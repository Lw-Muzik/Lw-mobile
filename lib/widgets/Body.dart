import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

class Body extends StatelessWidget {
  final ArtworkType type;
  final int artworkId;
  final Widget child;
  const Body(
      {super.key,
      required this.type,
      required this.artworkId,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, controller, child) {
      return Stack(
        children: [
          QueryArtworkWidget(
            artworkBorder: BorderRadius.zero,
            format: ArtworkFormat.PNG,
            size: 5000,
            quality: 100,
            artworkWidth: MediaQuery.of(context).size.width,
            artworkHeight: MediaQuery.of(context).size.height,
            id: artworkId,
            nullArtworkWidget: Image.asset("assets/audio.jpeg"),
            type: type,
          ),
          child ?? Container()
        ],
      );
    });
  }
}
