import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ── Per-particle data ──────────────────────────────────────────────────────

/// Intrinsic state: the phase offset is fixed for the lifetime of the particle.
/// Extrinsic state: the position is randomised on every completed cycle.
///
/// [position] is a fractional coordinate in [0, 1] × [0, 1] that is scaled
/// to actual pixels at paint time, so it is size-independent at init.
abstract class _RaindropIndividualParticle {
  Offset position;

  /// This particle's starting offset in the shared [0, 1] controller cycle.
  /// Particles are spread evenly so they never all peak simultaneously.
  final double phaseOffset;

  _RaindropIndividualParticle({required this.position, required this.phaseOffset});
}

class _RaindropIndividualTextParticle extends _RaindropIndividualParticle {
  String text;

  _RaindropIndividualTextParticle({required super.position, required super.phaseOffset, required this.text});
}

class _RaindropIndividualImageParticle extends _RaindropIndividualParticle {
  ImageProvider image;

  _RaindropIndividualImageParticle({required super.position, required super.phaseOffset, required this.image});
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
/// RaindropFadeIndividualField.texts(
///   maxAnimationCount: 8,
///   texts: ['漢', '字', '日', '本'],
///   textStyle: TextStyle(fontSize: 48),
/// )
/// RaindropFadeIndividualField.images(
///   maxAnimationCount: 5,
///   imageProviders: [AssetImage('assets/drop1.png'), AssetImage('assets/drop2.png')],
/// )
/// ```
abstract class RaindropFadeIndividualField extends StatefulWidget {
  final Color backgroundColor;
  final int maxAnimationCount;
  final Duration duration;

  /// Maximum rendered size of a single particle at full scale.
  final Size particleSize;

  const RaindropFadeIndividualField({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.maxAnimationCount = 5,
    this.duration = const Duration(milliseconds: 1500),
    this.particleSize = const Size(80, 80),
  });

  factory RaindropFadeIndividualField.images({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required List<ImageProvider> imageProviders,
  }) =>
      _RaindropFadeIndividualFieldImages(
        key: key,
        backgroundColor: backgroundColor,
        maxAnimationCount: maxAnimationCount,
        duration: duration,
        particleSize: particleSize,
        imageProviders: imageProviders,
      );

