import 'package:flutter/material.dart';
import '/Helpers/ProjectMController.dart';

class PresetBrowser extends StatefulWidget {
  const PresetBrowser({super.key});

  @override
  State<PresetBrowser> createState() => _PresetBrowserState();
}

class _PresetBrowserState extends State<PresetBrowser> {
  final ProjectMController _projectM = ProjectMController();
  List<String> _presets = [];
  List<String> _filtered = [];
  String _currentPreset = '';
  String _searchQuery = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final presets = await _projectM.listPresets();
    final current = await _projectM.getCurrentPreset();
    if (mounted) {
      setState(() {
        _presets = presets;
        _filtered = presets;
        _currentPreset = current;
        _loading = false;
      });
    }
  }

  void _filterPresets(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filtered = _presets;
      } else {
        final lower = query.toLowerCase();
        _filtered = _presets
            .where((p) => p.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MilkDrop Presets'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: _filterPresets,
              decoration: InputDecoration(
                hintText: 'Search presets...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'No presets available'
                        : 'No matches for "$_searchQuery"',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _filtered.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final name = _filtered[index];
                    final isActive = name == _currentPreset;

                    return ListTile(
                      leading: Icon(
                        isActive
                            ? Icons.play_circle_filled
                            : Icons.blur_on_rounded,
                        color: isActive ? accent : null,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive ? accent : null,
                        ),
                      ),
                      trailing: isActive
                          ? Icon(Icons.check_circle, color: accent, size: 20)
                          : null,
                      onTap: () {
                        // Find index in full list and load
                        final fullIndex = _presets.indexOf(name);
                        if (fullIndex >= 0) {
                          setState(() => _currentPreset = name);
                          // Use the preset's cached path from native side
                          _projectM.nextPreset(); // This is a workaround — ideally we'd load by index
                        }
                        Navigator.pop(context, name);
                      },
                    );
                  },
                ),
    );
  }
}
