import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ── Public abstract widget ─────────────────────────────────────────────────

/// A widget that animates its content with a raindrop-like fade effect:
/// the content fades in small, grows to full size, then fades out.
///
/// Use the named factory constructors to create an image or text variant:
///
/// ```dart
/// RaindropFadeAnimation.image(imageProvider: AssetImage('assets/drop.png'))
/// RaindropFadeAnimation.text(text: 'Hello')
/// ```
abstract class RaindropFadeAnimation extends StatefulWidget {
  final Color backgroundColor;
  final Widget child;
  final bool repeats;

  const RaindropFadeAnimation({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.child = const SizedBox.shrink(),
    this.repeats = true,
  });

  factory RaindropFadeAnimation.image({
    Key? key,
    Color backgroundColor = Colors.transparent,
    Widget child = const SizedBox.shrink(),
    bool repeats = true,
    required ImageProvider imageProvider,
  }) =>
      _RaindropFadeImageAnimation(
        key: key,
        imageProvider: imageProvider,
        backgroundColor: backgroundColor,
        repeats: repeats,
        child: child,
      );

  factory RaindropFadeAnimation.text({
    Key? key,
    Color backgroundColor = Colors.transparent,
    Widget child = const SizedBox.shrink(),
    bool repeats = true,
    required String text,
    TextStyle? textStyle,
  }) =>
      _RaindropFadeTextAnimation(
        key: key,
        text: text,
        textStyle: textStyle,
        backgroundColor: backgroundColor,
        repeats: repeats,
        child: child,
      );
}

// ── Private concrete widget subclasses ────────────────────────────────────

class _RaindropFadeImageAnimation extends RaindropFadeAnimation {
  const _RaindropFadeImageAnimation({
    super.key,
    super.backgroundColor,
    super.child,
    super.repeats,
    required this.imageProvider,
  });

  final ImageProvider imageProvider;

  @override
  State<_RaindropFadeImageAnimation> createState() =>
      _RaindropFadeImageState();
}

class _RaindropFadeTextAnimation extends RaindropFadeAnimation {
  const _RaindropFadeTextAnimation({
    super.key,
    super.backgroundColor,
    super.child,
    super.repeats,
    required this.text,
    this.textStyle,
  });

  final String text;
  final TextStyle? textStyle;

  @override
  State<_RaindropFadeTextAnimation> createState() => _RaindropFadeTextState();
}

// ── Abstract state — shared animation logic lives here ─────────────────────

/// Base state that drives the scale + opacity animation.
///
/// Subclasses only need to implement [buildPainter]; this class handles
/// the full animation lifecycle via the Template Method pattern.
///
/// The [AnimationController] is passed to each painter as its [repaint]
/// listenable, so [CustomPaint] repaints on every animation tick without
/// needing [AnimatedBuilder] or [setState].
abstract class _RaindropFadeAnimationState<T extends RaindropFadeAnimation>
    extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      //TODO: parameterize this
      duration: const Duration(milliseconds: 800),
    //TODO: stop animation by fast forwarding the remaining objects
    )..repeat();

    // Grows from a small point to full size over the whole duration.
    _scale = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Fades in quickly (first 40%), then fades out slowly (remaining 60%).
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  /// Subclasses return a painter that will be animated.
  ///
  /// Called once per [build]. The painter receives [_controller] as its
  /// repaint listenable and the current animation values so [paint] can
  /// apply scale and opacity without any widget rebuilds.
  CustomPainter buildPainter();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: CustomPaint(
        // The painter reads _scale.value / _opacity.value each frame and
        // is scheduled to repaint by _controller via the repaint listenable.
        painter: buildPainter(),
        child: widget.child,
      ),
    );
  }
}

// ── Concrete states — only the painter construction differs ────────────────

