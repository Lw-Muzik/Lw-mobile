/// What happens when the player rejects the track it was given.
///
/// A YouTube stream url is single-use, expires, and — since YouTube began
/// gating them — can be refused outright the moment it is opened. So a source
/// error is not an exceptional condition here, it is Tuesday. It has to be
/// *observed*, or the subscription's error escapes as an unhandled async error
/// and the queue simply stops: a player showing a pause button over a track
/// that never starts, and an auto-advance that lands on silence.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:eq_app/Helpers/AudioHandler.dart';
import 'package:eq_app/player/playback_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the handler observes playback errors', () {
    test('an error reaches onPlaybackError instead of escaping', () async {
      final handler = HypeAudioHandler();
      final events = StreamController<PlaybackEvent>();
      addTearDown(events.close);

      Object? reported;
      handler.onPlaybackError = (error) => reported = error;
      handler.bindPlaybackEvents(events.stream);

      events.addError(PlayerException(0, 'Source error', 0));
      await pumpEventQueue();

      expect(reported, isA<PlayerException>());
    });

    /// The path Android actually takes, and the reason the first version of
    /// this fix did nothing on a device: `AudioPlayer.java`'s `sendError`
    /// raises an error on the event channel *and* sets `errorCode` on the next
    /// ordinary event — and this fork of just_audio swallows the former with an
    /// empty `onError`. Only the event data reaches Dart.
    test('an errorCode carried on an ordinary event is reported', () async {
      final handler = HypeAudioHandler();
      final events = StreamController<PlaybackEvent>();
      addTearDown(events.close);

      final reported = <Object>[];
      handler.onPlaybackError = reported.add;
      handler.bindPlaybackEvents(events.stream);

      events.add(PlaybackEvent(
        processingState: ProcessingState.idle,
        errorCode: 0,
        errorMessage: 'Source error',
      ));
      await pumpEventQueue();

      expect(reported, hasLength(1));
      expect((reported.single as PlayerException).message, 'Source error');
    });

    test('the same failure is reported once, not on every event after it',
        () async {
      final handler = HypeAudioHandler();
      final events = StreamController<PlaybackEvent>();
      addTearDown(events.close);

      var reports = 0;
      handler.onPlaybackError = (_) => reports++;
      handler.bindPlaybackEvents(events.stream);

      for (var i = 0; i < 3; i++) {
        events.add(PlaybackEvent(
          processingState: ProcessingState.idle,
          errorCode: 0,
          errorMessage: 'Source error',
          updatePosition: Duration(seconds: i),
        ));
      }
      await pumpEventQueue();

      expect(reports, 1);
    });

    /// Two dead urls in a row carry the same code. The player clears it when it
    /// loads something new, and a retry that never gets that far clears it by
    /// hand — otherwise the second failure reads as an echo of the first and the
    /// queue stalls one track short of moving on.
    test('a second failure after a retry is reported again', () async {
      final handler = HypeAudioHandler();
      final events = StreamController<PlaybackEvent>();
      addTearDown(events.close);

      var reports = 0;
      handler.onPlaybackError = (_) => reports++;
      handler.bindPlaybackEvents(events.stream);

      final failure = PlaybackEvent(
        processingState: ProcessingState.idle,
        errorCode: 0,
        errorMessage: 'Source error',
      );
      events.add(failure);
      await pumpEventQueue();
      handler.clearPlaybackError();
      events.add(failure);
      await pumpEventQueue();

      expect(reports, 2);
    });

    test('the stream survives the error, so the next track still reports',
        () async {
      final handler = HypeAudioHandler();
      final events = StreamController<PlaybackEvent>();
      addTearDown(events.close);

      var errors = 0;
      handler.onPlaybackError = (_) => errors++;
      handler.bindPlaybackEvents(events.stream);

      events.addError(PlayerException(0, 'Source error', 0));
      await pumpEventQueue();
      events.addError(PlayerException(0, 'Source error', 0));
      await pumpEventQueue();

      expect(errors, 2,
          reason: 'cancelOnError would have torn the subscription down after '
              'the first one, and every later track would go unreported');
    });
  });

  group('what to do about it', () {
    /// Each rescue draws a *new* InnerTube session, and about four in ten are
    /// gated. One retry would therefore leave a 40% chance of skipping a track
    /// that plays perfectly well on the next draw.
    test('a streamed track gets several fresh sessions before being given up',
        () {
      for (var attempt = 0; attempt < maxRescueAttempts; attempt++) {
        expect(
          recoveryFor(isStream: true, attempts: attempt, hasNext: true),
          PlaybackRecovery.reResolve,
          reason: 'attempt $attempt of $maxRescueAttempts',
        );
      }
    });

    test('but not for ever — it moves on rather than looping', () {
      expect(
        recoveryFor(
            isStream: true, attempts: maxRescueAttempts, hasNext: true),
        PlaybackRecovery.skip,
      );
    });

    /// A local file that will not open is not going to resolve into a
    /// different local file. Re-resolving it is a request to nowhere.
    test('a local track is skipped, not re-resolved', () {
      expect(
        recoveryFor(isStream: false, attempts: 0, hasNext: true),
        PlaybackRecovery.skip,
      );
    });

    test('the end of the queue stops instead of skipping past it', () {
      expect(
        recoveryFor(
            isStream: true, attempts: maxRescueAttempts, hasNext: false),
        PlaybackRecovery.stop,
      );
    });

    /// Order matters: the last track in a queue still deserves its retries.
    test('the last track is still rescued before the queue is stopped', () {
      expect(
        recoveryFor(isStream: true, attempts: 0, hasNext: false),
        PlaybackRecovery.reResolve,
      );
    });
  });
}
