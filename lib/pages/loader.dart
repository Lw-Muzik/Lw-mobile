import 'dart:async';

import 'package:eq_app/controllers/PlayerController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/fileloader.dart';
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
    permission();
    _ripples = List.generate(
      7,
      (i) => Ripple(
        controller: _createAnimationController(),
      ),
    );
    _startAnimations();
  }

  void permission() async {
    SharedPreferences.getInstance().then((prefs) async {
      await fetchMetaData(context).then((value) {
        prefs.setBool("artworkLoaded", true);
      });
      Future.delayed(const Duration(seconds: 4), () {
        Navigator.pushReplacementNamed(context, Routes.home);
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
            "Scanning",
            style: Theme.of(context)
                .textTheme
                .titleLarge!
                .apply(color: Colors.black),
          ),
          Text(
            Provider.of<PlayerController>(context, listen: false).textHeader,
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          Text(
            Provider.of<PlayerController>(context, listen: false).text,
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(color: Colors.black, fontWeight: FontWeight.bold),
          )
        ],
      ),
    );
  }
}

class Ripple {
  final AnimationController controller;

  Ripple({required this.controller});
}
