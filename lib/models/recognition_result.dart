/// Result of audio fingerprint recognition via AcoustID + MusicBrainz.
class RecognitionResult {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? year;
  final String? isrc;
  final String? musicBrainzRecordingId;
  final String? musicBrainzReleaseId;
  final double score; // AcoustID confidence 0.0-1.0

  const RecognitionResult({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.isrc,
    this.musicBrainzRecordingId,
    this.musicBrainzReleaseId,
    this.score = 0.0,
  });

  bool get hasUsefulData =>
      (title != null && title!.isNotEmpty) ||
      (artist != null && artist!.isNotEmpty);

  Map<String, String> toTagMap() {
    final map = <String, String>{};
    if (title != null && title!.isNotEmpty) map['title'] = title!;
    if (artist != null && artist!.isNotEmpty) map['artist'] = artist!;
    if (album != null && album!.isNotEmpty) map['album'] = album!;
    if (albumArtist != null && albumArtist!.isNotEmpty) map['albumArtist'] = albumArtist!;
    if (year != null && year!.isNotEmpty) map['year'] = year!;
    if (isrc != null && isrc!.isNotEmpty) map['isrc'] = isrc!;
    if (musicBrainzRecordingId != null && musicBrainzRecordingId!.isNotEmpty) {
      map['musicBrainzRecordingId'] = musicBrainzRecordingId!;
    }
    return map;
  }

  @override
  String toString() =>
      'RecognitionResult(title=$title, artist=$artist, album=$album, score=${score.toStringAsFixed(2)})';
}
