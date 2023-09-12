extension IntUtil on int {
  String get nSongs {
    return this == 1 ? "$this Song" : "$this Songs";
  }

  String get nAlbums {
    return this == 1 ? "$this Album" : "$this Albums";
  }

  String get aTracks {
    return this == 1 ? " Available Track\n" : " Available Tracks\n";
  }

  String get formatBandFrequency {
    if (this < 1000) {
      return "";
    }
    if (this < 1000000) {
      return "${this ~/ 1000}Hz";
    }
    return "${this ~/ 1000000}kHz";
  }
}

extension DoubleUtil on double {
  String get dps {
    return "${toStringAsFixed(1)} dB";
  }
}
