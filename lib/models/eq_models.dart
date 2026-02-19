import 'dart:convert';

class ParametricPoint {
  double frequency; // 20-20000 Hz
  double gain; // -12 to +12 dB
  bool enabled;

  ParametricPoint({
    required this.frequency,
    this.gain = 0.0,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'gain': gain,
        'enabled': enabled,
      };

  factory ParametricPoint.fromJson(Map<String, dynamic> json) {
    return ParametricPoint(
      frequency: (json['frequency'] as num).toDouble(),
      gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  ParametricPoint copyWith({double? frequency, double? gain, bool? enabled}) {
    return ParametricPoint(
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      enabled: enabled ?? this.enabled,
    );
  }
}

class EqPreset {
  String name;
  List<double> graphicGains; // 32 values
  List<ParametricPoint> parametric; // variable length
  String? deviceType; // null = global, or "speaker"/"bluetooth" etc

  EqPreset({
    required this.name,
    required this.graphicGains,
    List<ParametricPoint>? parametric,
    this.deviceType,
  }) : parametric = parametric ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'graphicGains': graphicGains,
        'parametric': parametric.map((p) => p.toJson()).toList(),
        'deviceType': deviceType,
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) {
    return EqPreset(
      name: json['name'] as String,
      graphicGains:
          (json['graphicGains'] as List).map((e) => (e as num).toDouble()).toList(),
      parametric: json['parametric'] != null
          ? (json['parametric'] as List)
              .map((e) => ParametricPoint.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      deviceType: json['deviceType'] as String?,
    );
  }

  static String encodeList(Map<String, EqPreset> presets) {
    final map = presets.map((k, v) => MapEntry(k, v.toJson()));
    return json.encode(map);
  }

  static Map<String, EqPreset> decodeList(String encoded) {
    final map = json.decode(encoded) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, EqPreset.fromJson(v as Map<String, dynamic>)));
  }
}

/// Built-in graphic EQ presets (32-band gain curves)
class BuiltInPresets {
  static const int bandCount = 32;

  static final Map<String, List<double>> presets = {
    'Flat': List.filled(bandCount, 0.0),
    'Bass Boost': [
      8.0, 7.5, 7.0, 6.5, 6.0, 5.0, 4.0, 3.0,
      2.0, 1.5, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    'Treble Boost': [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0,
      6.0, 6.5, 7.0, 7.5, 8.0, 8.0, 7.5, 7.0,
    ],
    'V-Shape': [
      7.0, 6.5, 6.0, 5.5, 5.0, 4.0, 3.0, 2.0,
      1.0, 0.5, 0.0, -0.5, -1.0, -1.5, -2.0, -2.0,
      -2.0, -1.5, -1.0, -0.5, 0.0, 1.0, 2.0, 3.0,
      4.0, 5.0, 6.0, 6.5, 7.0, 7.0, 6.5, 6.0,
    ],
    'Vocal': [
      -2.0, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0,
      1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 4.5,
      4.5, 4.0, 3.5, 3.0, 2.5, 2.0, 1.0, 0.0,
      -0.5, -1.0, -1.5, -2.0, -2.0, -2.0, -2.0, -2.0,
    ],
    'Electronic': [
      6.0, 5.5, 5.0, 4.5, 4.0, 3.0, 2.0, 1.0,
      0.0, -0.5, -1.0, -1.0, 0.0, 0.5, 1.0, 1.5,
      2.0, 2.0, 1.5, 1.0, 0.5, 1.0, 2.0, 3.0,
      4.0, 5.0, 5.5, 6.0, 6.0, 5.5, 5.0, 4.5,
    ],
    'Rock': [
      5.0, 4.5, 4.0, 3.5, 3.0, 2.0, 1.0, 0.0,
      -0.5, -1.0, -1.5, -1.5, -1.0, -0.5, 0.0, 0.5,
      1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5,
      5.0, 5.5, 5.5, 5.0, 4.5, 4.0, 3.5, 3.0,
    ],
    'Jazz': [
      3.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.0, -0.5,
      -1.0, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0,
      2.5, 3.0, 3.5, 4.0, 4.0, 3.5, 3.0, 2.5,
      2.0, 1.5, 1.0, 0.5, 0.0, -0.5, -1.0, -1.0,
    ],
    'Classical': [
      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0,
      -1.5, -2.0, -2.0, -1.5, -1.0, 0.0, 0.5, 1.0,
      1.5, 2.0, 2.5, 3.0, 3.5, 3.5, 3.0, 2.5,
      2.0, 1.5, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0,
    ],
    'Hip Hop': [
      7.0, 6.5, 6.0, 5.5, 5.0, 4.0, 3.0, 2.0,
      1.0, 0.0, -0.5, -1.0, -1.0, -0.5, 0.0, 0.5,
      1.0, 1.0, 0.5, 0.0, -0.5, -0.5, 0.0, 0.5,
      1.0, 1.5, 2.0, 2.5, 3.0, 3.0, 2.5, 2.0,
    ],
    'Acoustic': [
      3.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.0, 0.0,
      0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 3.5,
      3.5, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.0,
      -0.5, -1.0, -1.0, -0.5, 0.0, 0.0, 0.0, 0.0,
    ],
  };

  static List<String> get names => presets.keys.toList();
}
