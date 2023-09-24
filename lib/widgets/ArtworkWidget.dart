import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../Helpers/index.dart';

class ArtworkWidget extends StatelessWidget {
  final String path;
  final String other;
  final int songId;
  final int quality;
  final ArtworkType type;
  final BoxFit fit;
  final BlendMode? blendMode;
  final double width;
  final double height;
  final BorderRadiusGeometry? borderRadius;
  final ColorFilter? colorFilter;
  final Widget? child;
  final bool useSaved;
  final int size;
  final EdgeInsetsGeometry? margin;
  const ArtworkWidget({
    super.key,
    this.path = "",
    required this.songId,
    this.type = ArtworkType.AUDIO,
    this.fit = BoxFit.cover,
    this.width = 56,
    this.height = 56,
    this.borderRadius,
    this.child,
    this.margin,
    this.colorFilter,
    this.other = "",
    this.quality = 70,
    this.size = 2,
    this.useSaved = true,
    this.blendMode,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider>(
      future:
          savedImage(path, songId, type: type, other: other, quality: quality),
      builder: (context, imageSnap) {
        return Container(
          margin: margin,
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(10),
            image: DecorationImage(
              fit: fit,
              colorFilter: colorFilter,
              image: imageSnap.hasData
                  ? imageSnap.data!
                  : const AssetImage("assets/audio.jpeg"),
            ),
          ),
          child: child,
        );
      },
    );
    // : FutureBuilder(
    //     future: OnAudioQuery.platform.queryArtwork(
    //       songId,
    //       type,
    //       quality: quality,
    //       format: ArtworkFormat.JPEG,
    //       size: size,
    //     ),
    //     builder: (context, imageSnap) {
    //       return Container(
    //         margin: margin,
    //         width: width,
    //         height: height,
    //         decoration: BoxDecoration(
    //           borderRadius: borderRadius,
    //           image: DecorationImage(
    //             fit: fit,
    //             colorFilter: colorFilter ??
    //                 ColorFilter.mode(
    //                     imageSnap.hasData ? Colors.black26 : Colors.black,
    //                     BlendMode.darken),
    //             image: imageSnap.hasData
    //                 ? MemoryImage(imageSnap.data!)
    //                 : const AssetImage("assets/audio.jpeg")
    //                     as ImageProvider,
    //           ),
    //         ),
    //         child: child,
    //       );
    //     },
    //   );
  }
}