class _RaindropFadeImageState
    extends _RaindropFadeAnimationState<_RaindropFadeImageAnimation> {
  /// The resolved [dart:ui Image], populated once the [ImageProvider] stream
  /// delivers its first frame.
  ui.Image? _resolvedImage;
  ImageStream? _imageStream;
  late final ImageStreamListener _imageStreamListener;

  @override
  void initState() {
    super.initState();
    _imageStreamListener = ImageStreamListener(_onImageLoaded);
    _resolveImage();
  }

  @override
  void didUpdateWidget(_RaindropFadeImageAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _imageStream?.removeListener(_imageStreamListener);
      _resolveImage();
    }
  }

  void _resolveImage() {
    _imageStream = widget.imageProvider
        .resolve(ImageConfiguration.empty)
      ..addListener(_imageStreamListener);
  }

  void _onImageLoaded(ImageInfo info, bool synchronousCall) {
    if (mounted) {
      setState(() => _resolvedImage = info.image);
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    super.dispose();
  }

  @override
  CustomPainter buildPainter() {
    return RaindropFadeImagePainter(
      repaint: _controller,
      image: _resolvedImage,
      scale: _scale,
      opacity: _opacity,
    );
  }
}

class _RaindropFadeTextState
    extends _RaindropFadeAnimationState<_RaindropFadeTextAnimation> {
  @override
  CustomPainter buildPainter() {
    return RaindropFadeTextPainter(
      repaint: _controller,
      text: widget.text,
      textStyle: widget.textStyle,
      scale: _scale,
      opacity: _opacity,
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────────

/// Applies [scale] and [opacity] to the canvas before drawing, so that
/// the animation is driven entirely inside [paint] with no widget rebuilds.
///
/// [repaint] should be the [AnimationController] so that [CustomPaint]
/// schedules a repaint on every animation tick.
class RaindropFadeImagePainter extends CustomPainter {
  final ui.Image? image;
  final Animation<double> scale;
  final Animation<double> opacity;

  RaindropFadeImagePainter({
    required Listenable repaint,
    required this.image,
    required this.scale,
    required this.opacity,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final resolvedImage = image;
    if (resolvedImage == null) return; // still loading

    final paint = Paint()..color = Color.fromRGBO(255, 255, 255, opacity.value);

    // Pivot the scale transform around the centre of the canvas.
    final centre = size.center(Offset.zero);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale.value);
    canvas.translate(-centre.dx, -centre.dy);

    // Fit the image inside the available area.
    final src = Rect.fromLTWH(
      0,
      0,
      resolvedImage.width.toDouble(),
      resolvedImage.height.toDouble(),
    );
    final dst = Offset.zero & size;
    canvas.drawImageRect(resolvedImage, src, dst, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(RaindropFadeImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.scale != scale ||
        oldDelegate.opacity != opacity;
  }
}

class RaindropFadeTextPainter extends CustomPainter {
  final String text;
  final TextStyle? textStyle;
  final Animation<double> scale;
  final Animation<double> opacity;

  static const TextStyle _defaultStyle = TextStyle(
    color: Colors.white,
    fontSize: 30,
  );

  RaindropFadeTextPainter({
    required Listenable repaint,
    required this.text,
    required this.scale,
    required this.opacity,
    this.textStyle,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Merge the caller's style on top of the default, then apply opacity.
    final effectiveStyle = _defaultStyle.merge(textStyle).copyWith(
          color: (_defaultStyle.merge(textStyle).color ?? Colors.white)
              .withOpacity(opacity.value),
        );

    final span = TextSpan(text: text, style: effectiveStyle);
    final textPainter =
        TextPainter(text: span, textDirection: TextDirection.ltr)
          ..layout(minWidth: 0, maxWidth: size.width);

    // Pivot the scale transform around the centre of the text.
    final centre = Alignment.center.alongSize(size);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale.value);
    canvas.translate(-centre.dx, -centre.dy);

    // Draw centred in the canvas.
    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);

    canvas.restore();
  }

  @override
  bool shouldRepaint(RaindropFadeTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.scale != scale ||
        oldDelegate.opacity != opacity;
  }
}
