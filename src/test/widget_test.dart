import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  //testWidgets('', (tester) async {
  //  expect(true, false);
  //});

  testWidgets('the widget can show an animated image', (tester) async {
    await tester.pumpWidget(RaindropFade.image(
      path: 'assets/flutter.png', animationCount: AnimationCount.one));
    await tester.pump(Duration(milliseconds: 200));

    final animatedWidget = find.byType(CustomPaint);
    expectLater(
      animatedWidget,
      matchesGoldenFile('goldens/one_animated_flutter_logo.png'));
  });

  testWidgets('the widget can show animated texts', (tester) async {
    await tester.pumpWidget(RaindropFade.text(
      path: 'text', animationCount: AnimationCount.one));
    await tester.pump(Duration(milliseconds: 200));

    final animatedWidget = find.byType(CustomPaint);
    expectLater(
      animatedWidget,
      matchesGoldenFile('goldens/one_animated_text_text.png'));
  });

  testWidgets('the widget can show its children', (tester) async {
    expect(true, false);
  });
}
