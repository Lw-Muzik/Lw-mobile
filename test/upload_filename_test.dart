import 'dart:convert';

import 'package:eq_app/services/stream_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `X-File-Name` a desktop sends is attacker-controlled as far as this
/// server is concerned: it is the only caller-supplied part of a path we then
/// write to. These pin the guarantees `/upload` leans on.
void main() {
  String sanitize(String raw) => StreamServerController.sanitizeUploadName(raw);

  group('sanitizeUploadName', () {
    test('keeps an ordinary name untouched', () {
      expect(sanitize('Song.mp3'), 'Song.mp3');
    });

    test('decodes the percent-encoding the desktop applies', () {
      expect(sanitize('Blue%20Monday.mp3'), 'Blue Monday.mp3');
      expect(sanitize('Sigur%20R%C3%B3s.flac'), 'Sigur Rós.flac');
    });

    test('survives a malformed percent-escape instead of throwing', () {
      expect(sanitize('100%.mp3'), '100%.mp3');
    });

    group('directory traversal', () {
      test('strips a relative traversal down to the final segment', () {
        expect(sanitize('../../evil.mp3'), 'evil.mp3');
      });

      test('strips a traversal hidden inside the percent-encoding', () {
        expect(sanitize('..%2F..%2Fevil.mp3'), 'evil.mp3');
      });

      test('strips an absolute POSIX path', () {
        expect(sanitize('/etc/passwd.mp3'), 'passwd.mp3');
      });

      test('strips a Windows path and its backslashes', () {
        expect(sanitize(r'C:\Windows\System32\evil.mp3'), 'evil.mp3');
      });

      test('rejects a name that is nothing but traversal', () {
        expect(sanitize('..'), '');
        expect(sanitize('../..'), '');
        expect(sanitize('evil/../..'), '');
      });
    });

    test('drops control characters and NUL bytes', () {
      expect(sanitize('Bad\u0000Name.mp3'), 'BadName.mp3');
      expect(sanitize('Tab\tNew\nLine.mp3'), 'TabNewLine.mp3');
      expect(sanitize('Delete\u007f.mp3'), 'Delete.mp3');
      // A NUL would otherwise truncate the path at the syscall boundary, so
      // a name these checks saw as ".mp3" could reach the disk as something
      // else entirely.
      expect(sanitize('song\u0000.txt.mp3'), 'song.txt.mp3');
      expect(sanitize('song%00.mp3'), 'song.mp3');
    });

    test('will not produce a hidden dotfile', () {
      expect(sanitize('.hidden.mp3'), 'hidden.mp3');
      expect(sanitize('...hidden.mp3'), 'hidden.mp3');
    });

    test('rejects an empty or whitespace-only name', () {
      expect(sanitize(''), '');
      expect(sanitize('   '), '');
      expect(sanitize('%20%20'), '');
    });

    test('preserves unicode titles', () {
      expect(sanitize('Café — Naïve.mp3'), 'Café — Naïve.mp3');
      expect(sanitize('東京.flac'), '東京.flac');
      expect(sanitize('🎵 Banger 🎵.mp3'), '🎵 Banger 🎵.mp3');
    });

    group('length bounding', () {
      test('clamps an over-long name but keeps the extension', () {
        final long = '${'a' * 300}.mp3';
        final out = sanitize(long);
        expect(out.endsWith('.mp3'), isTrue);
        expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      });

      test('bounds by bytes, not characters, for multi-byte titles', () {
        // 300 CJK chars is 900 UTF-8 bytes — well past what ext4 accepts (255)
        // even though it "looks" the same length as an ASCII name that fits.
        final long = '${'東' * 300}.flac';
        final out = sanitize(long);
        expect(out.endsWith('.flac'), isTrue);
        expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      });

      test('does not split a multi-byte code point when truncating', () {
        final out = sanitize('${'🎵' * 200}.mp3');
        // A split surrogate pair would not survive an encode/decode round-trip.
        expect(utf8.decode(utf8.encode(out)), out);
        expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      });

      test('does not mistake a dot in a long title for an extension', () {
        // The trailing run is too long to be an extension, so it is not
        // preserved — but the name must still come back bounded and usable.
        final out = sanitize("${'a' * 200}.${'b' * 40}");
        expect(out, isNotEmpty);
        expect(utf8.encode(out).length, lessThanOrEqualTo(180));
      });
    });
  });
}
