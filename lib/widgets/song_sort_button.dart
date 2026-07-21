import 'package:flutter/material.dart';

import '/data/library_repository.dart';

/// Sort control for the Songs list — the ordering affordance every mainstream
/// music player exposes and this app previously lacked entirely. Picking a
/// field keeps the current direction; the footer row toggles asc/desc.
class SongSortButton extends StatelessWidget {
  const SongSortButton({
    super.key,
    required this.sort,
    required this.dir,
    required this.onChanged,
  });

  final SongSort sort;
  final SortDir dir;
  final void Function(SongSort sort, SortDir dir) onChanged;

  static const Map<SongSort, String> _labels = {
    SongSort.title: 'Title',
    SongSort.artist: 'Artist',
    SongSort.album: 'Album',
    SongSort.dateAdded: 'Date added',
    SongSort.duration: 'Duration',
    SongSort.playCount: 'Most played',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<_SortAction>(
      tooltip: 'Sort',
      position: PopupMenuPosition.under,
      onSelected: (action) {
        if (action.toggleDir) {
          onChanged(
            sort,
            dir == SortDir.asc ? SortDir.desc : SortDir.asc,
          );
        } else {
          onChanged(action.sort!, dir);
        }
      },
      itemBuilder: (context) => [
        for (final entry in _labels.entries)
          CheckedPopupMenuItem<_SortAction>(
            value: _SortAction.field(entry.key),
            checked: entry.key == sort,
            child: Text(entry.value),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_SortAction>(
          value: _SortAction.dir(),
          child: Row(
            children: [
              Icon(
                dir == SortDir.asc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(dir == SortDir.asc ? 'Ascending' : 'Descending'),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort_rounded, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            _labels[sort] ?? 'Sort',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            dir == SortDir.asc
                ? Icons.arrow_drop_up_rounded
                : Icons.arrow_drop_down_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SortAction {
  const _SortAction._(this.sort, this.toggleDir);
  factory _SortAction.field(SongSort s) => _SortAction._(s, false);
  factory _SortAction.dir() => const _SortAction._(null, true);

  final SongSort? sort;
  final bool toggleDir;
}
