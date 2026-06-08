import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ── Per-particle data ──────────────────────────────────────────────────────

/// Intrinsic state: the phase offset is fixed for the lifetime of the particle.
/// Extrinsic state: the position is randomised on every completed cycle.
///
/// [position] is a fractional coordinate in [0, 1] × [0, 1] that is scaled
/// to actual pixels at paint time, so it is size-independent at init.
abstract class _RaindropParticle {
  Offset position;

  /// This particle's starting offset in the shared [0, 1] controller cycle.
  /// Particles are spread evenly so they never all peak simultaneously.
  final double phaseOffset;

  _RaindropParticle({required this.position, required this.phaseOffset});
}

class _RaindropTextParticle extends _RaindropParticle {
  String text;

  _RaindropTextParticle({required super.position, required super.phaseOffset, required this.text});
}

class _RaindropImageParticle extends _RaindropParticle {
  ImageProvider image;

  _RaindropImageParticle({required super.position, required super.phaseOffset, required this.image});
}

// ── Curve helpers (mirrors RaindropFadeAnimation curves) ───────────────────

/// Returns the scale value [0.2, 1.0] for a local animation time [0, 1],
/// matching the easeOut curve used by [RaindropFadeAnimation].
double _scaleAt(double t) {
  final eased = Curves.easeOut.transform(t.clamp(0.0, 1.0));
  return 0.2 + 0.8 * eased;
}

/// Returns the opacity value for a local animation time [0, 1]:
/// fades in over the first 40 %, fades out over the remaining 60 %.
double _opacityAt(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < 0.4) return t / 0.4;
  return 1.0 - (t - 0.4) / 0.6;
}

// ── Public abstract widget ─────────────────────────────────────────────────

/// Covers its entire area with [maxAnimationCount] simultaneous raindrop-fade
/// animations. Each particle animates independently at a staggered phase and
/// moves to a new random position after every completed cycle.
///
/// All particles share a single [AnimationController] and are drawn in a
/// single [CustomPainter] pass — O(1) ticker overhead regardless of count.
///
/// ```dart
/// RaindropFadeAnimation.texts(
///   maxAnimationCount: 8,
///   texts: ['漢', '字', '日', '本'],
///   textStyle: TextStyle(fontSize: 48),
/// )
/// RaindropFadeAnimation.images(
///   maxAnimationCount: 5,
///   imageProviders: [AssetImage('assets/drop1.png'), AssetImage('assets/drop2.png')],
/// )
/// ```
/// A widget that animates a field of raindrop-like fading particles.
///
/// Use [RaindropFadeAnimation.texts] to animate a collection of strings,
/// or [RaindropFadeAnimation.images] to animate a collection of [ImageProvider]s.
///
/// The widget covers its entire allocated area and randomly positions particles
/// that fade in and scale up, then fade out, mimicking raindrops hitting water.
abstract class RaindropFadeAnimation extends StatefulWidget {
  /// The background color of the entire animation field.
  final Color backgroundColor;

  /// The total number of particles animating simultaneously.
  /// Higher counts create a denser "rain" effect but require more processing.
  final int maxAnimationCount;

  /// The duration of a single particle's full lifecycle (fade in to fade out).
  final Duration duration;

  /// The maximum size a particle can reach at the peak of its animation (scale = 1.0).
  final Size particleSize;

  const RaindropFadeAnimation({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.maxAnimationCount = 5,
    this.duration = const Duration(milliseconds: 1500),
    this.particleSize = const Size(80, 80),
  });

  /// Creates an animation field that displays images.
  ///
  /// [imageProviders] is the list of images to cycle through.
  /// [maxAnimationCount] defaults to 5.
  /// [duration] defaults to 1.5 seconds.
  /// [particleSize] defaults to 80x80.
  factory RaindropFadeAnimation.images({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required List<ImageProvider> imageProviders,
  }) =>
      _RaindropFadeAnimationImages(
        key: key,
        backgroundColor: backgroundColor,
        maxAnimationCount: maxAnimationCount,
        duration: duration,
        particleSize: particleSize,
        imageProviders: imageProviders,
      );

  /// Creates an animation field that displays text characters or strings.
  ///
  /// [texts] is the list of strings to cycle through.
  /// [textStyle] allows customizing the appearance of the text.
  /// [maxAnimationCount] defaults to 5.
  /// [duration] defaults to 1.5 seconds.
  /// [particleSize] defaults to 80x80.
  factory RaindropFadeAnimation.texts({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required List<String> texts,
    TextStyle? textStyle,
  }) =>
      _RaindropFadeAnimationTexts(
        key: key,
        backgroundColor: backgroundColor,
        maxAnimationCount: maxAnimationCount,
        duration: duration,
        particleSize: particleSize,
        texts: texts,
        textStyle: textStyle,
      );
}

// ── Private concrete widget subclasses ────────────────────────────────────

