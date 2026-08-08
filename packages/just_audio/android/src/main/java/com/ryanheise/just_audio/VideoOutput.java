package com.ryanheise.just_audio;

import android.graphics.SurfaceTexture;
import android.view.Surface;

import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.VideoSize;
import androidx.media3.exoplayer.ExoPlayer;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.view.TextureRegistry;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The video half of a player that was only ever asked for audio.
 *
 * <p>The engine underneath this plugin is ExoPlayer, which has always been able to
 * decode and render video — it was simply never given a surface to draw on. This
 * class supplies one, so a track with a video stream renders into a Flutter
 * texture while its audio keeps travelling the ordinary path: through the
 * {@code AudioProcessor} chain this player builds, which is where the app's DSP
 * lives. Video therefore inherits the equaliser rather than needing one wired to
 * it, and inherits the queue, the notification and the background service for the
 * same reason — it is the same player.
 *
 * <h2>No surface means no video, deliberately</h2>
 *
 * <p>Detaching does not merely stop drawing: it disables the video track. A phone
 * with its screen off should not be decoding frames nobody can see, and on a
 * metered connection it should not be paying for them either. So backgrounding
 * turns a music video into exactly the audio stream it would have been, and
 * returning turns it back.
 */
class VideoOutput {
    /** Reported to Dart when a track has no video, and the aspect ratio is unknown. */
    private static final VideoSize NONE = VideoSize.UNKNOWN;

    private final TextureRegistry textureRegistry;
    private final BetterEventChannel events;

    @Nullable
    private TextureRegistry.SurfaceTextureEntry entry;
    @Nullable
    private Surface surface;

    /** The video renditions of the current item, in the order Dart is shown them. */
    private final List<Rendition> renditions = new ArrayList<>();
    /** Index into {@link #renditions}, or -1 for automatic (adaptive) selection. */
    private int selected = -1;

    private VideoSize lastSize = NONE;

    VideoOutput(final BinaryMessenger messenger, final String id, final TextureRegistry textureRegistry) {
        this.textureRegistry = textureRegistry;
        this.events = new BetterEventChannel(messenger, "com.ryanheise.just_audio.video." + id);
    }

    /** One selectable video rendition, and the override needed to pin it. */
    private static class Rendition {
        final TrackGroup group;
        final int indexInGroup;
        final int width;
        final int height;
        final int bitrate;
        final float frameRate;
        final String codecs;

        Rendition(TrackGroup group, int indexInGroup, Format format) {
            this.group = group;
            this.indexInGroup = indexInGroup;
            this.width = format.width;
            this.height = format.height;
            this.bitrate = format.bitrate;
            this.frameRate = format.frameRate;
            this.codecs = format.codecs != null ? format.codecs : "";
        }

        Map<String, Object> toMap() {
            final Map<String, Object> map = new HashMap<>();
            map.put("width", width);
            map.put("height", height);
            map.put("bitrate", bitrate);
            map.put("frameRate", frameRate == Format.NO_VALUE ? 0.0 : (double) frameRate);
            map.put("codecs", codecs);
            return map;
        }
    }

    /**
     * Creates the texture this player draws into and hands it to {@code player}.
     *
     * <p>Idempotent: asking twice returns the texture already in use rather than
     * orphaning one. The player screen and a full-screen route are two widgets
     * showing one stream, and they attach and detach independently.
     */
    long attach(@Nullable final ExoPlayer player) {
        if (entry == null) {
            entry = textureRegistry.createSurfaceTexture();
            final SurfaceTexture texture = entry.surfaceTexture();
            // Sized to the video once it is known; until then the default is
            // whatever the last item left behind, which stretches the first frame.
            if (lastSize.width > 0 && lastSize.height > 0) {
                texture.setDefaultBufferSize(lastSize.width, lastSize.height);
            }
            surface = new Surface(texture);
        }
        if (player != null) {
            player.setVideoSurface(surface);
            setTrackDisabled(player, false);
        }
        return entry.id();
    }

    /**
     * Gives the surface back and stops the video track.
     *
     * <p>The texture is released rather than kept warm. A retained texture is a
     * retained decoder buffer, and the case this exists for — the app in the
     * background — is exactly the case where holding one is least defensible.
     */
    void detach(@Nullable final ExoPlayer player) {
        if (player != null) {
            player.setVideoSurface(null);
            setTrackDisabled(player, true);
        }
        if (surface != null) {
            surface.release();
            surface = null;
        }
        if (entry != null) {
            entry.release();
            entry = null;
        }
    }

