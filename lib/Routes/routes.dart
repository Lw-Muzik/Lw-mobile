import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../pages/Equalizer.dart';
import '../pages/Home.dart';
import '../pages/loader.dart';
import '../player/PlayerUI.dart';

class Routes {
  static String home = "/";
  static String player = "/player";
  static String equalizer = "/equalizer";
  static String loader = "/assetLoader";
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
          transitionDuration: const Duration(milliseconds: 600),
          reverseTransitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondaryAnimation) {
            return DualTransitionBuilder(
              animation: animation,
              forwardBuilder: (context, anim, x) => FadeTransition(
                opacity: animation,
                child: page,
              ),
              reverseBuilder: (context, reverse, y) => ScaleTransition(
                scale: reverse,
                child: page,
              ),
            );
          },
        ),
      );
    }
  }

  static Widget animateTo(
      {required Widget closedWidget,
      required Widget openWidget,
      Duration duration = const Duration(milliseconds: 700)}) {
    return OpenContainer(
        closedElevation: 0,
        openElevation: 0,
        closedColor: Colors.transparent,
        openColor: Colors.transparent,
        transitionDuration: duration,
        transitionType: ContainerTransitionType.fade,
        closedBuilder: (context, fn) => closedWidget,
        openBuilder: (context, fn) => openWidget);
  }

  static void pop(BuildContext context) {
    Navigator.of(context).pop();
  }

  static Map<String, Widget Function(dynamic context)> routes() {
    return {
      player: (context) => const Player(),
      equalizer: (context) => const Equalizer(),
      home: (context) => const Home(),
      loader: (context) => const AssetLoader(),
    };
  }
}
