import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/fileloader.dart';
import '../Routes/routes.dart';
import '../Shaders/RipplePainter.dart';
import '/controllers/PlayerController.dart';

class AssetLoader extends StatefulWidget {
  const AssetLoader({super.key});

  @override
  State<AssetLoader> createState() => _AssetLoaderState();
}

class _AssetLoaderState extends State<AssetLoader>
    with TickerProviderStateMixin {
  static const int _rippleCount = 7;
  static const Duration _animationDuration = Duration(milliseconds: 2000);
  static const Duration _loadingDelay = Duration(seconds: 3);

  late final List<Ripple> _ripples;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _initializeRipples();
    _loadAssets();
  }

  void _initializeRipples() {
    _ripples = List.generate(
      _rippleCount,
      (i) => Ripple(
        controller: AnimationController(
          vsync: this,
          duration: _animationDuration,
        )..addListener(() {
            // Only call setState if the animation actually needs to update the UI
            if (mounted && i == 0) {
              setState(() {});
            }
          }),
      ),
    );

    _startRippleAnimations();
  }

  void _startRippleAnimations() {
    for (int i = 0; i < _ripples.length; i++) {
      Future.delayed(Duration(seconds: i), () {
        if (mounted) {
          _ripples[i].controller.repeat();
        }
      });
    }
  }

  Future<void> _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await fetchMetaData(context);
      await prefs.setBool("artworkLoaded", true);

      Future.delayed(_loadingDelay, () {
        if (mounted && !_isNavigating) {
          _isNavigating = true;
          Navigator.pushReplacementNamed(context, Routes.home);
          Routes.pop(context);
        }
      });
    } catch (e) {
      // Handle error appropriately
      debugPrint('Error loading assets: $e');
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
      backgroundColor: Colors.black,
      body: Consumer<PlayerController>(
        builder: (context, playerController, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRippleImage(),
            SizedBox(height: MediaQuery.of(context).size.width / 2),
            _buildTextSection(context, playerController),
          ],
        ),
      ),
    );
  }

  Widget _buildRippleImage() {
    return Center(
      child: CustomPaint(
        size: const Size(150, 150),
        painter: RipplePainter(_ripples),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Image.asset(
            "assets/audio.jpeg",
            width: 150,
            height: 150,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildTextSection(BuildContext context, PlayerController controller) {
    final textTheme = Theme.of(context).textTheme;
    const textStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );

    return Column(
      children: [
        Text(
          "Scanning",
          style: textTheme.titleLarge?.apply(color: Colors.white),
        ),
        Text(
          controller.textHeader,
          maxLines: 1,
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          controller.text,
          maxLines: 1,
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class Ripple {
  final AnimationController controller;

  const Ripple({required this.controller});
}
