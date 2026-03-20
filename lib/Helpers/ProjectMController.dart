import 'package:flutter/foundation.dart';
import '/Helpers/Channel.dart';

/// Dart controller wrapping the native projectM renderer via MethodChannel.
/// Manages the Flutter Texture ID and projectM lifecycle.
class ProjectMController {
  int? _textureId;
  bool _running = false;
  String _currentPreset = '';
  List<String> _presetNames = [];

  int? get textureId => _textureId;
  bool get isRunning => _running;
  String get currentPreset => _currentPreset;
  List<String> get presetNames => _presetNames;

  /// Initialize the projectM renderer and get a Flutter Texture ID.
  /// Returns null if initialization failed (e.g. no OpenGL ES support).
  Future<int?> init(int width, int height) async {
    final id = await Channel.channel.invokeMethod<int>(
      'projectm_init',
      {'width': width, 'height': height},
    );
    // Native returns -1 on failure
    if (id == null || id < 0) {
      debugPrint('ProjectM init failed: textureId=$id');
      _textureId = null;
      return null;
    }
    _textureId = id;
    debugPrint('ProjectM init: textureId=$id');
    return id;
  }

  /// Start the GL render loop.
  Future<void> start() async {
    await Channel.channel.invokeMethod('projectm_start');
    _running = true;
  }

  /// Stop the render loop (but keep texture alive).
  Future<void> stop() async {
    await Channel.channel.invokeMethod('projectm_stop');
    _running = false;
  }

  /// Release all resources including the Flutter texture.
  Future<void> release() async {
    await Channel.channel.invokeMethod('projectm_release');
    _running = false;
    _textureId = null;
  }

  /// Load a specific preset by file path.
  Future<void> setPreset(String path) async {
    await Channel.channel.invokeMethod('projectm_set_preset', {'path': path});
  }

  /// Cycle to the next preset. Returns the new preset name.
  Future<String> nextPreset() async {
    final name = await Channel.channel.invokeMethod<String>('projectm_next_preset');
    _currentPreset = name ?? '';
    return _currentPreset;
  }

  /// Cycle to the previous preset. Returns the new preset name.
  Future<String> previousPreset() async {
    final name = await Channel.channel.invokeMethod<String>('projectm_prev_preset');
    _currentPreset = name ?? '';
    return _currentPreset;
  }

  /// Load a preset by its index in the preset list.
  Future<String> loadPresetByIndex(int index) async {
    final name = await Channel.channel.invokeMethod<String>(
      'projectm_load_preset_index',
      {'index': index},
    );
    _currentPreset = name ?? '';
    return _currentPreset;
  }

  /// Get list of available preset names.
  Future<List<String>> listPresets() async {
    final result = await Channel.channel.invokeMethod<List>('projectm_list_presets');
    _presetNames = result?.cast<String>() ?? [];
    return _presetNames;
  }

  /// Get the current preset name.
  Future<String> getCurrentPreset() async {
    final name = await Channel.channel.invokeMethod<String>('projectm_current_preset');
    _currentPreset = name ?? '';
    return _currentPreset;
  }

  /// Set the render FPS (15-60).
  Future<void> setFps(int fps) async {
    await Channel.channel.invokeMethod('projectm_set_fps', {'fps': fps});
  }

  /// Set beat sensitivity (higher = more reactive).
  Future<void> setBeatSensitivity(double sensitivity) async {
    await Channel.channel.invokeMethod(
      'projectm_set_beat_sensitivity',
      {'sensitivity': sensitivity},
    );
  }

  /// Set auto-cycle duration in seconds (0 = disable auto-cycle).
  Future<void> setPresetDuration(double seconds) async {
    await Channel.channel.invokeMethod(
      'projectm_set_preset_duration',
      {'duration': seconds},
    );
  }

  /// Lock/unlock the current preset (prevents auto-switching).
  Future<void> setPresetLocked(bool locked) async {
    await Channel.channel.invokeMethod(
      'projectm_set_preset_locked',
      {'locked': locked},
    );
  }

  /// Update the render size (e.g. when widget resizes).
  Future<void> setSize(int width, int height) async {
    await Channel.channel.invokeMethod(
      'projectm_set_size',
      {'width': width, 'height': height},
    );
  }

  /// Set the mesh grid resolution (affects geometry complexity).
  Future<void> setMeshSize(int width, int height) async {
    await Channel.channel.invokeMethod(
      'projectm_set_mesh_size',
      {'width': width, 'height': height},
    );
  }
}
