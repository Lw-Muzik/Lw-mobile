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

/// Maps N visible display bands to 32 native DynamicsProcessing bands.
/// Fewer visible bands = each slider controls a group of native bands.
class BandMapping {
  final int displayCount;
  final List<double> frequencies;
  final List<List<int>> nativeGroups;

  const BandMapping._({
    required this.displayCount,
    required this.frequencies,
    required this.nativeGroups,
  });

  static const supportedCounts = [5, 10, 16, 20, 32];

  /// All 32 ISO 1/3-octave center frequencies.
  static const List<double> _allFreqs = [
    20, 25, 31.5, 40, 50, 63, 80, 100,
    125, 160, 200, 250, 315, 400, 500, 630,
    800, 1000, 1250, 1600, 2000, 2500, 3150, 4000,
    5000, 6300, 8000, 10000, 12500, 16000, 18000, 20000,
  ];

  static BandMapping forCount(int count) {
    switch (count) {
      case 5:
        return _mapping5;
      case 10:
        return _mapping10;
      case 16:
        return _mapping16;
      case 20:
        return _mapping20;
      case 32:
      default:
        return _mapping32;
    }
  }

  /// Average each group's native gains into N display gains.
  List<double> nativeToDisplay(List<double> native32) {
    return List.generate(displayCount, (i) {
      final group = nativeGroups[i];
      double sum = 0;
      for (final idx in group) {
        sum += native32[idx];
      }
      return sum / group.length;
    });
  }

  /// Broadcast each display gain to all native bands in its group.
  List<double> displayToNative(List<double> displayN) {
    final native32 = List<double>.filled(32, 0.0);
    for (int i = 0; i < displayCount && i < displayN.length; i++) {
      for (final idx in nativeGroups[i]) {
        native32[idx] = displayN[i];
      }
    }
    return native32;
  }

  // -- 5 bands: Sub-bass, Bass, Mids, Upper-mids, Treble --
  static const _mapping5 = BandMapping._(
    displayCount: 5,
    frequencies: [60, 230, 910, 3600, 14000],
    nativeGroups: [
      [0, 1, 2, 3, 4, 5],       // 20-63 Hz
      [6, 7, 8, 9, 10],         // 80-200 Hz
      [11, 12, 13, 14, 15, 16, 17], // 250-1000 Hz
      [18, 19, 20, 21, 22, 23, 24], // 1250-5000 Hz
      [25, 26, 27, 28, 29, 30, 31], // 6300-20000 Hz
    ],
  );

  // -- 10 bands: classic 10-band EQ --
  static const _mapping10 = BandMapping._(
    displayCount: 10,
    frequencies: [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
    nativeGroups: [
      [0, 1],           // 20-25 Hz
      [2, 3, 4],        // 31.5-50 Hz
      [5, 6, 7],        // 63-100 Hz
      [8, 9, 10],       // 125-200 Hz
      [11, 12, 13, 14], // 250-500 Hz
      [15, 16, 17],     // 630-1000 Hz
      [18, 19, 20],     // 1250-2000 Hz
      [21, 22, 23, 24], // 2500-5000 Hz
      [25, 26, 27],     // 6300-10000 Hz
      [28, 29, 30, 31], // 12500-20000 Hz
    ],
  );

  // -- 16 bands: every pair from 32 --
  static const _mapping16 = BandMapping._(
    displayCount: 16,
    frequencies: [
      22.5, 35.75, 56.5, 90, 142.5, 225, 357.5, 565,
      715, 1125, 1800, 2825, 4500, 7150, 11250, 19000,
    ],
    nativeGroups: [
      [0, 1], [2, 3], [4, 5], [6, 7],
      [8, 9], [10, 11], [12, 13], [14, 15],
      [16, 17], [18, 19], [20, 21], [22, 23],
      [24, 25], [26, 27], [28, 29], [30, 31],
    ],
  );

  // -- 20 bands: log-spaced picks from 32, remaining assigned to nearest --
  static final _mapping20 = _build20BandMapping();

  // -- 32 bands: 1:1 identity --
  static final _mapping32 = BandMapping._(
    displayCount: 32,
    frequencies: List<double>.from(_allFreqs),
    nativeGroups: List.generate(32, (i) => [i]),
  );

  static BandMapping _build20BandMapping() {
    // Pick 20 log-spaced indices from 0..31
    final picks = <int>[];
    for (int i = 0; i < 20; i++) {
      picks.add((i * 31.0 / 19.0).round());
    }
    // Remove duplicates and ensure exactly 20
    final unique = picks.toSet().toList()..sort();
    while (unique.length < 20) {
      for (int idx = 0; idx < 32 && unique.length < 20; idx++) {
        if (!unique.contains(idx)) {
          unique.add(idx);
          unique.sort();
          break;
        }
      }
    }
    final pickedIndices = unique.take(20).toList();

    // Assign each of the 32 native bands to the nearest picked index
    final groups = List.generate(20, (_) => <int>[]);
    for (int native = 0; native < 32; native++) {
      int bestGroup = 0;
      int bestDist = 999;
      for (int g = 0; g < pickedIndices.length; g++) {
        final dist = (native - pickedIndices[g]).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestGroup = g;
        }
      }
      groups[bestGroup].add(native);
    }

    return BandMapping._(
      displayCount: 20,
      frequencies: pickedIndices.map((i) => _allFreqs[i]).toList(),
      nativeGroups: groups,
    );
  }
}
