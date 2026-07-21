import '../Helpers/index.dart';
import '../Routes/routes.dart';
import '/exports/exports.dart';

import '../Global/index.dart';
import '../controllers/LibraryController.dart';
import '../data/library_repository.dart';
import '../widgets/library_list_row.dart';
import '../widgets/pinch_zoom_grid.dart';
import 'folder_songs.dart';

class Folders extends StatefulWidget {
  const Folders({super.key});

  @override
  State<Folders> createState() => _FoldersState();
}

class _FoldersState extends State<Folders> {
  late final Stream<List<FolderEntry>> _foldersStream =
      context.read<LibraryRepository>().watchFolders();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FolderEntry>>(
      stream: _foldersStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
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
        final library = context.read<LibraryController>();
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: PinchZoomGrid(
            initialExtent: library.gridExtentFor('folders', fallback: 200.0),
            minExtent: 100.0,
            maxExtent: 300.0,
            onExtentChanged: (e) => library.setGridExtent('folders', e),
            gridBuilder: (extent) => GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: extent,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                final path = folder.path;
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
                      child: folderArtwork(
                        context,
                        folder.name,
                        sampleId: folder.sampleId,
                        sampleData: folder.sampleData,
                        numSongs: folder.numSongs,
                      ),
                    ),
                  ),
                );
              },
            ),
            listBuilder: ListView.builder(
              itemExtent: kLibraryRowExtent,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                final path = folder.path;
                return LibraryListRow(
                  title: folder.name,
                  subtitle: '${folder.numSongs} Songs',
                  artworkId: folder.sampleId,
                  artworkType: ArtworkType.AUDIO,
                  artworkPath: folder.sampleData ?? '',
                  fallbackIcon: Icons.folder_rounded,
                  onTap: () => Routes.scaleTo(FolderSongs(path: path), context),
                  onLongPress: () {
                    showDeleteWindow("folder", path, context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
