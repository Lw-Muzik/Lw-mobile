package x.a.zix;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import androidx.annotation.RequiresApi;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Publishes a file this phone received from a paired desktop (Phone Link
 * {@code POST /upload}) into the shared music library.
 *
 * <p>On API 29+ this inserts into {@code MediaStore.Audio.Media} with a
 * {@code RELATIVE_PATH} of {@code Music/HypeMuzik}. Under scoped storage the app
 * cannot write the shared tree by path at all, and the insert doubles as the
 * registration — the row <em>is</em> what {@code OnAudioQuery} reads, so the
 * track joins the phone's library (and becomes streamable back to the desktop)
 * with no separate scan. Below 29 there is no {@code RELATIVE_PATH}, so the file
 * is written directly under the legacy {@code WRITE_EXTERNAL_STORAGE} grant and
 * handed to {@link MediaScannerConnection}, which registers it and reports the
 * id back.
 */
final class MediaImporter {
    private static final String TAG = "MediaImporter";

    /** Sub-folder of the shared Music tree that received songs land in. */
    private static final String FOLDER = "HypeMuzik";
    private static final int SCAN_TIMEOUT_SECONDS = 20;

    private MediaImporter() {}

    /**
     * Copies {@code sourcePath} into the music library as {@code displayName}.
     * Returns {@code {id, path}}, or null if the import failed. Blocking — copies
     * a whole track, so call it off the main thread.
     */
    static Map<String, Object> importAudio(Context context, String sourcePath,
                                           String displayName, String mimeType) {
        final File source = new File(sourcePath);
        if (!source.isFile()) return null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return importScoped(context, source, displayName, mimeType);
        }
        return importLegacy(context, source, displayName);
    }

    /**
     * API 29+: MediaStore owns the file; we only ever touch it through a Uri.
     * The version gate lives in {@link #importAudio}, which Lint can't follow
     * across the call, hence the annotation.
     */
    @RequiresApi(api = Build.VERSION_CODES.Q)
    private static Map<String, Object> importScoped(Context context, File source,
                                                    String displayName, String mimeType) {
        final ContentResolver resolver = context.getContentResolver();
        final Uri collection =
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);

        final ContentValues values = new ContentValues();
        values.put(MediaStore.Audio.Media.DISPLAY_NAME, displayName);
        values.put(MediaStore.Audio.Media.MIME_TYPE, mimeType);
        values.put(MediaStore.Audio.Media.RELATIVE_PATH,
                Environment.DIRECTORY_MUSIC + File.separator + FOLDER);
        values.put(MediaStore.Audio.Media.IS_MUSIC, 1);
        // Hide the row from other apps (and our own library query) until the
        // bytes are actually behind it.
        values.put(MediaStore.Audio.Media.IS_PENDING, 1);

        final Uri uri = resolver.insert(collection, values);
        if (uri == null) return null;
        try {
            if (!copyToUri(resolver, source, uri)) {
                resolver.delete(uri, null, null);
                return null;
            }
            values.clear();
            values.put(MediaStore.Audio.Media.IS_PENDING, 0);
            resolver.update(uri, values, null, null);
            return describe(resolver, uri);
        } catch (Exception e) {
            Log.e(TAG, "MediaStore import failed: " + displayName, e);
            // Never leave a pending row behind — it would linger as a phantom
            // entry until the OS expires it.
            try {
                resolver.delete(uri, null, null);
            } catch (Exception ignored) {
                // Nothing more we can do; the original failure is what matters.
            }
            return null;
        }
    }

    /** Below API 29: no RELATIVE_PATH, so write the public tree and scan it in. */
    private static Map<String, Object> importLegacy(Context context, File source,
                                                    String displayName) {
        final File dir = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                FOLDER);
        if (!dir.isDirectory() && !dir.mkdirs()) {
            Log.e(TAG, "Could not create " + dir);
            return null;
        }
        final File dest = uniqueFile(dir, displayName);
        try {
            copyFile(source, dest);
        } catch (IOException e) {
            Log.e(TAG, "Legacy import failed: " + displayName, e);
            dest.delete();
            return null;
        }
        final Map<String, Object> out = new HashMap<>();
        out.put("id", idOf(scanBlocking(context, dest)));
        out.put("path", dest.getAbsolutePath());
        return out;
    }

    /**
     * The row id carried by a MediaStore Uri, or null if it carries none. Never
     * fatal: by the time we ask, the bytes are on disk and registered — the id is
     * a nicety for the reply, not something to fail a done upload over.
     */
    private static String idOf(Uri uri) {
        if (uri == null) return null;
        try {
            return String.valueOf(ContentUris.parseId(uri));
        } catch (Exception e) {
            Log.w(TAG, "Uri carries no row id: " + uri, e);
            return null;
        }
    }

    /** Reads back the row's id and on-disk path (what OnAudioQuery reports). */
    private static Map<String, Object> describe(ContentResolver resolver, Uri uri) {
        final Map<String, Object> out = new HashMap<>();
        out.put("id", idOf(uri));
        out.put("path", null);
        final String[] projection = {MediaStore.Audio.Media.DATA};
        try (Cursor cursor = resolver.query(uri, projection, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                out.put("path", cursor.getString(0));
            }
        } catch (Exception e) {
            // The insert already succeeded, so report it with the id alone
            // rather than failing an upload we've fully accepted.
            Log.w(TAG, "Could not read back the inserted row", e);
        }
        return out;
    }

    private static boolean copyToUri(ContentResolver resolver, File source, Uri uri)
            throws IOException {
        try (OutputStream out = resolver.openOutputStream(uri, "w");
             InputStream in = new FileInputStream(source)) {
            if (out == null) return false;
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) != -1) {
                out.write(buf, 0, len);
            }
            return true;
        }
    }

    /**
     * Registers {@code file} with MediaStore and waits for the resulting Uri.
     * The scan is inherently async, but the id is part of the reply we owe the
     * desktop and the caller is already on a worker thread, so block (bounded)
     * for it.
     */
    private static Uri scanBlocking(Context context, File file) {
        final CountDownLatch latch = new CountDownLatch(1);
        final AtomicReference<Uri> found = new AtomicReference<>();
        MediaScannerConnection.scanFile(
                context,
                new String[]{file.getAbsolutePath()},
                null,
                (path, uri) -> {
                    found.set(uri);
                    latch.countDown();
                });
        try {
            latch.await(SCAN_TIMEOUT_SECONDS, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return found.get();
    }

    /** Suffixes {@code (2)}, {@code (3)}… so a repeat push can't clobber a file. */
    private static File uniqueFile(File dir, String displayName) {
        File candidate = new File(dir, displayName);
        if (!candidate.exists()) return candidate;
        final int dot = displayName.lastIndexOf('.');
        final String stem = dot > 0 ? displayName.substring(0, dot) : displayName;
        final String ext = dot > 0 ? displayName.substring(dot) : "";
        for (int n = 2; n < 1000; n++) {
            candidate = new File(dir, stem + " (" + n + ")" + ext);
            if (!candidate.exists()) return candidate;
        }
        return candidate;
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
