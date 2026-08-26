/// The app's four places, and the bar that is always under them.
///
/// # Why this replaced eight scrolling tabs
///
/// Home used to be eight tabs in a scrolling strip — Folders, Playlists,
/// Artists, Albums, Genres, Songs, Discover, Cloud — with no landing surface at
/// all. Playlists were the second of eight, which is a strange place for the
/// thing a person made themselves, and there was nowhere for anything the app
/// generated to live.
///
/// Four destinations, browse modes gathered inside Library, and the mini player
/// docked above the bar. That last part is not decoration: `bottomNavigationBar`
/// used to be where the mini player lived, so introducing a nav bar without
/// moving it would have meant choosing between them.
///
/// # The chrome is opaque, deliberately
///
/// A translucent bar over a scrolling list is the worst case for
/// `BackdropFilter` — content genuinely changing behind it, every frame, for as
/// long as the scroll lasts. That was this app's heat problem once already. See
/// the note in `themes/ember.dart`.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../controllers/drawer_controller.dart';
import '../../onboarding/coach_marks.dart';
import '../../onboarding/home_guide.dart';
import '../../routes/routes.dart';
import '../../themes/ember.dart';
import '../../widgets/body.dart';
import '../cloud/cloud_view.dart';
import '../discover/discover_view.dart';
import '../equalizer.dart';
import '../search_page.dart';
import 'home_surface.dart';
import 'library_surface.dart';
import 'widgets/ember_mini_player.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Walkthrough targets. The old tour pointed at a scrolling tab strip that no
  // longer exists; these three are what the shell actually has.
  final _searchKey = GlobalKey();
  final _navKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _coachController = CoachMarkController('home');

  Future<void> _tryShowCoachMarks() async {
    if (context.read<AppController>().isEqMode) return;
    if (await _coachController.hasBeenShown() || !mounted) return;
    // Let layout settle before measuring anything.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    _coachController.start(context, [
      CoachStep(
        targetKey: _navKey,
        title: 'Four places',
        description:
            'Home is made for you. Library is everything you own. Discover and '
            'Cloud are everything else.',
        icon: Icons.home_rounded,
        tooltipPosition: TooltipPosition.above,
      ),
      CoachStep(
        targetKey: _searchKey,
        title: 'Search everything',
        description:
            'One box across your library, your drive and YouTube. Tap a result '
            'to play it and build a station from it.',
        icon: Icons.search_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
      CoachStep(
        targetKey: _menuKey,
        title: 'Settings & EQ',
        description:
            'Open the menu for Settings, Equalizer, Visualizer, and more.',
        icon: Icons.tune_rounded,
        tooltipPosition: TooltipPosition.below,
      ),
    ]);
  }

  static const _destinations = [
    _Destination(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _Destination(Icons.library_music_rounded, Icons.library_music_outlined,
        'Library'),
    _Destination(Icons.explore_rounded, Icons.explore_outlined, 'Discover'),
    _Destination(Icons.cloud_rounded, Icons.cloud_outlined, 'Cloud'),
  ];

  /// Built once and kept alive by [IndexedStack], so switching destinations
  /// does not re-run a library query or throw away a scroll position.
  late final List<Widget> _surfaces = const [
    HomeSurface(),
    LibrarySurface(),
    DiscoverView(),
    CloudView(),
  ];

  @override
  Widget build(BuildContext context) {
    return HomeGuide(
      onComplete: _tryShowCoachMarks,
      child: Body(
      child: Consumer<AppController>(
        builder: (context, controller, _) {
          if (controller.isEqMode) return const Equalizer();

          return Scaffold(
            backgroundColor:
                controller.isFancy ? Colors.transparent : Ember.ground,
            appBar: _buildAppBar(context, controller),
            body: IndexedStack(index: _index, children: _surfaces),
            bottomNavigationBar: _buildBottom(controller),
          );
        },
      ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, AppController controller) {
    return AppBar(
      backgroundColor: controller.isFancy ? Colors.transparent : Ember.ground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: Ember.gutter,
      leading: IconButton(
        key: _menuKey,
        icon: const Icon(Icons.menu_rounded),
        color: Ember.textPrimary,
        onPressed: () => context.read<DrawerProvider>().toggleDrawer(),
      ),
      title: Text(
        _destinations[_index].label == 'Home'
            ? 'Hype Muzik'
            : _destinations[_index].label,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Ember.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          key: _searchKey,
          icon: const Icon(Icons.search_rounded, size: 22),
          color: Ember.textPrimary,
          onPressed: () => Routes.scaleTo(const SearchPage(), context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Mini player and nav bar, stacked, as one opaque block.
  ///
  /// `mainAxisSize.min` so the block is exactly as tall as it needs to be —
  /// with no track playing the mini player contributes nothing and the nav bar
  /// sits on its own.
  Widget _buildBottom(AppController controller) {
    return Container(
      decoration: const BoxDecoration(
        color: Ember.surface,
        border: Border(top: BorderSide(color: Ember.outline, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.hasNowPlaying)
              EmberMiniPlayer(controller: controller),
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Padding(
      key: _navKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < _destinations.length; i++)
            Expanded(child: _navItem(i)),
        ],
      ),
    );
  }

  Widget _navItem(int index) {
    final destination = _destinations[index];
    final selected = index == _index;
    return InkWell(
      onTap: () => setState(() => _index = index),
      borderRadius: BorderRadius.circular(Ember.radiusControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                // A tinted plate, not solid gold: the icon on it is gold too,
                // and gold-on-gold is invisible. White on gold is 1.63:1, so
                // inverting the icon instead would not have saved it either.
                color: selected ? Ember.accentWash : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 22,
                color: selected ? Ember.accent : Ember.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Ember.accent : Ember.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.selectedIcon, this.icon, this.label);
  final IconData selectedIcon;
  final IconData icon;
  final String label;
}
