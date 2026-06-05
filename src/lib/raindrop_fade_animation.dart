import 'package:flutter/widgets.dart';

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
  const RaindropFadeAnimation({super.key});

  factory RaindropFadeAnimation.image({
    Key? key,
    required ImageProvider imageProvider,
  }) =>
      _RaindropFadeImageAnimation(key: key, imageProvider: imageProvider);

  factory RaindropFadeAnimation.text({
    Key? key,
    required String text,
  }) =>
      _RaindropFadeTextAnimation(key: key, text: text);
}

// ── Private concrete widget subclasses ────────────────────────────────────

class _RaindropFadeImageAnimation extends RaindropFadeAnimation {
  const _RaindropFadeImageAnimation({
    super.key,
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
    required this.text,
  });

  final String text;

  @override
  State<_RaindropFadeTextAnimation> createState() => _RaindropFadeTextState();
}

// ── Abstract state — shared animation logic lives here ─────────────────────

/// Base state that drives the scale + opacity animation.
///
/// Subclasses only need to implement [buildContent]; this class handles
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
  Widget buildContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // [child] is built once by [buildContent] and passed through unchanged.
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: child,
        ),
      ),
      child: buildContent(context),
    );
  }
}

// ── Concrete states — only the content differs ─────────────────────────────

class _RaindropFadeImageState
    extends _RaindropFadeAnimationState<_RaindropFadeImageAnimation> {
  @override
  Widget buildContent(BuildContext context) {
    return Image(image: widget.imageProvider);
  }
}

class _RaindropFadeTextState
    extends _RaindropFadeAnimationState<_RaindropFadeTextAnimation> {
  @override
  Widget buildContent(BuildContext context) {
    return Text(widget.text);
  }
}