class _RaindropFadeAnimationImages extends RaindropFadeAnimation {
  const _RaindropFadeAnimationImages({
    super.key,
    super.backgroundColor,
    super.maxAnimationCount,
    super.duration,
    super.particleSize,
    required this.imageProviders,
  });

  final List<ImageProvider> imageProviders;

  @override
  State<_RaindropFadeAnimationImages> createState() =>
      _RaindropFadeAnimationImagesState();
}

class _RaindropFadeAnimationTexts extends RaindropFadeAnimation {
  const _RaindropFadeAnimationTexts({
    super.key,
    super.backgroundColor,
    super.maxAnimationCount,
    super.duration,
    super.particleSize,
    required this.texts,
    this.textStyle,
  });

  final List<String> texts;
  final TextStyle? textStyle;

  @override
  State<_RaindropFadeAnimationTexts> createState() =>
      _RaindropFadeAnimationTextsState();
}

// ── Abstract state — shared controller + particle management ───────────────

abstract class _RaindropFadeAnimationState<T extends RaindropFadeAnimation>
    extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_RaindropParticle> _particles;

  final _random = Random();
  double _previousValue = 0.0;

  @override
  void initState() {
    super.initState();
    _particles = _buildParticles(widget.maxAnimationCount);
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_onTick)
      ..repeat();
  }

  List<_RaindropParticle> _buildParticles(int count);

  void _onParticleCycleComplete(_RaindropParticle particle);

  void _onTick() {
    final curr = _controller.value;
    final prev = _previousValue;

    for (final particle in _particles) {
      final p = particle.phaseOffset;
      // Detect a crossing of p by the controller this frame.
      // Handles both normal forward motion and the wrap from ~1.0 → 0.0.
      final crossed = (curr >= prev)
          ? (prev < p && p <= curr)
          : (p > prev || p <= curr);

      if (crossed) {
        particle.position = Offset(_random.nextDouble(), _random.nextDouble());
        _onParticleCycleComplete(particle);
      }
    }
    _previousValue = curr;
  }

  @override
  void deactivate() {
    // Fast-forward through the remaining cycle so particles fade out gracefully
    // during any exit transition rather than freezing mid-frame.
    _controller.animateTo(1.0);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.maxAnimationCount != widget.maxAnimationCount) {
      // Rebuild the particle list with re-distributed phase offsets.
      _particles = _buildParticles(widget.maxAnimationCount);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  CustomPainter buildPainter();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: CustomPaint(
        painter: buildPainter(),
        // SizedBox.expand makes CustomPaint fill whatever constraints it gets.
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ── Concrete states ────────────────────────────────────────────────────────

class _RaindropFadeAnimationImagesState
    extends _RaindropFadeAnimationState<_RaindropFadeAnimationImages> {
  final Map<ImageProvider, ui.Image> _resolvedImages = {};
  final List<(ImageStream, ImageStreamListener)> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _resolveImages();
  }

  @override
  void didUpdateWidget(_RaindropFadeAnimationImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_areListsEqual(oldWidget.imageProviders, widget.imageProviders)) {
      _cleanupStreams();
      _resolveImages();
    }
  }

  bool _areListsEqual(List<ImageProvider> a, List<ImageProvider> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _resolveImages() {
    for (final provider in widget.imageProviders) {
      final stream = provider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((ImageInfo info, bool _) {
        if (mounted) {
          setState(() {
            _resolvedImages[provider] = info.image;
          });
        }
      });
      stream.addListener(listener);
      _subscriptions.add((stream, listener));
    }
  }

  void _cleanupStreams() {
    for (final (stream, listener) in _subscriptions) {
      stream.removeListener(listener);
    }
    _subscriptions.clear();
    _resolvedImages.clear();
  }

  @override
  void dispose() {
    _cleanupStreams();
    super.dispose();
  }

  @override
  List<_RaindropParticle> _buildParticles(int count) {
    if (widget.imageProviders.isEmpty) return [];
    return List.generate(
      count,
      (i) => _RaindropImageParticle(
        position: Offset(_random.nextDouble(), _random.nextDouble()),
        phaseOffset: i / count,
        image: widget.imageProviders[i % widget.imageProviders.length],
      ),
    );
  }

  @override
  void _onParticleCycleComplete(_RaindropParticle particle) {
    if (particle is _RaindropImageParticle && widget.imageProviders.isNotEmpty) {
      particle.image = widget.imageProviders[_random.nextInt(widget.imageProviders.length)];
    }
  }

  @override
  CustomPainter buildPainter() => _RaindropFieldImagePainter(
        repaint: _controller,
        particles: _particles,
        controller: _controller,
        resolvedImages: _resolvedImages,
        particleSize: widget.particleSize,
      );
}

class _RaindropFadeAnimationTextsState
    extends _RaindropFadeAnimationState<_RaindropFadeAnimationTexts> {
  @override
  List<_RaindropParticle> _buildParticles(int count) {
    if (widget.texts.isEmpty) return [];
    return List.generate(
      count,
      (i) => _RaindropTextParticle(
        position: Offset(_random.nextDouble(), _random.nextDouble()),
        phaseOffset: i / count,
        text: widget.texts[i % widget.texts.length],
      ),
    );
  }

  @override
  void _onParticleCycleComplete(_RaindropParticle particle) {
    if (particle is _RaindropTextParticle && widget.texts.isNotEmpty) {
      particle.text = widget.texts[_random.nextInt(widget.texts.length)];
    }
  }

  @override
  CustomPainter buildPainter() => _RaindropFieldTextPainter(
        repaint: _controller,
        particles: _particles,
        controller: _controller,
        texts: widget.texts,
        textStyle: widget.textStyle,
        particleSize: widget.particleSize,
      );
}

// ── Painters ───────────────────────────────────────────────────────────────

/// Base mixin with the per-particle draw loop shared by both painter variants.
mixin _RaindropFieldPainterMixin {
  List<_RaindropParticle> get particles;
  AnimationController get controller;
  Size get particleSize;

  /// Draws a single particle's content, centred at the canvas origin.
  /// The caller handles save/restore, translate, and scale.
  void drawContent(Canvas canvas, _RaindropParticle particle, double opacity);

  void paintParticles(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Local time in [0, 1] for this particle, accounting for its phase.
      final localTime =
          (controller.value - particle.phaseOffset + 1.0) % 1.0;
      final scale = _scaleAt(localTime);
      final opacity = _opacityAt(localTime);

      if (opacity <= 0.0) continue; // skip invisible particles

      // Convert fractional position to canvas coordinates.
      final cx = particle.position.dx * size.width;
      final cy = particle.position.dy * size.height;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(scale);

      // Clip to particleSize so images / text don't overflow at full scale.
      canvas.clipRect(Rect.fromCenter(
        center: Offset.zero,
        width: particleSize.width,
        height: particleSize.height,
      ));

      // Let the concrete painter draw its content centred at the origin.
      drawContent(canvas, particle, opacity);

      canvas.restore();
    }
  }
}

