import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Helpers/Channel.dart';
import '../controllers/AppController.dart';
import '../models/recognition_result.dart';

/// Bottom sheet that identifies the currently playing track via fingerprinting.
/// Three phases: Listening → Result → Saving.
class ListenSheet extends StatefulWidget {
  const ListenSheet({super.key});

  @override
  State<ListenSheet> createState() => _ListenSheetState();
}

enum _Phase { listening, result, saving, error }

class _ListenSheetState extends State<ListenSheet>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.listening;
  RecognitionResult? _result;
  String? _artworkPath;
  String _errorMessage = '';

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _startIdentification();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startIdentification() async {
    final controller = context.read<AppController>();
    if (controller.songs.isEmpty) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'No song playing';
      });
      return;
    }

    final song = controller.songs[controller.songId];
    try {
      final result = await controller.fingerprintService.identifySong(song);
      if (!mounted) return;

      if (result == null || !result.hasUsefulData) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = 'Could not identify this track';
        });
        return;
      }

      // Pre-fetch cover art if available
      String? artPath;
      if (result.musicBrainzReleaseId != null) {
        artPath = await controller.fingerprintService
            .fetchCoverArt(result.musicBrainzReleaseId!);
      }
      if (!mounted) return;

      setState(() {
        _result = result;
        _artworkPath = artPath;
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Identification failed';
      });
    }
  }

  Future<void> _save() async {
    if (_result == null) return;
    setState(() => _phase = _Phase.saving);

    final controller = context.read<AppController>();
    final song = controller.songs[controller.songId];

    try {
      // Write tags to file
      final tagMap = _result!.toTagMap();
      if (tagMap.isNotEmpty) {
        await Channel.writeTags(song.data, tagMap, artworkPath: _artworkPath);
        await Channel.scanMediaFile(song.data);
      }

      // Clean up temp artwork
      if (_artworkPath != null) {
        try {
          File(_artworkPath!).deleteSync();
        } catch (_) {}
      }

      if (!mounted) return;

      // Update in-memory state immediately
      await controller.updateSongMetadata(song, _result!);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Track info updated'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Failed to save tags';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          switch (_phase) {
            _Phase.listening => _buildListening(),
            _Phase.result => _buildResult(),
            _Phase.saving => _buildSaving(),
            _Phase.error => _buildError(),
          },
        ],
      ),
    );
  }

  Widget _buildListening() {
    return SizedBox(
      height: 260,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _PulseRingsPainter(
                    progress: _pulseController.value,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.hearing_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Listening...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final confidence = (r.score * 100).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Track Identified',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow('Title', r.title ?? 'Unknown'),
          _infoRow('Artist', r.artist ?? 'Unknown'),
          if (r.album != null) _infoRow('Album', r.album!),
          if (r.year != null) _infoRow('Year', r.year!),
          _infoRow('Confidence', '$confidence%'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaving() {
    return const SizedBox(
      height: 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 16),
            Text(
              'Saving tags...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 40),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    setState(() => _phase = _Phase.listening);
                    _pulseController.repeat();
                    _startIdentification();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Try Again'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints 3 concentric pulsing rings radiating outward.
class _PulseRingsPainter extends CustomPainter {
  final double progress;
  static const int ringCount = 3;

  _PulseRingsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < ringCount; i++) {
      final phase = (progress + i / ringCount) % 1.0;
      final radius = maxRadius * (0.3 + 0.7 * phase);
      final opacity = (1.0 - phase).clamp(0.0, 0.5);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingsPainter old) => old.progress != progress;
}
