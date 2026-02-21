import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Visualizers/wave-visualizer.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
import '/Helpers/ProjectMController.dart';
import '/Helpers/VisualizerWidget.dart';
import '/Routes/routes.dart';
import '/widgets/Body.dart';

class VisualUI extends StatefulWidget {
  const VisualUI({super.key});

  @override
  State<VisualUI> createState() => _VisualUIState();
}

class _VisualUIState extends State<VisualUI>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPanelOpen = false;

  // projectM state
  final ProjectMController _projectM = ProjectMController();
  bool _projectMInitialized = false;
  String _presetName = '';

  static const _visualizers = {
    'circular': _VisualPreset(
      name: 'Circular',
      icon: Icons.circle_outlined,
      description: 'Circular bars',
    ),
    'bars': _VisualPreset(
      name: 'Spectrum',
      icon: Icons.bar_chart_rounded,
      description: 'Classic analyzer',
    ),
    'milkdrop': _VisualPreset(
      name: 'MilkDrop',
      icon: Icons.blur_on_rounded,
      description: 'MilkDrop presets',
    ),
  };

  static const _colorPalette = [
    (0xFFFFFFFF, Colors.white),
    (0xFFD4A825, Color(0xFFD4A825)),
    (0xFF2196F3, Colors.blue),
    (0xFF9C27B0, Colors.purple),
    (0xFF4CAF50, Colors.green),
    (0xFFE91E63, Colors.pink),
    (0xFFFF5722, Color(0xFFFF5722)),
    (0xFF00BCD4, Color(0xFF00BCD4)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    final ctrl = context.read<AppController>();
    Visualizers.setFrameRate(ctrl.visualizerFrameRate);
    Visualizers.scaleVisualizer(true);

    // If starting with milkdrop style, initialize immediately
    if (ctrl.visualizerStyle == 'milkdrop') {
      _initProjectM();
    }
  }

  @override
  void dispose() {
    _stopProjectM();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initProjectM() async {
    if (_projectMInitialized) return;

    final size = MediaQuery.of(context).size;
    final w = size.width.toInt();
    final h = size.height.toInt();

    final textureId = await _projectM.init(w, h);
    if (textureId != null) {
      final ctrl = context.read<AppController>();
      await _projectM.setFps(ctrl.milkdropFps);
      await _projectM.setBeatSensitivity(ctrl.milkdropBeatSensitivity);
      await _projectM.setPresetDuration(ctrl.milkdropPresetDuration);
      await _projectM.setPresetLocked(ctrl.milkdropPresetLocked);
      await _projectM.start();
      final name = await _projectM.getCurrentPreset();
      if (mounted) {
        setState(() {
          _projectMInitialized = true;
          _presetName = name;
        });
      }
    }
  }

  Future<void> _stopProjectM() async {
    if (!_projectMInitialized) return;
    await _projectM.release();
    _projectMInitialized = false;
  }

  void _onStyleChanged(String style) {
    final ctrl = context.read<AppController>();
    final wasMillkdrop = ctrl.visualizerStyle == 'milkdrop';
    ctrl.visualizerStyle = style;

    if (style == 'milkdrop' && !wasMillkdrop) {
      _initProjectM();
    } else if (style != 'milkdrop' && wasMillkdrop) {
      _stopProjectM();
    }
  }

  void _togglePanel() {
    setState(() => _isPanelOpen = !_isPanelOpen);
    if (_isPanelOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Body(
      child: Consumer<AppController>(
        builder: (context, controller, child) {
          if (controller.visuals) Visualizers.enableVisual(true);
          final size = MediaQuery.of(context).size;
          final isMilkDrop = controller.visualizerStyle == 'milkdrop';

          return Scaffold(
            backgroundColor: controller.isFancy
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Visualizer canvas — tap to dismiss
                GestureDetector(
                  onTap: () {
                    if (_isPanelOpen) {
                      _togglePanel();
                    } else {
                      Routes.pop(context);
                    }
                  },
                  // Swipe left/right for preset switching in milkdrop mode
                  onHorizontalDragEnd: isMilkDrop
                      ? (details) async {
                          if (details.primaryVelocity == null) return;
                          String name;
                          if (details.primaryVelocity! < -200) {
                            name = await _projectM.nextPreset();
                          } else if (details.primaryVelocity! > 200) {
                            name = await _projectM.previousPreset();
                          } else {
                            return;
                          }
                          setState(() => _presetName = name);
                        }
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: mounted
                      ? isMilkDrop
                          ? _buildMilkDropVisualizer()
                          : _buildVisualizer(size.width, size.height)
                      : const SizedBox(),
                ),

                // Preset name overlay for MilkDrop
                if (isMilkDrop && _presetName.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Text(
                        _presetName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Bottom controls overlay
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomOverlay(
                    controller: controller,
                    isPanelOpen: _isPanelOpen,
                    selectedVisual: controller.visualizerStyle,
                    visualColor: Color(controller.visualizerColor),
                    visualizers: _visualizers,
                    bottomPadding: bottomPadding,
                    onTogglePanel: _togglePanel,
                    onSelectVisual: _onStyleChanged,
                    onSelectColor: (color) =>
                        controller.visualizerColor = color.toARGB32(),
                    onClose: () => Routes.pop(context),
                    projectM: _projectM,
                    currentPreset: _presetName,
                    onPresetSelected: (name) {
                      setState(() => _presetName = name);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMilkDropVisualizer() {
    if (!_projectMInitialized || _projectM.textureId == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFD4A825),
          strokeWidth: 2,
        ),
      );
    }
    return Texture(textureId: _projectM.textureId!);
  }

  Widget _buildVisualizer(double width, double height) {
    final ctrl = context.read<AppController>();
    final style = ctrl.visualizerStyle;
    final color = Color(ctrl.visualizerColor);
    final reactivity = ctrl.visualizerReactivity;

    return VisualizerWidget(
      builder: (context, fft, x) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: WaveVisualizer(
            key: ValueKey(style),
            color: color,
            width: width,
            height: height,
            audioData: fft,
            selector: style,
            reactivity: reactivity,
          ),
        );
      },
      id: 0,
    );
  }
}

class _VisualPreset {
  final String name;
  final IconData icon;
  final String description;
  const _VisualPreset({
    required this.name,
    required this.icon,
    required this.description,
  });
}

/// Bottom overlay: track info bar + expandable settings panel.
class _BottomOverlay extends StatelessWidget {
  final AppController controller;
  final bool isPanelOpen;
  final String selectedVisual;
  final Color visualColor;
  final Map<String, _VisualPreset> visualizers;
  final double bottomPadding;
  final VoidCallback onTogglePanel;
  final ValueChanged<String> onSelectVisual;
  final ValueChanged<Color> onSelectColor;
  final VoidCallback onClose;
  final ProjectMController projectM;
  final String currentPreset;
  final ValueChanged<String> onPresetSelected;

  const _BottomOverlay({
    required this.controller,
    required this.isPanelOpen,
    required this.selectedVisual,
    required this.visualColor,
    required this.visualizers,
    required this.bottomPadding,
    required this.onTogglePanel,
    required this.onSelectVisual,
    required this.onSelectColor,
    required this.onClose,
    required this.projectM,
    required this.currentPreset,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final song = controller.songs[controller.songId];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanded settings panel
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _SettingsPanel(
              selectedVisual: selectedVisual,
              visualColor: visualColor,
              visualizers: visualizers,
              onSelectVisual: onSelectVisual,
              onSelectColor: onSelectColor,
              projectM: projectM,
              currentPreset: currentPreset,
              onPresetSelected: onPresetSelected,
            ),
            crossFadeState: isPanelOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),

          // Track info + controls bar
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
            child: Row(
              children: [
                // Close
                _CircleButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: onClose,
                ),
                const SizedBox(width: 12),
                // Track info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        song.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Settings toggle
                _CircleButton(
                  icon: isPanelOpen ? Icons.close_rounded : Icons.tune_rounded,
                  onTap: onTogglePanel,
                  accent: isPanelOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings panel with visualizer selector + color picker + preset picker.
class _SettingsPanel extends StatelessWidget {
  final String selectedVisual;
  final Color visualColor;
  final Map<String, _VisualPreset> visualizers;
  final ValueChanged<String> onSelectVisual;
  final ValueChanged<Color> onSelectColor;
  final ProjectMController projectM;
  final String currentPreset;
  final ValueChanged<String> onPresetSelected;

  static const _accentColor = Color(0xFFD4A825);

  const _SettingsPanel({
    required this.selectedVisual,
    required this.visualColor,
    required this.visualizers,
    required this.onSelectVisual,
    required this.onSelectColor,
    required this.projectM,
    required this.currentPreset,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isMilkDrop = selectedVisual == 'milkdrop';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section: Visualizer type
          const Text(
            'STYLE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: visualizers.entries.map((entry) {
                final isSelected = entry.key == selectedVisual;

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => onSelectVisual(entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _accentColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? _accentColor.withValues(alpha: 0.5)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            entry.value.icon,
                            color: isSelected ? _accentColor : Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.value.name,
                            style: TextStyle(
                              color: isSelected ? _accentColor : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          // Section: Color palette (hidden for milkdrop — projectM handles its own colors)
          if (!isMilkDrop) ...[
            const Text(
              'COLOR',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: _VisualUIState._colorPalette.map((pair) {
                final color = pair.$2;
                final isSelected = visualColor.toARGB32() == color.toARGB32();

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => onSelectColor(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          // Section: Preset selector for MilkDrop
          if (isMilkDrop) ...[
            const Text(
              'PRESET',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _openPresetPicker(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.blur_on_rounded,
                      color: currentPreset.isNotEmpty
                          ? _accentColor
                          : Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        currentPreset.isNotEmpty
                            ? currentPreset
                            : 'Select a preset...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: currentPreset.isNotEmpty
                              ? Colors.white
                              : Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.search_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Prev / Next row
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final name = await projectM.previousPreset();
                      onPresetSelected(name);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.skip_previous_rounded,
                              color: Colors.white54, size: 18),
                          SizedBox(width: 4),
                          Text('Prev',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final name = await projectM.nextPreset();
                      onPresetSelected(name);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Next',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          SizedBox(width: 4),
                          Icon(Icons.skip_next_rounded,
                              color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _openPresetPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PresetPickerSheet(
        projectM: projectM,
        currentPreset: currentPreset,
        onSelected: onPresetSelected,
      ),
    );
  }
}

/// Searchable bottom sheet for browsing and selecting MilkDrop presets.
class _PresetPickerSheet extends StatefulWidget {
  final ProjectMController projectM;
  final String currentPreset;
  final ValueChanged<String> onSelected;

  const _PresetPickerSheet({
    required this.projectM,
    required this.currentPreset,
    required this.onSelected,
  });

  @override
  State<_PresetPickerSheet> createState() => _PresetPickerSheetState();
}

class _PresetPickerSheetState extends State<_PresetPickerSheet> {
  static const _accentColor = Color(0xFFD4A825);

  List<String> _allPresets = [];
  List<String> _filtered = [];
  String _query = '';
  bool _loading = true;
  late String _activePreset;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _activePreset = widget.currentPreset;
    _loadPresets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    final presets = await widget.projectM.listPresets();
    if (mounted) {
      setState(() {
        _allPresets = presets;
        _filtered = presets;
        _loading = false;
      });
      // Scroll to current preset
      _scrollToActive();
    }
  }

  void _scrollToActive() {
    if (_activePreset.isEmpty) return;
    final idx = _filtered.indexOf(_activePreset);
    if (idx > 0 && _scrollController.hasClients) {
      // Each item is ~48px tall
      _scrollController.animateTo(
        (idx * 48.0).clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onSearch(String query) {
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _filtered = _allPresets;
      } else {
        final lower = query.toLowerCase();
        _filtered = _allPresets
            .where((p) => p.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  Future<void> _selectPreset(String name) async {
    final idx = _allPresets.indexOf(name);
    if (idx < 0) return;
    final loaded = await widget.projectM.loadPresetByIndex(idx);
    setState(() => _activePreset = loaded);
    widget.onSelected(loaded);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.65,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.blur_on_rounded,
                    color: _accentColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'MilkDrop Presets',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  Text(
                    '${_filtered.length} preset${_filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search presets...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.3), size: 20),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 18),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Preset list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: _accentColor, strokeWidth: 2))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No presets available'
                              : 'No matches',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _filtered.length,
                        padding: EdgeInsets.only(bottom: bottomInset + 16),
                        itemBuilder: (context, index) {
                          final name = _filtered[index];
                          final isActive = name == _activePreset;

                          return InkWell(
                            onTap: () async {
                              await _selectPreset(name);
                              if (mounted) Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              color: isActive
                                  ? _accentColor.withValues(alpha: 0.1)
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    isActive
                                        ? Icons.play_circle_filled_rounded
                                        : Icons.blur_on_rounded,
                                    color: isActive
                                        ? _accentColor
                                        : Colors.white.withValues(alpha: 0.25),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isActive
                                            ? _accentColor
                                            : Colors.white.withValues(
                                                alpha: 0.8),
                                        fontSize: 13,
                                        fontWeight: isActive
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isActive)
                                    const Icon(Icons.check_rounded,
                                        color: _accentColor, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Small circle button for the bottom bar.
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent
                ? const Color(0xFFD4A825).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
          ),
          child: Icon(
            icon,
            color: accent ? const Color(0xFFD4A825) : Colors.white70,
            size: 22,
          ),
        ),
      ),
    );
  }
}
