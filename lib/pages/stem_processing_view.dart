import 'package:flutter/material.dart';
import '../controllers/stem_controller.dart';

class StemProcessingView extends StatelessWidget {
  final StemController controller;
  final String songTitle;
  final String songArtist;

  const StemProcessingView({
    super.key,
    required this.controller,
    required this.songTitle,
    required this.songArtist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final progress = controller.separationProgress;
          final message = controller.separationMessage;
          final isSeparating = controller.isSeparating;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                isSeparating ? 'Separating Stems...' : 'Stem Separation',
                style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              // Circular progress
              SizedBox(
                width: 120, height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120, height: 120,
                      child: CircularProgressIndicator(
                        value: isSeparating ? progress : null,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF9C27B0)),
                      ),
                    ),
                    Text(
                      isSeparating ? '${(progress * 100).round()}%' : '',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Song info
              Text(
                songTitle,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                songArtist,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Status message
              Text(
                message,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              // Cancel button
              if (isSeparating)
                TextButton(
                  onPressed: () {
                    controller.cancelSeparation();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
              if (!isSeparating && progress >= 1.0)
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9C27B0),
                  ),
                  child: const Text('Open Mixer'),
                ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          );
        },
      ),
    );
  }
}
