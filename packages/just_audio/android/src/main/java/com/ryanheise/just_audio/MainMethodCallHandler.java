package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;

public class MainMethodCallHandler implements MethodCallHandler {

    private final Context applicationContext;
    private final BinaryMessenger messenger;
    private final TextureRegistry textureRegistry;

    private final Map<String, AudioPlayer> players = new HashMap<>();

    public MainMethodCallHandler(Context applicationContext,
            BinaryMessenger messenger,
            TextureRegistry textureRegistry) {
        this.applicationContext = applicationContext;
        this.messenger = messenger;
        this.textureRegistry = textureRegistry;
    }

    @Override
    public void onMethodCall(MethodCall call, @NonNull Result result) {
        switch (call.method) {
        case "init": {
            String id = call.argument("id");
            if (players.containsKey(id)) {
                result.error("Platform player " + id + " already exists", null, null);
                break;
            }
            List<Object> rawAudioEffects = call.argument("androidAudioEffects");
            players.put(
                id,
                new AudioPlayer(
                    applicationContext,
                    messenger,
                    id,
                    call.argument("audioLoadConfiguration"),
                    rawAudioEffects,
                    call.argument("androidAudioOffloadPreferences"),
                    call.argument("androidOffloadSchedulingEnabled"),
		    call.argument("useLazyPreparation"),
                    textureRegistry
                )
            );
            result.success(null);
            break;
        }
        case "disposePlayer": {
            String id = call.argument("id");
            AudioPlayer player = players.get(id);
            if (player != null) {
                player.dispose();
                players.remove(id);
            }
            result.success(new HashMap<String, Object>());
            break;
        }
        case "disposeAllPlayers": {
            dispose();
            result.success(new HashMap<String, Object>());
            break;
        }
        // ---- Video output ----
        //
        // A player that has gone away is not an error to attach to: the screen
        // asking for video and the player it belongs to are torn down by
        // separate lifecycles, and losing a race between them should leave the
        // caller without a texture, not with an exception.
        case "attachVideo": {
            AudioPlayer player = players.get((String) call.argument("id"));
            if (player == null) {
                result.success(null);
            } else {
                result.success(Long.valueOf(player.attachVideo()));
            }
            break;
        }
        case "detachVideo": {
            AudioPlayer player = players.get((String) call.argument("id"));
            if (player != null) player.detachVideo();
            result.success(null);
            break;
        }
        case "selectVideoQuality": {
            AudioPlayer player = players.get((String) call.argument("id"));
            if (player != null) {
                Integer index = call.argument("index");
                player.selectVideoQuality(index == null ? -1 : index);
            }
            result.success(null);
            break;
        }
        default:
            result.notImplemented();
            break;
        }
    }

    void dispose() {
        for (AudioPlayer player : new ArrayList<AudioPlayer>(players.values())) {
            player.dispose();
        }
        players.clear();
    }
}
