/// Everything the user owns, one way of looking at it at a time.
///
/// These six views used to be six of the eight tabs in a scrolling strip at the
/// top of the app. They are *modes of looking at one collection*, not
/// destinations — which is what a segmented control says and a tab strip does
/// not.
///
/// The views themselves are unchanged. None of them carries a `Scaffold`; they
/// are bodies, which is why they can be hosted here as they are.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../themes/ember.dart';
import '../albums.dart';
import '../artists.dart';
import '../folders.dart';
import '../genres.dart';
import '../play_list_view.dart';
import '../songs.dart';

class LibrarySurface extends StatefulWidget {
  const LibrarySurface({super.key});

  @override
  State<LibrarySurface> createState() => _LibrarySurfaceState();
}

class _LibrarySurfaceState extends State<LibrarySurface> {
  int _mode = 0;

  /// Folders and Playlists are Android-only — `queryPlaylists` is documented in
  /// `play_list_view.dart` as unsupported on iOS.
  late final List<_Mode> _modes = [
    const _Mode('Songs', Icons.music_note_rounded, AllSongs()),
    const _Mode('Albums', Icons.album_rounded, Albums()),
    const _Mode('Artists', Icons.person_rounded, Artists()),
    const _Mode('Genres', Icons.category_rounded, Genres()),
    if (Platform.isAndroid) ...[
      const _Mode('Folders', Icons.folder_rounded, Folders()),
      const _Mode('Playlists', Icons.queue_music_rounded, PlayListView()),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: Ember.gutter - 6),
            itemCount: _modes.length,
            itemBuilder: (context, index) => _chip(index),
          ),
        ),
        // A hairline under the control, so the modes read as a header over the
        // list rather than as the first row of it.
        Container(height: 0.5, color: Ember.outline),
        const SizedBox(height: 4),
        // IndexedStack rather than swapping children: switching back to a mode
        // should return to where it was scrolled, not to the top of a list
        // rebuilt from scratch.
        Expanded(
          child: IndexedStack(
            index: _mode,
            children: [for (final mode in _modes) mode.view],
          ),
        ),
      ],
    );
  }

  Widget _chip(int index) {
    final mode = _modes[index];
    final selected = index == _mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GestureDetector(
        onTap: () => setState(() => _mode = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? Ember.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(Ember.radiusControl + 6),
            border: Border.all(
              color: selected ? Ember.outline : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode.icon,
                size: 16,
                color: selected ? Ember.ember400 : Ember.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? Ember.textPrimary : Ember.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mode {
  const _Mode(this.label, this.icon, this.view);
  final String label;
  final IconData icon;
  final Widget view;
}