  factory RaindropFadeIndividualField.texts({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required List<String> texts,
    TextStyle? textStyle,
  }) =>
      _RaindropFadeIndividualFieldTexts(
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

class _RaindropFadeIndividualFieldImages extends RaindropFadeIndividualField {
  const _RaindropFadeIndividualFieldImages({
    super.key,
    super.backgroundColor,
    super.maxAnimationCount,
    super.duration,
    super.particleSize,
    required this.imageProviders,
  });

  final List<ImageProvider> imageProviders;

  @override
  State<_RaindropFadeIndividualFieldImages> createState() =>
      _RaindropFadeIndividualFieldImagesState();
}

class _RaindropFadeIndividualFieldTexts extends RaindropFadeIndividualField {
  const _RaindropFadeIndividualFieldTexts({
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
  State<_RaindropFadeIndividualFieldTexts> createState() =>
      _RaindropFadeIndividualFieldTextsState();
}

// ── Abstract state — shared controller + particle management ───────────────

abstract class _RaindropFadeIndividualFieldState<T extends RaindropFadeIndividualField>
    extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_RaindropIndividualParticle> _particles;

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

  List<_RaindropIndividualParticle> _buildParticles(int count);

  void _onParticleCycleComplete(_RaindropIndividualParticle particle);

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

class _RaindropFadeIndividualFieldImagesState
    extends _RaindropFadeIndividualFieldState<_RaindropFadeIndividualFieldImages> {
  final Map<ImageProvider, ui.Image> _resolvedImages = {};
  final List<(ImageStream, ImageStreamListener)> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _resolveImages();
  }

  @override
  void didUpdateWidget(_RaindropFadeIndividualFieldImages oldWidget) {
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
  List<_RaindropIndividualParticle> _buildParticles(int count) {
    if (widget.imageProviders.isEmpty) return [];
    return List.generate(
      count,
      (i) => _RaindropIndividualImageParticle(
        position: Offset(_random.nextDouble(), _random.nextDouble()),
        phaseOffset: i / count,
        image: widget.imageProviders[i % widget.imageProviders.length],
      ),
    );
  }

  @override
  void _onParticleCycleComplete(_RaindropIndividualParticle particle) {
    if (particle is _RaindropIndividualImageParticle && widget.imageProviders.isNotEmpty) {
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

class _RaindropFadeIndividualFieldTextsState
    extends _RaindropFadeIndividualFieldState<_RaindropFadeIndividualFieldTexts> {
  @override
  List<_RaindropIndividualParticle> _buildParticles(int count) {
    if (widget.texts.isEmpty) return [];
    return List.generate(
      count,
      (i) => _RaindropIndividualTextParticle(
        position: Offset(_random.nextDouble(), _random.nextDouble()),
        phaseOffset: i / count,
        text: widget.texts[i % widget.texts.length],
      ),
    );
  }

  @override
  void _onParticleCycleComplete(_RaindropIndividualParticle particle) {
    if (particle is _RaindropIndividualTextParticle && widget.texts.isNotEmpty) {
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
  List<_RaindropIndividualParticle> get particles;
  AnimationController get controller;
  Size get particleSize;

  /// Draws a single particle's content, centred at the canvas origin.
  /// The caller handles save/restore, translate, and scale.
  void drawContent(Canvas canvas, _RaindropIndividualParticle particle);

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

      // Let the concrete painter draw its content centred at the origin,
      // with opacity baked into its Paint / TextStyle.
      _withOpacity(canvas, opacity, () => drawContent(canvas, particle));

      canvas.restore();
    }
  }

  void _withOpacity(Canvas canvas, double opacity, VoidCallback draw) {
    // saveLayer creates an offscreen buffer; we composite it back at [opacity].
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    draw();
    canvas.restore();
  }
}

class _RaindropFieldImagePainter extends CustomPainter
    with _RaindropFieldPainterMixin {
  @override
  final List<_RaindropIndividualParticle> particles;
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
  void drawContent(Canvas canvas, _RaindropIndividualParticle particle) {
    if (particle is _RaindropIndividualImageParticle) {
      final img = resolvedImages[particle.image];
      if (img == null) return;

      final src = Rect.fromLTWH(
          0, 0, img.width.toDouble(), img.height.toDouble());
      final dst = Rect.fromCenter(
          center: Offset.zero,
          width: particleSize.width,
          height: particleSize.height);
      canvas.drawImageRect(img, src, dst, Paint());
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
  final List<_RaindropIndividualParticle> particles;
  @override
  final AnimationController controller;
  @override
  final Size particleSize;
  final TextStyle? textStyle;

  static const _defaultStyle = TextStyle(color: Colors.white, fontSize: 30);

  // Cached TextPainter — rebuilt only when text or style changes.
  final Map<String, TextPainter> _textPainterCache = {};

  _RaindropFieldTextPainter({
    required Listenable repaint,
    required this.particles,
    required this.controller,
    required this.particleSize,
    required List<String> texts,
    this.textStyle,
  }) : super(repaint: repaint) {
    _buildTextPainterCache(texts);
  }

  void _buildTextPainterCache(List<String> texts) {
    final style = _defaultStyle.merge(textStyle);
    for (final text in texts) {
      _getTextPainter(text, style);
    }
  }

  TextPainter _getTextPainter(String text, TextStyle style) {
    var tp = _textPainterCache[text];
    if (tp == null) {
      tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: particleSize.width);
      _textPainterCache[text] = tp;
    }
    return tp;
  }

  @override
  void drawContent(Canvas canvas, _RaindropIndividualParticle particle) {
    if (particle is _RaindropIndividualTextParticle) {
      final style = _defaultStyle.merge(textStyle);
      final tp = _getTextPainter(particle.text, style);
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
