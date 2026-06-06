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

  const RaindropFadeAnimation({
    super.key,
    this.backgroundColor = Colors.transparent,
    this.child = const SizedBox.shrink()});

  factory RaindropFadeAnimation.image({
    Key? key,
    Color backgroundColor = Colors.transparent,
    Widget child = const SizedBox.shrink(),
    required ImageProvider imageProvider,
  }) =>
      _RaindropFadeImageAnimation(key: key, imageProvider: imageProvider, backgroundColor: backgroundColor, child: child);

  factory RaindropFadeAnimation.text({
    Key? key,
    Color backgroundColor = Colors.transparent,
    Widget child = const SizedBox.shrink(),
    required String text,
  }) =>
      _RaindropFadeTextAnimation(key: key, text: text, backgroundColor: backgroundColor, child: child);
}

// ── Private concrete widget subclasses ────────────────────────────────────

class _RaindropFadeImageAnimation extends RaindropFadeAnimation {
  const _RaindropFadeImageAnimation({
    super.key,
    super.backgroundColor = Colors.transparent,
    super.child = const SizedBox.shrink(),
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
    super.backgroundColor = Colors.transparent,
    super.child = const SizedBox.shrink(),
    required this.text,
  });

  final String text;

  @override
  State<_RaindropFadeTextAnimation> createState() => _RaindropFadeTextState();
}

// ── Abstract state — shared animation logic lives here ─────────────────────

/// Base state that drives the scale + opacity animation.
///
/// Subclasses only need to implement [buildPainter]; this class handles
/// the full animation lifecycle via the Template Method pattern.
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
      duration: const Duration(milliseconds: 800),
    )..forward();

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

  /// Subclasses return the content to animate (e.g. an [Image] or [Text]).
  ///
  /// This is called once and cached — it is not rebuilt on every animation
  /// frame, so it is safe to construct widgets here without concern for
  /// unnecessary rebuilds.
  CustomPainter buildPainter(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Expanded(
          child: ColoredBox(
            color: widget.backgroundColor,
            child: CustomPaint(
              painter: buildPainter(context),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Concrete states — only the content differs ─────────────────────────────

class _RaindropFadeImageState
    extends _RaindropFadeAnimationState<_RaindropFadeImageAnimation> {
  @override
  CustomPainter buildPainter(BuildContext context) {
    return RaindropFadeImagePainter(image: widget.imageProvider);
  }
}

class _RaindropFadeTextState
    extends _RaindropFadeAnimationState<_RaindropFadeTextAnimation> {
  @override
  CustomPainter buildPainter(BuildContext context) {
    return RaindropFadeTextPainter(text: widget.text);
  }
}

class RaindropFadeImagePainter extends CustomPainter {
  final ImageProvider image;

  RaindropFadeImagePainter({super.repaint, required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(
      //TODO: ImageProvider can't be passed, don't want to load image here
      image,
      Offset.zero,
      //TODO: this paint does not need to do anything
      Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class RaindropFadeTextPainter extends CustomPainter {
  final String text;

  RaindropFadeTextPainter({super.repaint, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    //TODO: parameterize these
    final style = TextStyle(color: Colors.white, fontSize: 30);
    final span = TextSpan(text: text, style: style);
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(minWidth: 0, maxWidth: size.width);

    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
