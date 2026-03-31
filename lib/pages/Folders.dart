import '../Helpers/index.dart';
import '../Routes/routes.dart';
import '/exports/exports.dart';

import '../Global/index.dart';
import '../widgets/pinch_zoom_grid.dart';
import 'folder_songs.dart';

class Folders extends StatefulWidget {
  const Folders({super.key});

  @override
  State<Folders> createState() => _FoldersState();
}

class _FoldersState extends State<Folders> {
  late Future<List<String>> _foldersFuture;

  @override
  void initState() {
    super.initState();
    _foldersFuture = OnAudioQuery.platform.queryAllPath();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _foldersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        } else if (snapshot.hasError) {
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
                  "Failed to load folders",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  "No folders found",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        final folders = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: PinchZoomGrid(
            initialExtent: 200.0,
            minExtent: 100.0,
            maxExtent: 300.0,
            gridBuilder: (extent) => GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final path = folders[index];
                final folderName = path.split("/").last;
                return InkWell(
                  onTap: () => Routes.scaleTo(FolderSongs(path: path), context),
                  onLongPress: () {
                    showDeleteWindow("folder", path, context);
                  },
                  child: Hero(
                    tag: 'folder_$path',
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: folderArtwork(path, folderName),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
