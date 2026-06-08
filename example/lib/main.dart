import 'package:flutter/material.dart';
import 'package:raindrop_fade_animation/raindrop_fade_animation.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int currentAnimation = 0;

  // #begin
  final multipleTexts = RaindropFadeAnimation.texts(
    texts: ['test', 'flutter', 'linux', 'pub.dev'],
    backgroundColor: Colors.blue,
    maxAnimationCount: 5,
    duration: Duration(milliseconds: 1500),
    particleSize: Size(200, 200),
    textStyle: TextStyle(fontSize: 28, color: Colors.white),);

  final multipleImages = RaindropFadeAnimation.images(
    imageProviders: [AssetImage('assets/flutter.png'), AssetImage('assets/tux.png'),],
    backgroundColor: Colors.blue,
    maxAnimationCount: 5,
    duration: Duration(milliseconds: 1500),
    particleSize: Size(200, 200),);
  // #end

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raindrop Fade Animation',
      home: Scaffold(
        backgroundColor: Colors.black,
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() {
            currentAnimation >= 1
              ? currentAnimation = 0
              : currentAnimation++;
          })
        ),
        body: SafeArea(
          child: SizedBox.expand(
            child: <Widget>[multipleTexts, multipleImages][currentAnimation],
          ),
        ),
      ),
    );
  }
}
