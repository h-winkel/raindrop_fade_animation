import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raindrop_fade_animation/raindrop_fade_animation.dart';

void main() {
  testWidgets('RaindropFadeAnimation smoke test', (WidgetTester tester) async {
    // Build the widget with texts.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RaindropFadeAnimation.texts(
            texts: ['Test'],
            maxAnimationCount: 1,
          ),
        ),
      ),
    );

    // Verify it builds without crashing.
    // We use a predicate to find the widget because it might be a private subclass
    expect(find.byWidgetPredicate((widget) => widget is RaindropFadeAnimation), findsOneWidget);

    // Pump a frame to trigger the animation controller.
    await tester.pump(const Duration(milliseconds: 100));
    
    // Verify it still exists.
    expect(find.byWidgetPredicate((widget) => widget is RaindropFadeAnimation), findsOneWidget);
  });
}
