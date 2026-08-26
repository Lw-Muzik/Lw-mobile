import '/controllers/app_controller.dart';
import 'package:eq_app/models/speaker_profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeakerEqView extends StatefulWidget {
  const SpeakerEqView({super.key});

  @override
  State<SpeakerEqView> createState() => _SpeakerEqViewState();
}

class _SpeakerEqViewState extends State<SpeakerEqView> {
  String _searchQuery = '';
  String _selectedCategory = 'all';

  static const _categories = [
    ('all', 'All'),
    ('over-ear', 'Over-ear'),
    ('in-ear', 'In-ear'),
    ('earbud', 'Earbud'),
  ];

  List<SpeakerProfile> _filteredProfiles(AppController controller) {
    var profiles = controller.speakerProfiles;
    if (_selectedCategory != 'all') {
      profiles = profiles
          .where((p) => p.category == _selectedCategory)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final lower = _searchQuery.toLowerCase();
      profiles = profiles
          .where((p) => p.name.toLowerCase().contains(lower))
          .toList();
    }
    return profiles;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final profiles = _filteredProfiles(controller);
    final activeProfile = controller.activeSpeakerProfile;

    return Column(
      children: [
        // Active profile info bar
        if (controller.speakerEqEnabled && activeProfile != null)
          _buildActiveBar(controller, theme),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search headphones...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        // Category chips
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (key, label) = _categories[i];
              final selected = _selectedCategory == key;
              return FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = key),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Profile list
        Expanded(
          child: profiles.isEmpty
              ? Center(
                  child: Text(
                    'No profiles found',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: profiles.length,
                  itemBuilder: (context, i) =>
                      _buildProfileTile(profiles[i], controller, theme),
                ),
        ),
      ],
    );
  }

  Widget _buildActiveBar(AppController controller, ThemeData theme) {
    final profile = controller.speakerProfiles
        .where((p) => p.name == controller.activeSpeakerProfile)
        .firstOrNull;
    if (profile == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${profile.name} (${profile.filters.length} bands, ${profile.preamp.toStringAsFixed(1)} dB preamp)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => controller.clearSpeakerProfile(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(
    SpeakerProfile profile,
    AppController controller,
    ThemeData theme,
  ) {
    final isActive = controller.activeSpeakerProfile == profile.name;
    return Card(
      elevation: 0,
      color: isActive
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
          : theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isActive
            ? BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
              )
            : BorderSide.none,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(
          _categoryIcon(profile.category),
          size: 22,
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        title: Text(
          profile.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? theme.colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${profile.source} - ${profile.filters.length} bands',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        trailing: isActive
            ? Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 20,
              )
            : null,
        onTap: () {
          if (isActive) {
            controller.clearSpeakerProfile();
          } else {
            controller.applySpeakerProfile(profile.name);
          }
        },
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'over-ear':
        return Icons.headphones;
      case 'in-ear':
        return Icons.earbuds;
      case 'earbud':
        return Icons.earbuds_outlined;
      default:
        return Icons.headphones;
    }
  }
}
