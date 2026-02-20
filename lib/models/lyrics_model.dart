/// Lyrics data models and LRC parser/encoder for Hype Muzik.

class LyricWord {
  final Duration startTime;
  final Duration endTime;
  final String text;

  const LyricWord({
    required this.startTime,
    required this.endTime,
    required this.text,
  });
}

class LyricLine {
  final Duration? timestamp;
  final String text;
  final List<LyricWord>? words;

  const LyricLine({this.timestamp, required this.text, this.words});

  LyricLine copyWith({Duration? timestamp, String? text}) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      words: words,
    );
  }
}

class LyricsData {
  final List<LyricLine> lines;
  final bool isSynced;
  final String raw;
  final String? artist;
  final String? title;
  final String? album;
  final int offsetMs;

  const LyricsData({
    required this.lines,
    required this.isSynced,
    required this.raw,
    this.artist,
    this.title,
    this.album,
    this.offsetMs = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'lines': lines.map((l) {
        final map = <String, dynamic>{'text': l.text};
        if (l.timestamp != null) map['timestamp'] = l.timestamp!.inMilliseconds;
        return map;
      }).toList(),
      'isSynced': isSynced,
      'raw': raw,
      if (artist != null) 'artist': artist,
      if (title != null) 'title': title,
      if (album != null) 'album': album,
      'offsetMs': offsetMs,
    };
  }

  factory LyricsData.fromJson(Map<String, dynamic> json) {
    final linesList = (json['lines'] as List).map((l) {
      final map = l as Map<String, dynamic>;
      return LyricLine(
        text: map['text'] as String,
        timestamp: map['timestamp'] != null
            ? Duration(milliseconds: (map['timestamp'] as num).toInt())
            : null,
      );
    }).toList();
    return LyricsData(
      lines: linesList,
      isSynced: json['isSynced'] as bool? ?? false,
      raw: json['raw'] as String? ?? '',
      artist: json['artist'] as String?,
      title: json['title'] as String?,
      album: json['album'] as String?,
      offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// LRC parsing
// ---------------------------------------------------------------------------

/// Matches `[mm:ss.xx]` or `[mm:ss.xxx]` timestamps.
final _timestampRe = RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{2,3}))?\]');

/// Matches metadata tags like `[ar:Artist Name]`.
final _metaRe = RegExp(r'^\[([a-z]+):(.*)\]$', caseSensitive: false);

/// Matches enhanced LRC word-level timing: `<mm:ss.xx>word`
final _wordRe = RegExp(r'<(\d{1,3}):(\d{2})(?:\.(\d{2,3}))?>([^<]*)');

Duration _parseTimestamp(Match m, [int group = 1]) {
  final min = int.parse(m.group(group)!);
  final sec = int.parse(m.group(group + 1)!);
  final msStr = m.group(group + 2) ?? '0';
  final ms = msStr.length == 2
      ? int.parse(msStr) * 10
      : int.parse(msStr);
  return Duration(minutes: min, seconds: sec, milliseconds: ms);
}

LyricsData parseLrc(String content) {
  String? artist, title, album;
  int offsetMs = 0;
  final lines = <LyricLine>[];
  bool hasSyncedLine = false;

  for (final rawLine in content.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;

    // Check for metadata tags (no timestamp)
    final metaMatch = _metaRe.firstMatch(line);
    if (metaMatch != null && !_timestampRe.hasMatch(line)) {
      final tag = metaMatch.group(1)!.toLowerCase();
      final value = metaMatch.group(2)!.trim();
      switch (tag) {
        case 'ar':
          artist = value;
        case 'ti':
          title = value;
        case 'al':
          album = value;
        case 'offset':
          offsetMs = int.tryParse(value) ?? 0;
      }
      continue;
    }

    // Extract all timestamps from the line (some LRC lines have multiple: [00:01.00][00:05.00]text)
    final timestamps = _timestampRe.allMatches(line).toList();
    if (timestamps.isEmpty) {
      // Unsynced line
      lines.add(LyricLine(text: line));
      continue;
    }

    // Strip timestamps to get text
    final text = line.replaceAll(_timestampRe, '').trim();
    if (text.isEmpty) continue;

    hasSyncedLine = true;

    // Parse enhanced word-level timing if present
    List<LyricWord>? words;
    final wordMatches = _wordRe.allMatches(text).toList();
    if (wordMatches.isNotEmpty) {
      words = [];
      for (int i = 0; i < wordMatches.length; i++) {
        final wm = wordMatches[i];
        final wStart = _parseTimestampFromWordMatch(wm);
        final wEnd = i + 1 < wordMatches.length
            ? _parseTimestampFromWordMatch(wordMatches[i + 1])
            : wStart + const Duration(milliseconds: 500);
        final wText = wm.group(4)?.trim() ?? '';
        if (wText.isNotEmpty) {
          words.add(LyricWord(startTime: wStart, endTime: wEnd, text: wText));
        }
      }
    }

    final plainText = text.replaceAll(_wordRe, '').isEmpty && words != null
        ? words.map((w) => w.text).join(' ')
        : text.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:\.\d{2,3})?>'), '').trim();

    // Add a LyricLine for each timestamp
    for (final ts in timestamps) {
      lines.add(LyricLine(
        timestamp: _parseTimestamp(ts),
        text: plainText,
        words: words,
      ));
    }
  }

  // Sort synced lines by timestamp
  if (hasSyncedLine) {
    lines.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return a.timestamp!.compareTo(b.timestamp!);
    });
  }

  return LyricsData(
    lines: lines,
    isSynced: hasSyncedLine,
    raw: content,
    artist: artist,
    title: title,
    album: album,
    offsetMs: offsetMs,
  );
}

Duration _parseTimestampFromWordMatch(RegExpMatch m) {
  final min = int.parse(m.group(1)!);
  final sec = int.parse(m.group(2)!);
  final msStr = m.group(3) ?? '0';
  final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
  return Duration(minutes: min, seconds: sec, milliseconds: ms);
}

// ---------------------------------------------------------------------------
// LRC encoding
// ---------------------------------------------------------------------------

String encodeLrc(LyricsData data) {
  final buf = StringBuffer();

  if (data.title != null) buf.writeln('[ti:${data.title}]');
  if (data.artist != null) buf.writeln('[ar:${data.artist}]');
  if (data.album != null) buf.writeln('[al:${data.album}]');
  if (data.offsetMs != 0) buf.writeln('[offset:${data.offsetMs}]');

  for (final line in data.lines) {
    if (line.timestamp != null) {
      buf.writeln('${_formatTimestamp(line.timestamp!)}${line.text}');
    } else {
      buf.writeln(line.text);
    }
  }

  return buf.toString();
}

String _formatTimestamp(Duration d) {
  final min = d.inMinutes.toString().padLeft(2, '0');
  final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
  final ms = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
  return '[$min:$sec.$ms]';
}
