import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Visualizers/wave-visualizer.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
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
    'sphere': _VisualPreset(
      name: 'Sphere',
      icon: Icons.radio_button_unchecked,
      description: '3D reactive sphere',
    ),
    'flower': _VisualPreset(
      name: 'Plasma',
      icon: Icons.blur_circular,
      description: 'Flowing plasma',
    ),
    'fabric': _VisualPreset(
      name: 'Fabric',
      icon: Icons.texture,
      description: 'Flowing fabric',
    ),
    'sea': _VisualPreset(
      name: 'Ocean',
      icon: Icons.water,
      description: 'Ocean waves',
    ),
    'cube': _VisualPreset(
      name: 'Cube',
      icon: Icons.view_in_ar,
      description: '3D cube',
    ),
    'ripple': _VisualPreset(
      name: 'Ripple',
      icon: Icons.waves,
      description: 'Ripple rings',
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                  behavior: HitTestBehavior.opaque,
                  child: mounted
                      ? _buildVisualizer(size.width, size.height)
                      : const SizedBox(),
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
                    onSelectVisual: (key) =>
                        controller.visualizerStyle = key,
                    onSelectColor: (color) =>
                        controller.visualizerColor = color.toARGB32(),
                    onClose: () => Routes.pop(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
                  icon: isPanelOpen
                      ? Icons.close_rounded
                      : Icons.tune_rounded,
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

/// Settings panel with visualizer selector + color picker.
class _SettingsPanel extends StatelessWidget {
  final String selectedVisual;
  final Color visualColor;
  final Map<String, _VisualPreset> visualizers;
  final ValueChanged<String> onSelectVisual;
  final ValueChanged<Color> onSelectColor;

  static const _accentColor = Color(0xFFD4A825);

  const _SettingsPanel({
    required this.selectedVisual,
    required this.visualColor,
    required this.visualizers,
    required this.onSelectVisual,
    required this.onSelectColor,
  });

  @override
  Widget build(BuildContext context) {
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
                          horizontal: 14, vertical: 10),
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
                              color:
                                  isSelected ? _accentColor : Colors.white70,
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
          // Section: Color palette
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
                        color: isSelected
                            ? Colors.white
                            : Colors.transparent,
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
