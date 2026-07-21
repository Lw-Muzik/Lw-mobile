import 'package:flutter/material.dart';

import 'song_tile.dart';

/// Lightweight shimmer placeholder shown while the very first library scan is
/// still populating the database. Local tabs used to show a bare spinner while
/// cloud tabs had proper skeletons; this brings them to parity. Once the DB has
/// rows, cold opens are instant and this is never seen.
class SongListSkeleton extends StatefulWidget {
  const SongListSkeleton({super.key, this.rows = 12});

  final int rows;

  @override
  State<SongListSkeleton> createState() => _SongListSkeletonState();
}

class _SongListSkeletonState extends State<SongListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final alpha = 0.04 + (_c.value * 0.06);
        final block = base.withValues(alpha: alpha);
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemExtent: kSongTileExtent,
          itemCount: widget.rows,
          itemBuilder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 140,
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
