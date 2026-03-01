import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

enum Stem { vocals, drums, bass, other }

class StemState {
  double volume;
  bool muted;
  bool soloed;

  StemState({
    this.volume = 1.0,
    this.muted = false,
    this.soloed = false,
  });

  StemState copyWith({double? volume, bool? muted, bool? soloed}) {
    return StemState(
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
    );
  }

  Map<String, dynamic> toJson() => {
    'volume': volume,
    'muted': muted,
    'soloed': soloed,
  };

  factory StemState.fromJson(Map<String, dynamic> json) => StemState(
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    muted: json['muted'] as bool? ?? false,
    soloed: json['soloed'] as bool? ?? false,
  );
}

class StemCache {
  static Future<String> stemDirFor(String songPath) async {
    final hash = md5.convert(utf8.encode(songPath)).toString();
    final cacheDir = await getTemporaryDirectory();
    return '${cacheDir.path}/stems/$hash';
  }

  static Future<bool> stemsExist(String songPath) async {
    final dir = await stemDirFor(songPath);
    final d = Directory(dir);
    if (!d.existsSync()) return false;
    return File('$dir/vocals.wav').existsSync() &&
        File('$dir/drums.wav').existsSync() &&
        File('$dir/bass.wav').existsSync() &&
        File('$dir/other.wav').existsSync();
  }

  static Future<Map<Stem, String>> stemPaths(String songPath) async {
    final dir = await stemDirFor(songPath);
    return {
      Stem.vocals: '$dir/vocals.wav',
      Stem.drums: '$dir/drums.wav',
      Stem.bass: '$dir/bass.wav',
      Stem.other: '$dir/other.wav',
    };
  }

  static Future<int> totalCacheSize() async {
    final cacheDir = await getTemporaryDirectory();
    final stemsDir = Directory('${cacheDir.path}/stems');
    if (!stemsDir.existsSync()) return 0;
    int total = 0;
    await for (final entity in stemsDir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  static Future<void> clearCache() async {
    final cacheDir = await getTemporaryDirectory();
    final stemsDir = Directory('${cacheDir.path}/stems');
    if (stemsDir.existsSync()) {
      await stemsDir.delete(recursive: true);
    }
  }

  static Future<void> clearStemsFor(String songPath) async {
    final dir = await stemDirFor(songPath);
    final d = Directory(dir);
    if (d.existsSync()) {
      await d.delete(recursive: true);
    }
  }
}
