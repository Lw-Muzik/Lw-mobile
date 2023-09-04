import 'package:flutter/material.dart';

import '../pages/Equalizer.dart';
import '../pages/Home.dart';
import '../player/PlayerUI.dart';

class Routes {
  static String home = "/";
  static String player = "/player";
  static String equalizer = "/equalizer";
  static void routeTo(Widget page, BuildContext context,
      {bool animate = false}) {
    if (animate) {
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (context) {
              return page;
            },
            fullscreenDialog: true),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 1000),
          reverseTransitionDuration: const Duration(milliseconds: 1000),
          pageBuilder: (context, animation, secondaryAnimation) {
            return FadeTransition(
              opacity: animation,
              child: page,
            );
          },
        ),
      );
    }
  }

  static void pop(BuildContext context) {
    Navigator.of(context).pop();
  }

  static Map<String, Widget Function(dynamic context)> routes() {
    return {
      player: (context) => const Player(),
      equalizer: (context) => const Equalizer(),
      home: (context) => const Home(),
    };
  }
}
