import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioHandler with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;
}
