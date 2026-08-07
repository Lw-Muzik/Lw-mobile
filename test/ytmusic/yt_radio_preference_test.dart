/// The Autoplay setting, which is the gate on every station the app starts by
/// itself — including the one a search result now seeds.
///
/// Worth its own test because the failure is silent in both directions: a
/// preference that doesn't load leaves the field at its default `true`, so a
/// user who turned Autoplay off gets stations anyway and nothing anywhere says
/// so; and a load that lands late overwrites a setting the user just changed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eq_app/services/ytmusic/yt_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final radio = YtRadioQueue.instance;

  setUp(radio.resetForTest);

  test('nothing stored means on', () async {
    SharedPreferences.setMockInitialValues({});
    await radio.loadPreference();
    expect(radio.enabled, isTrue);
  });

  test('a stored "off" reaches the gate', () async {
    SharedPreferences.setMockInitialValues({'ytmusic.autoplay': false});
    await radio.loadPreference();
    expect(radio.enabled, isFalse,
        reason: 'the app would start stations the user has switched off');
  });

  test('turning it off survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    await radio.setEnabled(false);

    // As if the app had been started again: same stored preferences, a fresh
    // object that has not read them yet.
    radio.resetForTest();
    expect(radio.enabled, isTrue, reason: 'the unread default is meant to be on');

    await radio.loadPreference();
    expect(radio.enabled, isFalse);
  });

  test('every screen may ask, but only the first read touches the disk', () {
    SharedPreferences.setMockInitialValues({'ytmusic.autoplay': false});
    expect(identical(radio.loadPreference(), radio.loadPreference()), isTrue);
  });

  test('a read cannot land on top of a setting made while it was in flight',
      () async {
    SharedPreferences.setMockInitialValues({'ytmusic.autoplay': false});
    final inFlight = radio.loadPreference();
    // The user reaches the switch before the disk answers.
    await radio.setEnabled(true);
    await inFlight;
    expect(radio.enabled, isTrue,
        reason: 'the stored value is stale the moment the user changes it');
  });

  test('switching off closes the gate without abandoning the queue', () async {
    SharedPreferences.setMockInitialValues({});
    radio.attach(seed: 'abc123');
    expect(radio.isLive, isTrue);

    await radio.setEnabled(false);
    // Still attached, because the tracks already queued are still a YouTube
    // queue and `_fillQueue` checks `isLive` before appending to it. What
    // changes is that nothing further will be fetched.
    expect(radio.isLive, isTrue);
    expect(radio.enabled, isFalse);
  });
}
