import 'dart:convert';
import 'package:flutter/services.dart';

class SpeakerFilter {
  final String type; // PK, LSC, HSC
  final double fc;
  final double gain;
  final double q;

  const SpeakerFilter({
    required this.type,
    required this.fc,
    required this.gain,
    required this.q,
  });

  /// Maps AutoEq filter type to BiquadType enum in C++:
  /// PK → Peaking (0), LSC → LowShelf (1), HSC → HighShelf (2)
  int get biquadType {
    switch (type) {
      case 'LSC':
        return 1;
      case 'HSC':
        return 2;
      default:
        return 0; // PK
    }
  }

  Map<String, dynamic> toNativeMap() => {
        'fc': fc,
        'gain': gain,
        'q': q,
        'type': biquadType,
      };

  factory SpeakerFilter.fromJson(Map<String, dynamic> json) => SpeakerFilter(
        type: json['type'] as String? ?? 'PK',
        fc: (json['fc'] as num).toDouble(),
        gain: (json['gain'] as num).toDouble(),
        q: (json['q'] as num).toDouble(),
      );
}

class SpeakerProfile {
  final String name;
  final String source;
  final String category;
  final double preamp;
  final List<SpeakerFilter> filters;

  const SpeakerProfile({
    required this.name,
    required this.source,
    required this.category,
    required this.preamp,
    required this.filters,
  });

  factory SpeakerProfile.fromJson(Map<String, dynamic> json) => SpeakerProfile(
        name: json['name'] as String,
        source: json['source'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        preamp: (json['preamp'] as num?)?.toDouble() ?? 0.0,
        filters: (json['filters'] as List)
            .map((f) => SpeakerFilter.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

class SpeakerProfileService {
  List<SpeakerProfile> _profiles = [];

  List<SpeakerProfile> get profiles => _profiles;

  Future<void> load() async {
    final data = await rootBundle.loadString('assets/autoeq.json');
    final json = jsonDecode(data) as Map<String, dynamic>;
    final list = json['profiles'] as List;
    _profiles = list
        .map((e) => SpeakerProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<SpeakerProfile> search(String query) {
    if (query.isEmpty) return _profiles;
    final lower = query.toLowerCase();
    return _profiles
        .where((p) => p.name.toLowerCase().contains(lower))
        .toList();
  }

  List<SpeakerProfile> byCategory(String category) {
    if (category == 'all') return _profiles;
    return _profiles.where((p) => p.category == category).toList();
  }
}
