package x.a.zix;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.database.Cursor;
import android.net.Uri;
import android.provider.MediaStore;

import com.mpatric.mp3agic.ID3v2;
import com.mpatric.mp3agic.ID3v24Tag;
import com.mpatric.mp3agic.Mp3File;

import org.jaudiotagger.audio.AudioFile;
import org.jaudiotagger.audio.AudioFileIO;
import org.jaudiotagger.tag.FieldKey;
import org.jaudiotagger.tag.Tag;

import java.io.*;
import java.util.logging.Level;
import java.util.logging.Logger;

public class LyricsManager {

    static {
        // Suppress JAudioTagger verbose logging on Android
        Logger.getLogger("org.jaudiotagger").setLevel(Level.OFF);
    }

    /**
     * Reads embedded lyrics from any audio format using JAudioTagger.
     * Supports: MP3 (USLT), M4A/AAC (©lyr), FLAC/OGG (LYRICS vorbis comment), WMA.
     * Falls back to mp3agic for MP3 files if JAudioTagger fails.
     * Returns the lyrics text, or null if not present.
     */
    public static String readLyrics(String filePath) {
        // Try JAudioTagger first — handles all formats
        try {
            AudioFile audioFile = AudioFileIO.read(new File(filePath));
            Tag tag = audioFile.getTag();
            if (tag != null) {
                String lyrics = tag.getFirst(FieldKey.LYRICS);
                if (lyrics != null && !lyrics.isEmpty()) {
                    return lyrics;
                }
            }
        } catch (Exception e) {
            // JAudioTagger couldn't parse — fall through
        }

        // Fallback: mp3agic for MP3 (proven, handles edge cases)
        try {
            Mp3File mp3 = new Mp3File(filePath);
            if (mp3.hasId3v2Tag()) {
                ID3v2 tag = mp3.getId3v2Tag();
                String lyrics = tag.getLyrics();
                if (lyrics != null && !lyrics.isEmpty()) {
                    return lyrics;
                }
            }
        } catch (Exception e) {
            // Not an MP3 or no lyrics
        }

        return null;
    }

    /**
     * Direct file-path write for Android 9 and below.
     * mp3agic writes to a temp file then we rename over the original.
     */
    public static boolean writeLyricsDirect(String filePath, String lyrics) {
        try {
            Mp3File mp3 = new Mp3File(filePath);
            ID3v2 tag;
            if (mp3.hasId3v2Tag()) {
                tag = mp3.getId3v2Tag();
            } else {
                tag = new ID3v24Tag();
                mp3.setId3v2Tag(tag);
            }
            tag.setLyrics(lyrics);

            String tempPath = filePath + ".tmp_lyrics";
            mp3.save(tempPath);

            File original = new File(filePath);
            File temp = new File(tempPath);

            if (!original.delete()) {
                temp.delete();
                return false;
            }
            if (!temp.renameTo(original)) {
                return false;
            }
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            try {
                new File(filePath + ".tmp_lyrics").delete();
            } catch (Exception ignored) {}
            return false;
        }
    }

    /**
     * Copies the original file to cache, modifies lyrics with mp3agic, returns
     * the modified file. Returns null on failure. Caller must delete the file.
     */
    public static File prepareModifiedFile(File cacheDir, String filePath, String lyrics) {
        File cacheCopy = new File(cacheDir, "lyrics_src.mp3");
        File modified = new File(cacheDir, "lyrics_modified.mp3");
        try {
            copyFile(new File(filePath), cacheCopy);
            Mp3File mp3 = new Mp3File(cacheCopy);
            ID3v2 tag;
            if (mp3.hasId3v2Tag()) {
                tag = mp3.getId3v2Tag();
            } else {
                tag = new ID3v24Tag();
                mp3.setId3v2Tag(tag);
            }
            tag.setLyrics(lyrics);
            mp3.save(modified.getAbsolutePath());
            cacheCopy.delete();
            return modified;
        } catch (Exception e) {
            e.printStackTrace();
            cacheCopy.delete();
            modified.delete();
            return null;
        }
    }

    /**
     * Finds the MediaStore content URI for an audio file by its path.
     */
    public static Uri getMediaUri(ContentResolver resolver, String filePath) {
        Uri collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        String[] projection = {MediaStore.Audio.Media._ID};
        String selection = MediaStore.Audio.Media.DATA + "=?";
        String[] selectionArgs = {filePath};
        try (Cursor cursor = resolver.query(collection, projection, selection, selectionArgs, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                long id = cursor.getLong(0);
                return ContentUris.withAppendedId(collection, id);
            }
        }
        return null;
    }

    /**
     * Writes the modified file content to a MediaStore URI via ContentResolver.
     */
    public static boolean writeToUri(ContentResolver resolver, Uri uri, File modified) {
        try (OutputStream os = resolver.openOutputStream(uri, "wt");
             InputStream is = new FileInputStream(modified)) {
            if (os == null) return false;
            byte[] buf = new byte[8192];
            int len;
            while ((len = is.read(buf)) != -1) {
                os.write(buf, 0, len);
            }
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
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
