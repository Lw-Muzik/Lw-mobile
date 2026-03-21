import 'package:flutter/material.dart';

import '../../Routes/routes.dart';
import '../../onboarding/coach_marks.dart';
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
  final _coachController = CoachMarkController('discover');
  final _searchBarKey = GlobalKey();
  final _hot100Key = GlobalKey();
  final _popularKey = GlobalKey();
  final _artistsKey = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2000), _maybeShowCoachMarks);
  }

  Future<void> _maybeShowCoachMarks() async {
    if (!mounted) return;
    final shown = await _coachController.hasBeenShown();
    if (shown || !mounted) return;

    _coachController.start(context, [
      CoachStep(
        targetKey: _searchBarKey,
        title: 'Search',
        description:
            'Search for any song, artist, or album across the music catalog.',
        icon: Icons.search_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
      CoachStep(
        targetKey: _hot100Key,
        title: 'Hot 100',
        description:
            'The Hot 100 chart shows trending Ugandan music. Tap any song to play.',
        icon: Icons.local_fire_department_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
      CoachStep(
        targetKey: _popularKey,
        title: 'Popular',
        description:
            'Popular songs updated regularly. Tap \'View More\' to see the full list.',
        icon: Icons.trending_up_rounded,
        tooltipPosition: TooltipPosition.above,
      ),
      CoachStep(
        targetKey: _artistsKey,
        title: 'Artists',
        description:
            'Browse artists. Tap an artist to see their profile and songs.',
        icon: Icons.people_rounded,
        tooltipPosition: TooltipPosition.above,
      ),
    ]);
  }

  @override
  void dispose() {
    _coachController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Search bar
        KeyedSubtree(key: _searchBarKey, child: _buildSearchBar(context, theme)),

        const SizedBox(height: 4),

        // Hot 100 chart
        KeyedSubtree(key: _hot100Key, child: const Hot100Section()),

        _buildSectionDivider(theme),

        // Popular / trending songs
        KeyedSubtree(key: _popularKey, child: const PopularSection()),

        _buildSectionDivider(theme),

        // Artists directory
        KeyedSubtree(key: _artistsKey, child: const ArtistsSection()),

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