    /** Re-attaches after the underlying player was rebuilt (a new source, a new engine). */
    void reattach(@Nullable final ExoPlayer player) {
        if (player == null || surface == null) return;
        player.setVideoSurface(surface);
        setTrackDisabled(player, false);
        applySelection(player);
    }

    /**
     * Pins playback to one rendition, or returns it to adaptive selection.
     *
     * <p>{@code index} is a position in the list last broadcast to Dart; -1 is
     * "Auto", which is not a rendition but the absence of a choice — ExoPlayer's
     * own bitrate adaptation, which is what should be running unless the user has
     * said otherwise.
     */
    void select(@Nullable final ExoPlayer player, final int index) {
        selected = (index >= 0 && index < renditions.size()) ? index : -1;
        if (player != null) applySelection(player);
        broadcast();
    }

    int selectedIndex() {
        return selected;
    }

    private void applySelection(final ExoPlayer player) {
        final TrackSelectionParameters.Builder builder =
                player.getTrackSelectionParameters().buildUpon().clearOverridesOfType(C.TRACK_TYPE_VIDEO);
        if (selected >= 0 && selected < renditions.size()) {
            final Rendition rendition = renditions.get(selected);
            builder.addOverride(new TrackSelectionOverride(rendition.group, rendition.indexInGroup));
        }
        player.setTrackSelectionParameters(builder.build());
    }

    private void setTrackDisabled(final ExoPlayer player, final boolean disabled) {
        player.setTrackSelectionParameters(
                player.getTrackSelectionParameters()
                        .buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, disabled)
                        .build());
    }

    /**
     * Re-reads the renditions on offer.
     *
     * <p>A pinned choice cannot survive a new item — the group it referred to no
     * longer exists — so the selection returns to automatic whenever the track
     * list changes shape. Silently keeping an index into a different video is how
     * a 1080p pin becomes an arbitrary rendition of the next song.
     */
    void onTracksChanged(final Tracks tracks) {
        final List<Rendition> found = new ArrayList<>();
        for (final Tracks.Group group : tracks.getGroups()) {
            if (group.getType() != C.TRACK_TYPE_VIDEO) continue;
            final TrackGroup trackGroup = group.getMediaTrackGroup();
            for (int i = 0; i < trackGroup.length; i++) {
                final Format format = trackGroup.getFormat(i);
                if (format.width <= 0 || format.height <= 0) continue;
                found.add(new Rendition(trackGroup, i, format));
            }
        }
        // Largest first: a quality menu reads downwards from the best on offer.
        found.sort((a, b) -> Integer.compare(b.height * b.width, a.height * a.width));

        final boolean sameShape = found.size() == renditions.size() && sameHeights(found);
        renditions.clear();
        renditions.addAll(found);
        if (!sameShape) selected = -1;
        broadcast();
    }

    private boolean sameHeights(final List<Rendition> other) {
        for (int i = 0; i < other.size(); i++) {
            if (other.get(i).height != renditions.get(i).height) return false;
        }
        return true;
    }

    void onVideoSizeChanged(final VideoSize size) {
        lastSize = size;
        if (entry != null && size.width > 0 && size.height > 0) {
            entry.surfaceTexture().setDefaultBufferSize(size.width, size.height);
        }
        broadcast();
    }

    /** Called when the item changes, so a stale aspect ratio never outlives its video. */
    void onItemChanged() {
        lastSize = NONE;
        broadcast();
    }

    private void broadcast() {
        final List<Map<String, Object>> list = new ArrayList<>(renditions.size());
        for (final Rendition rendition : renditions) {
            list.add(rendition.toMap());
        }
        final Map<String, Object> event = new HashMap<>();
        event.put("width", lastSize.width);
        event.put("height", lastSize.height);
        event.put("pixelAspectRatio", (double) lastSize.pixelWidthHeightRatio);
        event.put("renditions", list);
        event.put("selected", selected);
        events.success(event);
    }

    void dispose(@Nullable final ExoPlayer player) {
        detach(player);
        renditions.clear();
        events.endOfStream();
    }
}
