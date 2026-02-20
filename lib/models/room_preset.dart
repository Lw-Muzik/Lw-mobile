import 'dart:convert';

class RoomPreset {
  final String name;
  final int decayTime;        // 100-20000 ms
  final int roomLevel;        // -9000..0 mB
  final int roomHFLevel;      // -9000..0 mB
  final int decayHFRatio;     // 100-2000
  final int reflectionsLevel; // -9000..1000 mB
  final int reflectionsDelay; // 0-300 ms
  final int reverbLevel;      // -9000..2000 mB
  final int reverbDelay;      // 0-100 ms
  final int density;          // 0-1000
  final int diffusion;        // 0-1000

  const RoomPreset({
    required this.name,
    required this.decayTime,
    required this.roomLevel,
    required this.roomHFLevel,
    required this.decayHFRatio,
    required this.reflectionsLevel,
    required this.reflectionsDelay,
    required this.reverbLevel,
    required this.reverbDelay,
    required this.density,
    required this.diffusion,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'decayTime': decayTime,
    'roomLevel': roomLevel,
    'roomHFLevel': roomHFLevel,
    'decayHFRatio': decayHFRatio,
    'reflectionsLevel': reflectionsLevel,
    'reflectionsDelay': reflectionsDelay,
    'reverbLevel': reverbLevel,
    'reverbDelay': reverbDelay,
    'density': density,
    'diffusion': diffusion,
  };

  factory RoomPreset.fromJson(Map<String, dynamic> j) => RoomPreset(
    name: j['name'] as String,
    decayTime: j['decayTime'] as int,
    roomLevel: j['roomLevel'] as int,
    roomHFLevel: j['roomHFLevel'] as int,
    decayHFRatio: j['decayHFRatio'] as int,
    reflectionsLevel: j['reflectionsLevel'] as int,
    reflectionsDelay: j['reflectionsDelay'] as int,
    reverbLevel: j['reverbLevel'] as int,
    reverbDelay: j['reverbDelay'] as int,
    density: j['density'] as int,
    diffusion: j['diffusion'] as int,
  );

  static String encodeList(List<RoomPreset> presets) =>
      json.encode(presets.map((p) => p.toJson()).toList());

  static List<RoomPreset> decodeList(String jsonStr) =>
      (json.decode(jsonStr) as List)
          .map((e) => RoomPreset.fromJson(e as Map<String, dynamic>))
          .toList();

  /// Built-in presets with professionally tuned parameters.
  static const List<RoomPreset> builtIn = [
    RoomPreset(
      name: 'Off',
      decayTime: 100,
      roomLevel: -9000,
      roomHFLevel: 0,
      decayHFRatio: 1000,
      reflectionsLevel: -9000,
      reflectionsDelay: 0,
      reverbLevel: -9000,
      reverbDelay: 0,
      density: 0,
      diffusion: 0,
    ),
    RoomPreset(
      name: 'Small Room',
      decayTime: 800,
      roomLevel: -1200,
      roomHFLevel: -600,
      decayHFRatio: 830,
      reflectionsLevel: -200,
      reflectionsDelay: 5,
      reverbLevel: -400,
      reverbDelay: 10,
      density: 800,
      diffusion: 900,
    ),
    RoomPreset(
      name: 'Medium Room',
      decayTime: 1500,
      roomLevel: -1000,
      roomHFLevel: -450,
      decayHFRatio: 750,
      reflectionsLevel: -350,
      reflectionsDelay: 10,
      reverbLevel: -200,
      reverbDelay: 20,
      density: 850,
      diffusion: 850,
    ),
    RoomPreset(
      name: 'Large Room',
      decayTime: 2800,
      roomLevel: -800,
      roomHFLevel: -400,
      decayHFRatio: 650,
      reflectionsLevel: -500,
      reflectionsDelay: 20,
      reverbLevel: -100,
      reverbDelay: 30,
      density: 900,
      diffusion: 800,
    ),
    RoomPreset(
      name: 'Hall',
      decayTime: 4500,
      roomLevel: -600,
      roomHFLevel: -500,
      decayHFRatio: 600,
      reflectionsLevel: -600,
      reflectionsDelay: 30,
      reverbLevel: 0,
      reverbDelay: 40,
      density: 950,
      diffusion: 900,
    ),
    RoomPreset(
      name: 'Cathedral',
      decayTime: 8000,
      roomLevel: -400,
      roomHFLevel: -700,
      decayHFRatio: 450,
      reflectionsLevel: -800,
      reflectionsDelay: 50,
      reverbLevel: 200,
      reverbDelay: 60,
      density: 1000,
      diffusion: 1000,
    ),
    RoomPreset(
      name: 'Plate',
      decayTime: 1200,
      roomLevel: -500,
      roomHFLevel: -100,
      decayHFRatio: 1500,
      reflectionsLevel: -100,
      reflectionsDelay: 2,
      reverbLevel: 0,
      reverbDelay: 5,
      density: 1000,
      diffusion: 1000,
    ),
    RoomPreset(
      name: 'Studio',
      decayTime: 600,
      roomLevel: -1500,
      roomHFLevel: -300,
      decayHFRatio: 900,
      reflectionsLevel: -300,
      reflectionsDelay: 3,
      reverbLevel: -600,
      reverbDelay: 8,
      density: 700,
      diffusion: 950,
    ),
    RoomPreset(
      name: 'Chamber',
      decayTime: 2200,
      roomLevel: -900,
      roomHFLevel: -350,
      decayHFRatio: 700,
      reflectionsLevel: -400,
      reflectionsDelay: 15,
      reverbLevel: -150,
      reverbDelay: 25,
      density: 880,
      diffusion: 870,
    ),
    RoomPreset(
      name: 'Arena',
      decayTime: 12000,
      roomLevel: -300,
      roomHFLevel: -800,
      decayHFRatio: 400,
      reflectionsLevel: -900,
      reflectionsDelay: 80,
      reverbLevel: 400,
      reverbDelay: 80,
      density: 1000,
      diffusion: 950,
    ),
    RoomPreset(
      name: 'Concert',
      decayTime: 6000,
      roomLevel: -500,
      roomHFLevel: -600,
      decayHFRatio: 550,
      reflectionsLevel: -700,
      reflectionsDelay: 40,
      reverbLevel: 100,
      reverbDelay: 50,
      density: 970,
      diffusion: 950,
    ),
  ];
}
