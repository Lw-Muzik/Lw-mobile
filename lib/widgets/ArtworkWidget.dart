import 'dart:ui';

import '/exports/exports.dart';
import '../Helpers/index.dart';

class ArtworkWidget extends StatefulWidget {
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
    this.width = 100,
    this.height = 100,
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
  State<ArtworkWidget> createState() => _ArtworkWidgetState();
}

class _ArtworkWidgetState extends State<ArtworkWidget> {
  // Memoized: the old StatelessWidget recreated the savedImage() future on
  // EVERY build (temp-dir lookup + file stat per rebuild, per tile). Now the
  // future is built once and only refreshed when the artwork identity or
  // required decode size actually changes.
  Future<ImageProvider>? _imageFuture;
  int? _decodeWidth;

  int _computeDecodeWidth(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final w = widget.width.isFinite && widget.width > 0
        ? widget.width
        : MediaQuery.of(context).size.width;
    // Physical pixels needed for crisp display, bounded so decoded bitmaps
    // stay small (a full-res 3000px embedded cover is ~36MB RGBA).
    return (w * dpr).round().clamp(64, 1600);
  }

  void _ensureFuture(BuildContext context) {
    final decodeWidth = _computeDecodeWidth(context);
    if (_imageFuture != null && decodeWidth == _decodeWidth) return;
    _decodeWidth = decodeWidth;
    _imageFuture = savedImage(
      widget.path,
      widget.songId,
      type: widget.type,
      other: widget.other,
      quality: widget.quality,
      decodeWidth: decodeWidth,
    );
  }

  @override
  void didUpdateWidget(covariant ArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.songId != widget.songId ||
        oldWidget.other != widget.other ||
        oldWidget.type != widget.type) {
      _imageFuture = null; // identity changed — rebuild the future lazily
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureFuture(context);
    return FutureBuilder<ImageProvider>(
      future: _imageFuture,
      builder: (context, imageSnap) {
        return Container(
          margin: widget.margin,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
            image: DecorationImage(
              fit: widget.fit,
              colorFilter: widget.colorFilter,
              image: imageSnap.hasData
                  ? imageSnap.data!
                  : const AssetImage("assets/audio.jpeg"),
            ),
          ),
          child: widget.child,
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
