import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../Helpers/index.dart';
import '../../models/lyrics_model.dart';

class LyricsEditor extends StatefulWidget {
  final AppController controller;
  const LyricsEditor({super.key, required this.controller});

  @override
  State<LyricsEditor> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends State<LyricsEditor> {
  late final TextEditingController _textController;
  bool _synced = false;
  bool _saving = false;
  final List<Duration> _timestamps = [];

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final existing = controller.currentLyrics;
    if (existing != null) {
      _synced = existing.isSynced;
      _textController = TextEditingController(text: existing.raw);
    } else {
      _textController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _stampCurrentLine() {
    final position = controller.handler.currentTrackPlayer.position;
    final ts = _formatTimestamp(position);
    final text = _textController.text;
    final sel = _textController.selection;

    // Find the start of the current line
    int lineStart = sel.baseOffset;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    // Insert timestamp at line start
    final newText =
        text.substring(0, lineStart) + ts + text.substring(lineStart);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + ts.length),
    );
    _timestamps.add(position);

    // Move cursor to next line
    final nextNewline = newText.indexOf('\n', lineStart + ts.length);
    if (nextNewline >= 0 && nextNewline + 1 < newText.length) {
      _textController.selection = TextSelection.collapsed(
        offset: nextNewline + 1,
      );
    }
  }

  String _formatTimestamp(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$min:$sec.$ms]';
  }

  Future<void> _save({required bool toLrc, required bool toId3}) async {
    if (_saving) return;
    setState(() => _saving = true);

    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    final song = controller.songs[controller.songId];
    final lyricsData = parseLrc(text);
    bool success = true;

    if (toLrc) {
      success &= await controller.lyricsService.saveLyricsToLrc(
        song,
        lyricsData,
      );
    }
    if (toId3) {
      final isLocal = !song.data.startsWith('http');
      if (isLocal) {
        success &= await controller.lyricsService.saveLyricsToId3(song, text);
      }
    }

    await controller.reloadCurrentLyrics();

    setState(() => _saving = false);

    if (mounted) {
      showMessage(
        context: context,
        type: success ? 'success' : 'danger',
        msg: success ? 'Lyrics saved' : 'Failed to save lyrics',
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Title bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit Lyrics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          // Synced toggle + stamp button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Synced toggle
                ChoiceChip(
                  label: const Text('Plain'),
                  selected: !_synced,
                  onSelected: (_) => setState(() => _synced = false),
                  selectedColor: Colors.white24,
                  labelStyle: TextStyle(
                    color: !_synced ? Colors.white : Colors.white54,
                    fontSize: 13,
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Synced'),
                  selected: _synced,
                  onSelected: (_) => setState(() => _synced = true),
                  selectedColor: Colors.white24,
                  labelStyle: TextStyle(
                    color: _synced ? Colors.white : Colors.white54,
                    fontSize: 13,
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const Spacer(),
                if (_synced)
                  FilledButton.icon(
                    onPressed: _stampCurrentLine,
                    icon: const Icon(Icons.timer_rounded, size: 18),
                    label: const Text('Stamp', style: TextStyle(fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Text editor
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.6,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText:
                      'Paste or type lyrics here...\n\nFor synced lyrics, use the Stamp button\nto add timestamps while the song plays.',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white38),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
          ),
          // Save buttons
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              bottomInset > 0 ? 12 : bottomPad + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _save(toLrc: true, toId3: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Save .lrc'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _save(toLrc: false, toId3: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Embed'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(toLrc: true, toId3: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Both'),
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
