import 'package:animations/animations.dart';
import '/pages/index_page.dart';
import 'package:flutter/material.dart';

import '../pages/equalizer.dart';
import '../pages/loader.dart';
import '../player/player_ui.dart';

class Routes {
  static String home = "/";
  static String player = "/player";
  static String equalizer = "/equalizer";
  static String loader = "/assetLoader";

  static void routeTo(
    Widget page,
    BuildContext context, {
    bool animate = true,
  }) {
    if (!animate) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            return page;
          },
          fullscreenDialog: true,
        ),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) {
            return DualTransitionBuilder(
              animation: animation,
              forwardBuilder: (context, anim, x) =>
                  FadeTransition(opacity: animation, child: page),
              reverseBuilder: (context, reverse, y) =>
                  ScaleTransition(scale: reverse, child: page),
            );
          },
        ),
      );
    }
  }

  static Widget animateTo({
    required Widget closedWidget,
    required Widget openWidget,
    Duration duration = const Duration(milliseconds: 500),
  }) {
    return OpenContainer(
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: Colors.transparent,
      transitionDuration: duration,
      transitionType: ContainerTransitionType.fadeThrough,
      closedBuilder: (context, fn) => closedWidget,
      openBuilder: (context, fn) => openWidget,
    );
  }

  /// Premium detail-page transition: shared-axis Z (scale + fade)
  static void scaleTo(Widget page, BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.scaled,
            child: child,
          );
        },
      ),
    );
  }

  static void pop(BuildContext context) {
    Navigator.of(context).pop();
  }

  static Map<String, Widget Function(dynamic context)> routes() {
    return {
      player: (context) => const Player(),
      equalizer: (context) => const Equalizer(),
      home: (context) => const IndexPage(),
      loader: (context) => const AssetLoader(),
    };
  }
}
