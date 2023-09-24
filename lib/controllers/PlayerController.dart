import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'AppController.dart';

class PlayerController extends ChangeNotifier {
  PlayerController() {}
  final AppController _controller = AppController();
  AudioPlayer get player => _controller.audioHandler;
}
