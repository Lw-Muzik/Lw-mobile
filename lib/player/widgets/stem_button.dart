import 'package:flutter/material.dart';
import '../../controllers/AppController.dart';
import '../../controllers/stem_controller.dart';
import '../../models/stem_model.dart';
import '../../pages/stem_mixer_view.dart';
import '../../pages/stem_processing_view.dart';
import '../../Routes/routes.dart';

class StemButton extends StatelessWidget {
  final AppController controller;

  const StemButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.stemController,
      builder: (context, _) {
        final stem = controller.stemController;
        final hasStems = stem.hasStemsForCurrentSong;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleTap(context, stem),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        Icons.multitrack_audio_rounded,
                        color: stem.stemModeActive
                            ? const Color(0xFF9C27B0)
                            : Colors.white70,
                        size: 22,
                      ),
                      if (hasStems && !stem.stemModeActive)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF9C27B0),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stems',
                    style: TextStyle(
                      color: stem.stemModeActive
                          ? const Color(0xFF9C27B0)
                          : Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(BuildContext context, StemController stem) {
    if (stem.hasStemsForCurrentSong) {
      // Stems exist — load and navigate to mixer
      _openMixer(context, stem);
    } else if (stem.isSeparating) {
      // Currently separating — show progress
      _showProgress(context, stem);
    } else {
      // Not separated — prompt to separate
      _showSeparatePrompt(context, stem);
    }
  }

  Future<void> _openMixer(BuildContext context, StemController stem) async {
    if (controller.songs.isEmpty) return;
    final song = controller.songs[controller.songId];
    if (stem.currentStemSong != song.data) {
      await stem.loadStems(song.data);
    }
    if (!stem.stemModeActive) {
      await stem.activateStemMode();
    }
    if (context.mounted) {
      Routes.routeTo(const StemMixerView(), context, animate: true);
    }
  }

  void _showProgress(BuildContext context, StemController stem) {
    if (controller.songs.isEmpty) return;
    final song = controller.songs[controller.songId];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StemProcessingView(
        controller: stem,
        songTitle: song.title,
        songArtist: song.artist ?? 'Unknown',
      ),
    );
  }

  void _showSeparatePrompt(BuildContext context, StemController stem) {
    if (controller.songs.isEmpty) return;
    final song = controller.songs[controller.songId];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(Icons.multitrack_audio_rounded,
              color: Color(0xFF9C27B0), size: 48),
            const SizedBox(height: 12),
            const Text('Separate Stems',
              style: TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Split "${song.title}" into vocals, drums, bass, and instruments.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'This may take 3-10 minutes.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  stem.separateCurrentSong(song.data);
                  _showProgress(context, stem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C27B0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start Separation',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
