import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ── Per-particle data ──────────────────────────────────────────────────────

/// Intrinsic state: the phase offset is fixed for the lifetime of the particle.
/// Extrinsic state: the position is randomised on every completed cycle.
///
/// [position] is a fractional coordinate in [0, 1] × [0, 1] that is scaled
/// to actual pixels at paint time, so it is size-independent at init.
class _RaindropParticle {
  Offset position;

  /// This particle's starting offset in the shared [0, 1] controller cycle.
  /// Particles are spread evenly so they never all peak simultaneously.
  final double phaseOffset;

  _RaindropParticle({required this.position, required this.phaseOffset});
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
/// RaindropFadeField.text(
///   maxAnimationCount: 8,
///   text: '漢',
///   textStyle: TextStyle(fontSize: 48),
/// )
/// RaindropFadeField.image(
///   maxAnimationCount: 5,
///   imageProvider: AssetImage('assets/drop.png'),
/// )
/// ```
abstract class RaindropFadeField extends StatefulWidget {
  final Color backgroundColor;
  final int maxAnimationCount;
  final Duration duration;

  /// Maximum rendered size of a single particle at full scale.
  final Size particleSize;

  const RaindropFadeField({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.maxAnimationCount = 5,
    this.duration = const Duration(milliseconds: 1500),
    this.particleSize = const Size(80, 80),
  });

  factory RaindropFadeField.image({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required ImageProvider imageProvider,
  }) =>
      _RaindropFadeFieldImage(
        key: key,
        backgroundColor: backgroundColor,
        maxAnimationCount: maxAnimationCount,
        duration: duration,
        particleSize: particleSize,
        imageProvider: imageProvider,
      );

  factory RaindropFadeField.text({
    Key? key,
    Color backgroundColor = Colors.transparent,
    int maxAnimationCount = 5,
    Duration duration = const Duration(milliseconds: 1500),
    Size particleSize = const Size(80, 80),
    required String text,
    TextStyle? textStyle,
  }) =>
      _RaindropFadeFieldText(
        key: key,
        backgroundColor: backgroundColor,
        maxAnimationCount: maxAnimationCount,
        duration: duration,
        particleSize: particleSize,
        text: text,
        textStyle: textStyle,
      );
}

// ── Private concrete widget subclasses ────────────────────────────────────

class _RaindropFadeFieldImage extends RaindropFadeField {
  const _RaindropFadeFieldImage({
    super.key,
    super.backgroundColor,
    super.maxAnimationCount,
    super.duration,
    super.particleSize,
    required this.imageProvider,
  });

  final ImageProvider imageProvider;

  @override
  State<_RaindropFadeFieldImage> createState() => _RaindropFadeFieldImageState();
}

class _RaindropFadeFieldText extends RaindropFadeField {
  const _RaindropFadeFieldText({
    super.key,
    super.backgroundColor,
    super.maxAnimationCount,
    super.duration,
    super.particleSize,
    required this.text,
    this.textStyle,
  });

  final String text;
  final TextStyle? textStyle;

  @override
  State<_RaindropFadeFieldText> createState() => _RaindropFadeFieldTextState();
}

// ── Abstract state — shared controller + particle management ───────────────

abstract class _RaindropFadeFieldState<T extends RaindropFadeField>
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

  List<_RaindropParticle> _buildParticles(int count) => List.generate(
        count,
        (i) => _RaindropParticle(
          position: Offset(_random.nextDouble(), _random.nextDouble()),
          phaseOffset: i / count,
        ),
      );

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

class _RaindropFadeFieldImageState
    extends _RaindropFadeFieldState<_RaindropFadeFieldImage> {
  ui.Image? _resolvedImage;
  ImageStream? _imageStream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(_onImageLoaded);
    _resolveImage();
  }

  @override
  void didUpdateWidget(_RaindropFadeFieldImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _imageStream?.removeListener(_listener);
      _resolveImage();
    }
  }

  void _resolveImage() {
    _imageStream = widget.imageProvider.resolve(ImageConfiguration.empty)
      ..addListener(_listener);
  }

  void _onImageLoaded(ImageInfo info, bool _) {
    if (mounted) setState(() => _resolvedImage = info.image);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_listener);
    super.dispose();
  }

  @override
  CustomPainter buildPainter() => _RaindropFieldImagePainter(
        repaint: _controller,
        particles: _particles,
        controller: _controller,
        image: _resolvedImage,
        particleSize: widget.particleSize,
      );
}

class _RaindropFadeFieldTextState
    extends _RaindropFadeFieldState<_RaindropFadeFieldText> {
  @override
  CustomPainter buildPainter() => _RaindropFieldTextPainter(
        repaint: _controller,
        particles: _particles,
        controller: _controller,
        text: widget.text,
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
  void drawContent(Canvas canvas);

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
      _withOpacity(canvas, opacity, () => drawContent(canvas));

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
  final List<_RaindropParticle> particles;
  @override
  final AnimationController controller;
  @override
  final Size particleSize;
  final ui.Image? image;

  _RaindropFieldImagePainter({
    required Listenable repaint,
    required this.particles,
    required this.controller,
    required this.particleSize,
    required this.image,
  }) : super(repaint: repaint);

  @override
  void drawContent(Canvas canvas) {
    final img = image;
    if (img == null) return;

    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(
        center: Offset.zero,
        width: particleSize.width,
        height: particleSize.height);
    canvas.drawImageRect(img, src, dst, Paint());
  }

  @override
  void paint(Canvas canvas, Size size) => paintParticles(canvas, size);

  @override
  bool shouldRepaint(_RaindropFieldImagePainter old) =>
      old.image != image ||
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
  final String text;
  final TextStyle? textStyle;

  static const _defaultStyle = TextStyle(color: Colors.white, fontSize: 30);

  // Cached TextPainter — rebuilt only when text or style changes.
  late TextPainter _textPainter;

  _RaindropFieldTextPainter({
    required Listenable repaint,
    required this.particles,
    required this.controller,
    required this.particleSize,
    required this.text,
    this.textStyle,
  }) : super(repaint: repaint) {
    _buildTextPainter();
  }

  void _buildTextPainter() {
    final style = _defaultStyle.merge(textStyle);
    _textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: particleSize.width);
  }

  @override
  void drawContent(Canvas canvas) {
    // Draw centred at origin (the canvas has already been translated to the
    // particle centre, so offset by half the text dimensions).
    final offset = Offset(
      -_textPainter.width / 2,
      -_textPainter.height / 2,
    );
    _textPainter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) => paintParticles(canvas, size);

  @override
  bool shouldRepaint(_RaindropFieldTextPainter old) =>
      old.text != text ||
      old.textStyle != textStyle ||
      old.particles != particles ||
      old.particleSize != particleSize;
}
