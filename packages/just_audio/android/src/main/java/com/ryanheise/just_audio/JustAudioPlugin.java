package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * JustAudioPlugin
 */
public class JustAudioPlugin implements FlutterPlugin {
    private MethodChannel channel;
    /**
     * Video attach/detach and quality selection.
     *
     * <p>Its own channel rather than extra methods on the one above, because the
     * Dart side of that channel is `just_audio_platform_interface` — a published
     * package this app consumes rather than owns. Video rides alongside it so the
     * upstream plugin can be updated without this work having to be merged back
     * in each time.
     */
    private MethodChannel videoChannel;
    private MainMethodCallHandler methodCallHandler;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Context applicationContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        methodCallHandler = new MainMethodCallHandler(
                applicationContext, messenger, binding.getTextureRegistry());

        channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
        channel.setMethodCallHandler(methodCallHandler);
        videoChannel = new MethodChannel(messenger, "com.ryanheise.just_audio.video");
        videoChannel.setMethodCallHandler(methodCallHandler);
        @SuppressWarnings("deprecation")
        FlutterEngine engine = binding.getFlutterEngine();
        engine.addEngineLifecycleListener(new EngineLifecycleListener() {
            @Override
            public void onPreEngineRestart() {
                methodCallHandler.dispose();
            }

            @Override
            public void onEngineWillDestroy() {
            }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        methodCallHandler.dispose();
        methodCallHandler = null;

        channel.setMethodCallHandler(null);
        videoChannel.setMethodCallHandler(null);
    }
}
