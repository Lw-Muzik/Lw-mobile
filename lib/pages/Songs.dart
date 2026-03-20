import 'dart:io';
import '/exports/exports.dart';

import '/Helpers/Files.dart';
import '/widgets/song_tile.dart';
import '/widgets/song_options_sheet.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/services/local_music_scanner.dart';
import '../player/player_ui.dart';

class AllSongs extends StatefulWidget {
  const AllSongs({super.key});

  @override
  State<AllSongs> createState() => _AllSongsState();
}

class _AllSongsState extends State<AllSongs> {
  final ScrollController scrollController = ScrollController();
  late Future<List<SongModel>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = Files.fetchAllSongs();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void _refreshSongs() {
    setState(() {
      _songsFuture = Files.fetchAllSongs();
    });
  }

  bool _importing = false;

  Future<void> _importFiles() async {
    if (_importing) return;
    _importing = true;
    try {
      final count = await LocalMusicScanner.importFiles();
      if (!mounted) return;
      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $count file${count == 1 ? '' : 's'}')),
        );
        _refreshSongs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: _songsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  "Failed to load songs. Please try again.",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (Platform.isIOS) ...[
                  const SizedBox(height: 16),
                  _ImportButton(onTap: _importFiles),
                ],
              ],
            ),
          );
        } else if (snap.hasData && snap.data!.isNotEmpty) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${snap.data!.length} songs",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const Spacer(),
                    if (Platform.isIOS) ...[
                      GestureDetector(
                        onTap: _refreshSongs,
                        child: Icon(Icons.refresh_rounded, size: 20,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _importFiles,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text("Import",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Consumer<AppController>(
                  builder: (context, controller, _) {
                    return SongListView(
                      songs: snap.data!,
                      controller: controller,
                      onTap: (song, index) {
                        controller.playSongFromList(snap.data!, index);
                        Routes.routeTo(const Player(), context);
                      },
                      onLongPress: (song, index) {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => SongOptionsSheet(song: song),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        } else {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_off,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  Platform.isIOS
                      ? "No songs found"
                      : "No songs available.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (Platform.isIOS) ...[
                  const SizedBox(height: 20),
                  _ImportButton(onTap: _importFiles),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      "How to add music on iOS:\n\n"
                      "1. Tap 'Import' above to pick files\n"
                      "2. In Safari: download a song → tap it\n"
                      "   → Share → 'Open in Hype Muzik'\n"
                      "3. In Files app: browse to On My iPhone\n"
                      "   → Hype Muzik → drop files there\n\n"
                      "Songs from Apple Music library\n"
                      "appear automatically.",
                      textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  ),
                ],
              ],
            ),
          );
        }
      },
    );
  }
}

class _ImportButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.folder_open_rounded, size: 20),
      label: const Text("Import Music Files"),
    );
  }
}
