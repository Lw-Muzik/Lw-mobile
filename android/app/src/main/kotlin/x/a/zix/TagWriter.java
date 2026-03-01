package x.a.zix;

import android.content.ContentResolver;
import android.content.Context;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.util.Log;

import org.jaudiotagger.audio.AudioFile;
import org.jaudiotagger.audio.AudioFileIO;
import org.jaudiotagger.tag.FieldKey;
import org.jaudiotagger.tag.Tag;
import org.jaudiotagger.tag.images.Artwork;
import org.jaudiotagger.tag.images.ArtworkFactory;

import java.io.*;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Writes metadata tags to audio files using JAudioTagger.
 * Supports MP3, M4A, FLAC, OGG, WMA.
 * Fill-empty policy: only writes fields that are currently empty.
 */
public class TagWriter {

    private static final String TAG = "TagWriter";

    static {
        Logger.getLogger("org.jaudiotagger").setLevel(Level.OFF);
    }

    private static final Map<String, FieldKey> FIELD_MAP = Map.of(
        "title", FieldKey.TITLE,
        "artist", FieldKey.ARTIST,
        "album", FieldKey.ALBUM,
        "albumArtist", FieldKey.ALBUM_ARTIST,
        "year", FieldKey.YEAR,
        "track", FieldKey.TRACK,
        "isrc", FieldKey.ISRC,
        "musicBrainzRecordingId", FieldKey.MUSICBRAINZ_TRACK_ID
    );

    /**
     * Writes tags directly to a file (for Android < 11 or test use).
     * Only fills empty fields. artworkPath is optional cover art to embed.
     * Returns true on success.
     */
    public static boolean writeTagsDirect(String filePath, Map<String, String> tags,
                                           String artworkPath) {
        if (filePath == null || tags == null || tags.isEmpty()) return false;
        try {
            File file = new File(filePath);
            AudioFile audioFile = AudioFileIO.read(file);
            Tag tag = audioFile.getTagOrCreateAndSetDefault();

            boolean changed = applyTextTags(tag, tags);
            changed |= applyArtwork(tag, artworkPath);

            if (changed) {
                audioFile.commit();
            }
            return true;
        } catch (Exception e) {
            Log.e(TAG, "writeTagsDirect failed: " + filePath, e);
            return false;
        }
    }

    /** Overload for backward compat (no artwork). */
    public static boolean writeTagsDirect(String filePath, Map<String, String> tags) {
        return writeTagsDirect(filePath, tags, null);
    }

    /**
     * Prepares a modified copy of the audio file with tags written, for scoped storage writes.
     * Returns the modified file in cacheDir, or null on failure.
     * Caller must delete the returned file after use.
     */
    public static File prepareModifiedFile(File cacheDir, String filePath,
                                            Map<String, String> tags, String artworkPath) {
        if (filePath == null || tags == null || tags.isEmpty()) return null;

        File src = new File(filePath);
        String ext = getExtension(filePath);
        File cacheCopy = new File(cacheDir, "tag_src" + ext);
        File modified = new File(cacheDir, "tag_modified" + ext);

        try {
            copyFile(src, cacheCopy);

            AudioFile audioFile = AudioFileIO.read(cacheCopy);
            Tag tag = audioFile.getTagOrCreateAndSetDefault();

            boolean changed = applyTextTags(tag, tags);
            changed |= applyArtwork(tag, artworkPath);

            if (changed) {
                audioFile.commit();
            }

            // Rename cache copy to "modified" for clarity
            if (modified.exists()) modified.delete();
            if (!cacheCopy.renameTo(modified)) {
                copyFile(cacheCopy, modified);
                cacheCopy.delete();
            }

            return modified;
        } catch (Exception e) {
            Log.e(TAG, "prepareModifiedFile failed", e);
            cacheCopy.delete();
            modified.delete();
            return null;
        }
    }

    /** Overload for backward compat (no artwork). */
    public static File prepareModifiedFile(File cacheDir, String filePath, Map<String, String> tags) {
        return prepareModifiedFile(cacheDir, filePath, tags, null);
    }

    /** Applies text tags to the given Tag object (fill-empty policy). */
    private static boolean applyTextTags(Tag tag, Map<String, String> tags) {
        boolean changed = false;
        for (Map.Entry<String, String> entry : tags.entrySet()) {
            FieldKey fieldKey = FIELD_MAP.get(entry.getKey());
            if (fieldKey == null) continue;

            String newValue = entry.getValue();
            if (newValue == null || newValue.isEmpty()) continue;

            String existing = tag.getFirst(fieldKey);
            if (existing != null && !existing.isEmpty()) continue;

            try {
                tag.setField(fieldKey, newValue);
                changed = true;
            } catch (Exception e) {
                Log.w(TAG, "Failed to set field " + entry.getKey(), e);
            }
        }
        return changed;
    }

    /** Embeds cover artwork if the file currently has none. */
    private static boolean applyArtwork(Tag tag, String artworkPath) {
        if (artworkPath == null || artworkPath.isEmpty()) return false;
        try {
            // Only embed if no artwork exists
            if (tag.getFirstArtwork() != null) return false;

            File artFile = new File(artworkPath);
            if (!artFile.exists() || artFile.length() == 0) return false;

            Artwork artwork = ArtworkFactory.createArtworkFromFile(artFile);
            tag.setField(artwork);
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Failed to embed artwork", e);
            return false;
        }
    }

    /**
     * Triggers MediaStore re-scan for the given file so the OS picks up tag changes.
     * Call this after writing tags so queries return updated metadata.
     */
    public static void scanFile(Context context, String filePath) {
        if (filePath == null || context == null) return;
        MediaScannerConnection.scanFile(context,
                new String[]{filePath}, null, null);
    }

    private static String getExtension(String path) {
        int dot = path.lastIndexOf('.');
        return dot >= 0 ? path.substring(dot) : "";
    }

    private static void copyFile(File src, File dst) throws IOException {
        try (InputStream in = new FileInputStream(src);
             OutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) != -1) {
                out.write(buf, 0, len);
            }
        }
    }
}
