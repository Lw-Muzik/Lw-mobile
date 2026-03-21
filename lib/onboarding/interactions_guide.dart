import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full-screen interactions guide showing gesture patterns and shortcuts.
/// Can be launched from Settings or shown once automatically after onboarding.
class InteractionsGuide extends StatefulWidget {
  const InteractionsGuide({super.key});

  /// Check if the guide has been shown before.
  static Future<bool> hasBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('interactions_guide_shown') ?? false;
  }

  /// Mark as shown so it doesn't auto-trigger again.
  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interactions_guide_shown', true);
  }

  @override
  State<InteractionsGuide> createState() => _InteractionsGuideState();
}

class _InteractionsGuideState extends State<InteractionsGuide> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _sections = [
    _InteractionSection(
      title: 'Player Gestures',
      icon: Icons.touch_app_rounded,
      color: Color(0xFFD4A825),
      interactions: [
        _Interaction(
          gesture: 'Swipe Card Right',
          action: 'Skip to next track',
          icon: Icons.swipe_right_rounded,
        ),
        _Interaction(
          gesture: 'Swipe Card Left',
          action: 'Go to previous track',
          icon: Icons.swipe_left_rounded,
        ),
        _Interaction(
          gesture: 'Long Press Artwork',
          action: 'View track info & details',
          icon: Icons.info_outline_rounded,
        ),
        _Interaction(
          gesture: 'Tap Mini Player',
          action: 'Expand to full player',
          icon: Icons.open_in_full_rounded,
        ),
        _Interaction(
          gesture: 'Drag Waveform Bar',
          action: 'Seek through the track',
          icon: Icons.linear_scale_rounded,
        ),
      ],
    ),
    _InteractionSection(
      title: 'Song Lists',
      icon: Icons.queue_music_rounded,
      color: Color(0xFF5EC4D4),
      interactions: [
        _Interaction(
          gesture: 'Tap Song',
          action: 'Play the song immediately',
          icon: Icons.play_arrow_rounded,
        ),
        _Interaction(
          gesture: 'Long Press Song',
          action: 'View song details & options',
          icon: Icons.more_horiz_rounded,
        ),
        _Interaction(
          gesture: 'Swipe in Queue',
          action: 'Remove song from queue',
          icon: Icons.delete_sweep_rounded,
        ),
        _Interaction(
          gesture: 'Tap "View More"',
          action: 'See full list with pagination',
          icon: Icons.expand_more_rounded,
        ),
      ],
    ),
    _InteractionSection(
      title: 'Equalizer & DSP',
      icon: Icons.equalizer_rounded,
      color: Color(0xFF9C6ADE),
      interactions: [
        _Interaction(
          gesture: 'Drag EQ Sliders',
          action: 'Adjust frequency band gains',
          icon: Icons.tune_rounded,
        ),
        _Interaction(
          gesture: 'Tap EQ Preset',
          action: 'Load preset EQ curve',
          icon: Icons.auto_fix_high_rounded,
        ),
        _Interaction(
          gesture: 'Rotate Tone Knobs',
          action: 'Adjust bass & treble tone',
          icon: Icons.radio_button_checked_rounded,
        ),
        _Interaction(
          gesture: 'Toggle Switches',
          action: 'Enable/disable EQ, MBC, limiter',
          icon: Icons.toggle_on_rounded,
        ),
      ],
    ),
    _InteractionSection(
      title: 'Discover & Browse',
      icon: Icons.explore_rounded,
      color: Color(0xFFFF6B35),
      interactions: [
        _Interaction(
          gesture: 'Scroll Horizontally',
          action: 'Browse featured songs & artists',
          icon: Icons.view_carousel_rounded,
        ),
        _Interaction(
          gesture: 'Tap Artist Avatar',
          action: 'View artist profile & songs',
          icon: Icons.person_rounded,
        ),
        _Interaction(
          gesture: 'Tap Search Bar',
          action: 'Search songs across the library',
          icon: Icons.search_rounded,
        ),
        _Interaction(
          gesture: 'Pull to Refresh',
          action: 'Reload charts & trending data',
          icon: Icons.refresh_rounded,
        ),
      ],
    ),
    _InteractionSection(
      title: 'Navigation & More',
      icon: Icons.navigation_rounded,
      color: Color(0xFF4CAF50),
      interactions: [
        _Interaction(
          gesture: 'Swipe Tabs',
          action: 'Switch between library sections',
          icon: Icons.tab_rounded,
        ),
        _Interaction(
          gesture: 'Tap Visualizer Icon',
          action: 'Launch fullscreen visual mode',
          icon: Icons.auto_awesome_rounded,
        ),
        _Interaction(
          gesture: 'Tap Lyrics Icon',
          action: 'Show synchronized lyrics view',
          icon: Icons.lyrics_rounded,
        ),
        _Interaction(
          gesture: 'Tap Fingerprint Icon',
          action: 'Identify current playing track',
          icon: Icons.fingerprint_rounded,
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _sections.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      InteractionsGuide.markShown();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Pages
          PageView.builder(
            controller: _pageController,
            itemCount: _sections.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return _SectionPage(section: _sections[index]);
            },
          ),

          // Top: close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: TextButton(
              onPressed: () {
                InteractionsGuide.markShown();
                Navigator.of(context).pop();
              },
              child: Text(
                'Close',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Bottom: indicators + next button
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 24,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_sections.length, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? _sections[_currentPage].color
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: _sections[_currentPage].color,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      child: Text(
                        _currentPage == _sections.length - 1
                            ? 'Got It'
                            : 'Next',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section page
// =============================================================================

class _SectionPage extends StatelessWidget {
  final _InteractionSection section;
  const _SectionPage({required this.section});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(28, topPadding + 60, 28, 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: section.color.withValues(alpha: 0.15),
            ),
            child: Icon(section.icon, size: 28, color: section.color),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 28),

          // Interactions list
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: section.interactions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final interaction = section.interactions[index];
                return _InteractionTile(
                  interaction: interaction,
                  color: section.color,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractionTile extends StatelessWidget {
  final _Interaction interaction;
  final Color color;
  const _InteractionTile({required this.interaction, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(interaction.icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  interaction.gesture,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  interaction.action,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Data models
// =============================================================================

class _InteractionSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Interaction> interactions;

  const _InteractionSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.interactions,
  });
}

class _Interaction {
  final String gesture;
  final String action;
  final IconData icon;

  const _Interaction({
    required this.gesture,
    required this.action,
    required this.icon,
  });
}
