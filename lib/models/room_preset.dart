import 'dart:convert';

class RoomPreset {
  final String name;
  final double roomSize;    // 0.0 - 1.0 (scales delay lengths)
  final double decay;       // 0.0 - 1.0 (maps to RT60: 0.1s - 15s)
  final double damping;     // 0.0 - 1.0 (0=bright, 1=dark)
  final double preDelay;    // 0 - 200 ms
  final double diffusion;   // 0.0 - 1.0 (echo density)
  final double wetDry;      // 0.0 - 1.0 (0=dry, 1=fully wet)

  const RoomPreset({
    required this.name,
    required this.roomSize,
    required this.decay,
    required this.damping,
    required this.preDelay,
    required this.diffusion,
    required this.wetDry,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'roomSize': roomSize,
    'decay': decay,
    'damping': damping,
    'preDelay': preDelay,
    'diffusion': diffusion,
    'wetDry': wetDry,
  };

  factory RoomPreset.fromJson(Map<String, dynamic> j) => RoomPreset(
    name: j['name'] as String,
    roomSize: (j['roomSize'] as num).toDouble(),
    decay: (j['decay'] as num).toDouble(),
    damping: (j['damping'] as num).toDouble(),
    preDelay: (j['preDelay'] as num).toDouble(),
    diffusion: (j['diffusion'] as num).toDouble(),
    wetDry: (j['wetDry'] as num).toDouble(),
  );

  static String encodeList(List<RoomPreset> presets) =>
      json.encode(presets.map((p) => p.toJson()).toList());

  static List<RoomPreset> decodeList(String jsonStr) =>
      (json.decode(jsonStr) as List)
          .map((e) => RoomPreset.fromJson(e as Map<String, dynamic>))
          .toList();

  /// Built-in presets tuned for the Freeverb engine.
  /// - roomSize: 0-1, scales comb delay lengths (0=tiny, 1=large)
  /// - decay: 0-1, maps to feedback (0.70-0.98 via Freeverb scaling)
  /// - damping: 0-1, HF absorption (0=bright, 1=dark)
  /// - preDelay: 0-200 ms
  /// - diffusion: 0-1, allpass feedback (0.3-0.7)
  /// - wetDry: 0-1, wet/dry mix
  static const List<RoomPreset> builtIn = [
    RoomPreset(name: 'Off',         roomSize: 0.0,  decay: 0.0,  damping: 0.0,  preDelay: 0,   diffusion: 0.0,  wetDry: 0.0),
    RoomPreset(name: 'Small Room',  roomSize: 0.2,  decay: 0.25, damping: 0.6,  preDelay: 3,   diffusion: 0.5,  wetDry: 0.25),
    RoomPreset(name: 'Medium Room', roomSize: 0.4,  decay: 0.4,  damping: 0.45, preDelay: 8,   diffusion: 0.55, wetDry: 0.3),
    RoomPreset(name: 'Large Room',  roomSize: 0.6,  decay: 0.55, damping: 0.35, preDelay: 15,  diffusion: 0.6,  wetDry: 0.35),
    RoomPreset(name: 'Hall',        roomSize: 0.75, decay: 0.65, damping: 0.3,  preDelay: 25,  diffusion: 0.65, wetDry: 0.4),
    RoomPreset(name: 'Cathedral',   roomSize: 0.9,  decay: 0.8,  damping: 0.5,  preDelay: 40,  diffusion: 0.7,  wetDry: 0.4),
    RoomPreset(name: 'Plate',       roomSize: 0.35, decay: 0.5,  damping: 0.1,  preDelay: 2,   diffusion: 0.8,  wetDry: 0.35),
    RoomPreset(name: 'Studio',      roomSize: 0.15, decay: 0.2,  damping: 0.65, preDelay: 2,   diffusion: 0.4,  wetDry: 0.2),
    RoomPreset(name: 'Chamber',     roomSize: 0.45, decay: 0.45, damping: 0.35, preDelay: 12,  diffusion: 0.55, wetDry: 0.3),
    RoomPreset(name: 'Arena',       roomSize: 1.0,  decay: 0.9,  damping: 0.55, preDelay: 60,  diffusion: 0.65, wetDry: 0.35),
    RoomPreset(name: 'Concert',     roomSize: 0.8,  decay: 0.7,  damping: 0.35, preDelay: 35,  diffusion: 0.65, wetDry: 0.4),
  ];
}
