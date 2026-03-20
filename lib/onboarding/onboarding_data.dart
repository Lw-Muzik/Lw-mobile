import 'package:flutter/material.dart';

class OnboardingPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> features;
  final Color accentColor;

  const OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.features,
    this.accentColor = const Color(0xFFD4A825),
  });
}

const List<OnboardingPage> onboardingPages = [
  OnboardingPage(
    title: 'Welcome to\nHype Muzik',
    subtitle: 'Your ultimate music experience',
    icon: Icons.headphones_rounded,
    features: [
      'Play local & cloud music',
      'Professional audio engine',
      'Beautiful visualizations',
    ],
  ),
  OnboardingPage(
    title: 'Studio-Grade\nEqualizer',
    subtitle: 'Shape your sound',
    icon: Icons.equalizer_rounded,
    features: [
      '32-band graphic EQ with presets',
      'Parametric EQ for surgical precision',
      'Bass & treble tone controls',
    ],
    accentColor: Color(0xFF5EC4D4),
  ),
  OnboardingPage(
    title: 'Room Effects\n& Spatial Audio',
    subtitle: 'Transform your listening space',
    icon: Icons.spatial_audio_rounded,
    features: [
      'Reverb with 11 room presets',
      'Stereo expander for wider soundstage',
      'Crossfeed for natural headphone listening',
    ],
    accentColor: Color(0xFF9C6ADE),
  ),
  OnboardingPage(
    title: 'Cloud\nStreaming',
    subtitle: 'Your music, everywhere',
    icon: Icons.cloud_rounded,
    features: [
      'Google Drive & Dropbox integration',
      'Smart caching saves mobile data',
      'Gapless playback & crossfade',
    ],
    accentColor: Color(0xFF4CAF50),
  ),
  OnboardingPage(
    title: 'Visualizers\n& Lyrics',
    subtitle: 'See your music come alive',
    icon: Icons.auto_awesome_rounded,
    features: [
      'Radial, spectrum & silk wave modes',
      'Synchronized lyrics display',
      'Track recognition with one tap',
    ],
    accentColor: Color(0xFFE91E63),
  ),
];
