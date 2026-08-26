/// Handing the video surface between the two players.
///
/// There are two players so tracks can crossfade, one video surface per player,
/// and a rebind asks for both things at once: give the audible player the
/// picture, take it off everyone else. Those two halves run over the same map
/// of surfaces, so the order they touch it in is the whole of the behaviour.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:eq_app/Helpers/AudioHandler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a surface created mid-detach does not break the detach', () async {
    final handler = HypeAudioHandler();
    // A previous track's player, holding the surface that has to be given up.
    handler.videoOutputFor(AudioPlayer());

    final detaching = handler.detachAllVideo(except: handler.player);
    // What the attach half of a rebind does at the same moment: the incoming
    // player has never had a surface, so asking for one adds to the very map
    // being walked. Iterating it directly threw here, and the crossfade into
    // the first video of a session was exactly this sequence.
    handler.videoOutputFor(AudioPlayer());

    await expectLater(detaching, completes);
  });

  test('the audible player keeps the picture while the rest give theirs up',
      () async {
    final handler = HypeAudioHandler();
    final kept = handler.videoOutputFor(handler.player);
    final dropped = handler.videoOutputFor(AudioPlayer());
    await kept.attach();
    await dropped.attach();

    await handler.detachAllVideo(except: handler.player);

    expect(kept.isWanted, isTrue,
        reason: 'the audible player is the one the picture is moving to; '
            'reclaiming its surface is what blacked the stage out');
    expect(dropped.isWanted, isFalse,
        reason: 'the player the fade just stopped must not go on holding a '
            'surface, or its last frame freezes over the next track');
  });
}
