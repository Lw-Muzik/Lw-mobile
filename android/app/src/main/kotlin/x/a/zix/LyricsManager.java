package x.a.zix;

import com.mpatric.mp3agic.ID3v2;
import com.mpatric.mp3agic.ID3v24Tag;
import com.mpatric.mp3agic.Mp3File;

import java.io.File;

public class LyricsManager {

    /**
     * Reads USLT (unsynchronized lyrics) from the ID3v2 tag of an MP3 file.
     * Returns the lyrics text, or null if not present.
     */
    public static String readLyrics(String filePath) {
        try {
            Mp3File mp3 = new Mp3File(filePath);
            if (mp3.hasId3v2Tag()) {
                ID3v2 tag = mp3.getId3v2Tag();
                String lyrics = tag.getLyrics();
                if (lyrics != null && !lyrics.isEmpty()) {
                    return lyrics;
                }
            }
            return null;
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    /**
     * Writes USLT lyrics into the ID3v2 tag of an MP3 file.
     * If no ID3v2 tag exists, creates a new ID3v2.4 tag.
     * mp3agic writes to a temp file then we rename over the original.
     */
    public static boolean writeLyrics(String filePath, String lyrics) {
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

            // mp3agic requires saving to a different file, then rename
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
            // Clean up temp file on failure
            try {
                new File(filePath + ".tmp_lyrics").delete();
            } catch (Exception ignored) {}
            return false;
        }
    }
}
