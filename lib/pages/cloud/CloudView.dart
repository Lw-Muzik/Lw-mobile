import '/exports/exports.dart';
import '/Routes/routes.dart';
import '../../controllers/AppController.dart';
import '../../models/cloud_file.dart';
import 'CloudFolderSongs.dart';

class CloudView extends StatefulWidget {
  const CloudView({super.key});

  @override
  State<CloudView> createState() => _CloudViewState();
}

class _CloudViewState extends State<CloudView>
    with AutomaticKeepAliveClientMixin {
  bool _loading = false;
  String? _error;
  Map<String, List<CloudFile>> _gdriveFolders = {};
  Map<String, List<CloudFile>> _dropboxFolders = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadIfConnected();
  }

  void _loadIfConnected() {
    final controller = Provider.of<AppController>(context, listen: false);
    if (controller.isGoogleConnected || controller.isDropboxConnected) {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final controller = Provider.of<AppController>(context, listen: false);
    try {
      if (controller.isGoogleConnected) {
        final files = await controller.googleDriveService.listAudioFiles();
        _gdriveFolders = _groupByFolder(files);
      } else {
        _gdriveFolders = {};
      }

      if (controller.isDropboxConnected) {
        final files = await controller.dropboxService.listAudioFiles();
        _dropboxFolders = _groupByFolder(files);
      } else {
        _dropboxFolders = {};
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  Map<String, List<CloudFile>> _groupByFolder(List<CloudFile> files) {
    final map = <String, List<CloudFile>>{};
    for (final f in files) {
      (map[f.folderPath] ??= []).add(f);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final hasConnection =
            controller.isGoogleConnected || controller.isDropboxConnected;

        return RefreshIndicator(
          onRefresh: _loadFiles,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildProviderCards(controller),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator.adaptive(),
                )),
              if (_error != null)
                _buildErrorWidget(),
              if (!_loading && hasConnection && _gdriveFolders.isNotEmpty)
                _buildFolderSection(
                  'Google Drive',
                  Icons.cloud_rounded,
                  _gdriveFolders,
                  CloudProvider.googleDrive,
                  controller,
                ),
              if (!_loading && hasConnection && _dropboxFolders.isNotEmpty)
                _buildFolderSection(
                  'Dropbox',
                  Icons.cloud_circle_rounded,
                  _dropboxFolders,
                  CloudProvider.dropbox,
                  controller,
                ),
              if (!_loading &&
                  !hasConnection)
                _buildEmptyState(),
              if (!_loading &&
                  hasConnection &&
                  _gdriveFolders.isEmpty &&
                  _dropboxFolders.isEmpty &&
                  _error == null)
                _buildNoFilesState(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProviderCards(AppController controller) {
    return Row(
      children: [
        Expanded(
          child: _ProviderCard(
            icon: Icons.cloud_rounded,
            name: 'Google Drive',
            connected: controller.isGoogleConnected,
            onConnect: () async {
              final ok = await controller.connectGoogle();
              if (ok && mounted) _loadFiles();
            },
            onDisconnect: () async {
              await controller.disconnectGoogle();
              setState(() => _gdriveFolders = {});
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProviderCard(
            icon: Icons.cloud_circle_rounded,
            name: 'Dropbox',
            connected: controller.isDropboxConnected,
            onConnect: () async {
              final ok = await controller.connectDropbox();
              if (ok && mounted) _loadFiles();
            },
            onDisconnect: () async {
              await controller.disconnectDropbox();
              setState(() => _dropboxFolders = {});
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderSection(
    String title,
    IconData icon,
    Map<String, List<CloudFile>> folders,
    CloudProvider provider,
    AppController controller,
  ) {
    final sortedKeys = folders.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < sortedKeys.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(folders[sortedKeys[i]]!.first.folderName),
                  subtitle:
                      Text('${folders[sortedKeys[i]]!.length} songs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Routes.routeTo(
                    CloudFolderSongs(
                      folderName: folders[sortedKeys[i]]!.first.folderName,
                      files: folders[sortedKeys[i]]!,
                      provider: provider,
                    ),
                    context,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text('Failed to load files',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextButton(onPressed: _loadFiles, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Connect a cloud provider',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Stream music from Google Drive or Dropbox',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilesState() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off_rounded,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No audio files found',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Upload music files to your cloud storage to stream them here',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ProviderCard({
    required this.icon,
    required this.name,
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon,
                size: 32,
                color: connected
                    ? accent
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              connected ? 'Connected' : 'Not connected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: connected
                        ? Colors.green
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: connected ? onDisconnect : onConnect,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(connected ? 'Disconnect' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
