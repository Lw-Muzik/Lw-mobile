import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Visualizers/wave-visualizer.dart';
import '/controllers/AppController.dart';
import '/Helpers/AudioVisualizer.dart';
import '/Helpers/VisualizerWidget.dart';
import '/player/widgets/MusicInfo.dart';
import '/Routes/routes.dart';
import '/widgets/Body.dart';

class VisualUI extends StatefulWidget {
  const VisualUI({super.key});

  @override
  State<VisualUI> createState() => _VisualUIState();
}

class _VisualUIState extends State<VisualUI>
    with SingleTickerProviderStateMixin {
  static const double musicInfoHeight = 150.0;
  late AnimationController _controller;
  String _selectedVisual = 'circular';
  bool _isSelectorVisible = false;
  bool _isControlsVisible = false;
  double _sensitivity = 1.0;
  double _speed = 1.0;
  Color _visualColor = Colors.white;

  final Map<String, Map<String, dynamic>> _visualizers = {
    'circular': {
      'name': 'Circular Bars',
      'icon': Icons.circle_outlined,
      'description': 'Circular bars effect',
      'hasSpeed': true,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'bars': {
      'name': 'Spectrum',
      'icon': Icons.bar_chart,
      'description': 'Classic spectrum analyzer',
      'hasSpeed': false,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'cube': {
      'name': 'Cube',
      'icon': Icons.square,
      'description': 'Cube analyzer',
      'hasSpeed': false,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'sea': {
      'name': 'Ocean',
      'icon': Icons.water,
      'description': 'Dynamic ocean waves',
      'hasSpeed': true,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'ripple': {
      'name': 'Ripple',
      'icon': Icons.circle,
      'description': 'Reactive ripple effect',
      'hasSpeed': true,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'sphere': {
      'name': 'Sphere',
      'icon': Icons.radio_button_unchecked,
      'description': 'Reactive 3D sphere visualization',
      'hasSpeed': true,
      'hasSensitivity': true,
      'hasColor': true,
    },
    'flower': {
      'name': 'Plasma',
      'icon': Icons.blur_circular,
      'description': 'Flowing plasma effect',
      'hasSpeed': true,
      'hasSensitivity': false,
      'hasColor': true,
    },
    'fabric': {
      'name': 'Fabric',
      'icon': Icons.waves,
      'description': 'Flowing fabric simulation',
      'hasSpeed': true,
      'hasSensitivity': true,
      'hasColor': false,
    },
  };

  @override
  void initState() {
    super.initState();
    _initializeVisualizer();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initializeVisualizer() {
    Visualizers.setFrameRate(60);
    Visualizers.scaleVisualizer(true);
    Visualizers.getEnabled().asStream().listen((v) {});
  }

  Widget _buildVisualizer(BuildContext context, double width, double height) {
    return VisualizerWidget(
      builder: (context, fft, x) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: animation,
                child: child,
              ),
            );
          },
          child: WaveVisualizer(
            color: _visualColor,
            key: ValueKey(_selectedVisual),
            width: width,
            height: height,
            audioData: fft,
            selector: _selectedVisual,
          ),
        );
      },
      id: 0,
    );
  }

  Widget _buildVisualizerControls() {
    final currentVisualizer = _visualizers[_selectedVisual]!;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: 20,
      right: 20,
      bottom: _isControlsVisible ? (musicInfoHeight + 100) : -200,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentVisualizer['name'],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              currentVisualizer['description'],
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            if (currentVisualizer['hasSensitivity'])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sensitivity',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  Slider(
                    value: _sensitivity,
                    onChanged: (value) => setState(() => _sensitivity = value),
                    min: 0.1,
                    max: 2.0,
                    activeColor: Colors.red,
                  ),
                ],
              ),
            if (currentVisualizer['hasSpeed'])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Speed',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  Slider(
                    value: _speed,
                    onChanged: (value) => setState(() => _speed = value),
                    min: 0.1,
                    max: 2.0,
                    activeColor: Colors.red,
                  ),
                ],
              ),
            if (currentVisualizer['hasColor'])
              Row(
                children: [
                  Text(
                    'Color',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      Colors.white,
                      Colors.blue,
                      Colors.purple,
                      Colors.green,
                      Colors.orange,
                      Colors.pink,
                    ]
                        .map((color) => GestureDetector(
                              onTap: () => setState(() => _visualColor = color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _visualColor == color
                                        ? Theme.of(context).primaryColor
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizerSelector() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: _isSelectorVisible ? musicInfoHeight + 20 : -100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _visualizers.entries.map((entry) {
                final isSelected = entry.key == _selectedVisual;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVisual = entry.key;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          entry.value['icon'],
                          color: isSelected ? Colors.white : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.value['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: musicInfoHeight + 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "toggle_controls",
            mini: true,
            onPressed: () =>
                setState(() => _isControlsVisible = !_isControlsVisible),
            child: Icon(_isControlsVisible ? Icons.tune : Icons.tune),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "toggle_selector",
            onPressed: () =>
                setState(() => _isSelectorVisible = !_isSelectorVisible),
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _controller,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Body(
      child: Consumer<AppController>(
        builder: (context, controller, child) {
          if (controller.visuals) {
            Visualizers.enableVisual(true);
          }

          final size = MediaQuery.of(context).size;

          return Scaffold(
            backgroundColor: controller.isFancy
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
            body: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isSelectorVisible || _isControlsVisible) {
                      setState(() {
                        _isSelectorVisible = false;
                        _isControlsVisible = false;
                      });
                    } else {
                      Routes.pop(context);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: mounted
                      ? _buildVisualizer(context, size.width, size.height)
                      : const SizedBox(),
                ),
                _buildVisualizerSelector(),
                _buildVisualizerControls(),
                _buildControls(),
              ],
            ),
            floatingActionButton: SizedBox(
              height: musicInfoHeight,
              width: double.infinity,
              child: MusicInfo(controller: controller),
            ),
          );
        },
      ),
    );
  }
}
