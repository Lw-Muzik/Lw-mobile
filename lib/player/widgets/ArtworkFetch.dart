import 'dart:ui';

import 'package:flutter/material.dart';

import '../../apis/index.dart';

class ArtworkFetch extends StatefulWidget {
  final String title;
  final String path;
  final String artist;
  const ArtworkFetch(
      {super.key,
      required this.path,
      required this.title,
      required this.artist});

  @override
  State<ArtworkFetch> createState() => _ArtworkFetchState();
}

class _ArtworkFetchState extends State<ArtworkFetch> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
          // color: Colors.grey.shade400.withOpacity(0.15),
          ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: FutureBuilder(
          builder: (context, snap) {
            return snap.hasData && snap.data?.results != null
                ? GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    children: List.generate(
                      snap.data!.results.length,
                      (i) => InkWell(
                        onTap: () => Apis.downloadArtwork(
                            snap.data!.results[i].url, widget.path, context),
                        child: Image.network(snap.data!.results[i].url,
                            width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.image_not_supported_outlined);
                        }),
                      ),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  );
          },
          future: Apis.fetchArtWork(widget.title, widget.artist),
        ),
      ),
    );
  }
}
