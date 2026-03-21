import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import 'hot100_section.dart';
import 'popular_section.dart';
import 'artists_section.dart';
import 'music_search_page.dart';

class DiscoverView extends StatefulWidget {
  const DiscoverView({super.key});

  @override
  State<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<DiscoverView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Search bar
        _buildSearchBar(context, theme),

        const SizedBox(height: 4),

        // Hot 100 chart
        const Hot100Section(),

        _buildSectionDivider(theme),

        // Popular / trending songs
        const PopularSection(),

        _buildSectionDivider(theme),

        // Artists directory
        const ArtistsSection(),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => Routes.routeTo(const MusicSearchPage(), context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              Text('Search songs...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        height: 1,
      ),
    );
  }
}
