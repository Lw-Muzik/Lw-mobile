import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Routes/routes.dart';
import '../Shaders/RipplePainter.dart';

class AssetLoader extends StatefulWidget {
  const AssetLoader({super.key});

  @override
  State<AssetLoader> createState() => _AssetLoaderState();
}

class _AssetLoaderState extends State<AssetLoader>
    with TickerProviderStateMixin {
  List<Ripple> _ripples = [];
  @override
  void initState() {
    super.initState();

    _ripples = List.generate(
      7,
      (i) => Ripple(
        controller: _createAnimationController(),
      ),
    );
    _startAnimations();
    Timer.periodic(const Duration(seconds: 1), (timer) {
      // check if artwork is loaded
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.getBool("artworkLoaded") != null &&
            prefs.getBool("artworkLoaded") == true) {
          timer.cancel();
          Future.delayed(const Duration(seconds: 4), () {
            Navigator.pushReplacementNamed(context, Routes.home);
          });
        }
      });
    });
  }

  AnimationController _createAnimationController() {
    return AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 2000), // Adjust the duration as needed.
    )..addListener(() {
        setState(() {});
      });
  }

  void _startAnimations() {
    for (int i = 0; i < _ripples.length; i++) {
      final ripple = _ripples[i];
      Future.delayed(Duration(seconds: i), () {
        ripple.controller.repeat();
      });
    }
  }

  @override
  void dispose() {
    for (var ripple in _ripples) {
      ripple.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDBF3E),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: CustomPaint(
              size: const Size(150, 150),
              painter: RipplePainter(_ripples),
              child: Image.asset(
                "assets/icon.png",
                width: 220,
                height: 220,
              ),
            ),
          ),
          SizedBox.square(
            dimension: MediaQuery.of(context).size.width / 2,
          ),
          Text(
            "Loading assets, please wait...",
            style: Theme.of(context)
                .textTheme
                .titleLarge!
                .apply(color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class Ripple {
  final AnimationController controller;

  Ripple({required this.controller});
}