class _RaindropFieldImagePainter extends CustomPainter
    with _RaindropFieldPainterMixin {
  @override
  final List<_RaindropParticle> particles;
  @override
  final AnimationController controller;
  @override
  final Size particleSize;
  final Map<ImageProvider, ui.Image> resolvedImages;

  _RaindropFieldImagePainter({
    required Listenable repaint,
    required this.particles,
    required this.controller,
    required this.particleSize,
    required this.resolvedImages,
  }) : super(repaint: repaint);

  @override
  void drawContent(Canvas canvas, _RaindropParticle particle, double opacity) {
    if (particle is _RaindropImageParticle) {
      final img = resolvedImages[particle.image];
      if (img == null) return;

      final src = Rect.fromLTWH(
          0, 0, img.width.toDouble(), img.height.toDouble());
      final dst = Rect.fromCenter(
          center: Offset.zero,
          width: particleSize.width,
          height: particleSize.height);
      
      // Apply opacity directly to the Paint object.
      final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
      canvas.drawImageRect(img, src, dst, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintParticles(canvas, size);

  @override
  bool shouldRepaint(_RaindropFieldImagePainter old) =>
      old.resolvedImages != resolvedImages ||
      old.particles != particles ||
      old.particleSize != particleSize;
}

class _RaindropFieldTextPainter extends CustomPainter
    with _RaindropFieldPainterMixin {
  @override
  final List<_RaindropParticle> particles;
  @override
  final AnimationController controller;
  @override
  final Size particleSize;
  final TextStyle? textStyle;

  static const _defaultStyle = TextStyle(color: Colors.white, fontSize: 30);

  _RaindropFieldTextPainter({
    required Listenable repaint,
    required this.particles,
    required this.controller,
    required this.particleSize,
    required List<String> texts,
    this.textStyle,
  }) : super(repaint: repaint);

  @override
  void drawContent(Canvas canvas, _RaindropParticle particle, double opacity) {
    if (particle is _RaindropTextParticle) {
      final baseStyle = _defaultStyle.merge(textStyle);
      // Apply opacity to the text color.
      final styleWithOpacity = baseStyle.copyWith(
        color: (baseStyle.color ?? Colors.white).withValues(alpha: opacity),
      );

      final tp = TextPainter(
        text: TextSpan(text: particle.text, style: styleWithOpacity),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: particleSize.width);

      final offset = Offset(
        -tp.width / 2,
        -tp.height / 2,
      );
      tp.paint(canvas, offset);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintParticles(canvas, size);

  @override
  bool shouldRepaint(_RaindropFieldTextPainter old) =>
      old.textStyle != textStyle ||
      old.particles != particles ||
      old.particleSize != particleSize;
}
