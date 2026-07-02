package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import io.flutter.plugin.common.EventChannel;

/**
 * Foreground service for background stem separation.
 *
 * Decodes audio file to float PCM via MediaCodec, then runs C++ frequency-band
 * + Mid/Side spatial separation to produce 4 stem WAV files.
 *
 * Separation technique: Butterworth crossover filters + M/S decomposition.
 * - Bass: low-pass < 250 Hz (full stereo)
 * - Vocals: center-channel content bandpassed 250-8000 Hz
 * - Other: side-channel (panned instruments) + high frequencies
 * - Drums: residual (original minus other three stems)
 *
 * Reports progress via EventChannel to Dart UI.
 * Supports cancellation via stop service intent.
 */
public class StemSeparationService extends Service {
    private static final String TAG = "StemSeparation";
    private static final String CHANNEL_ID = "stem_separation";
    private static final int NOTIFICATION_ID = 9003;

    static {
        System.loadLibrary("eq_app");
    }

    // Native C++ stem separation (file-based): reads raw PCM from file, separates, writes WAVs.
    // All heavy memory work happens in native heap — avoids Java OOM.
    private static native boolean nativeSeparateStems(
            String inputRawPath, int numFrames, int sampleRate, String outputDir);

    private static final AtomicBoolean cancelled = new AtomicBoolean(false);
    private static final AtomicReference<EventChannel.EventSink> eventSink =
            new AtomicReference<>(null);

    private Thread workerThread;

    public static void setupEventChannel(EventChannel channel) {
        channel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink sink) {
                eventSink.set(sink);
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink.set(null);
            }
        });
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            stopSelf();
            return START_NOT_STICKY;
        }

        String action = intent.getAction();
        if ("CANCEL".equals(action)) {
            cancelled.set(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        String filePath = intent.getStringExtra("filePath");
        String outputDir = intent.getStringExtra("outputDir");
        if (filePath == null || outputDir == null) {
            stopSelf();
            return START_NOT_STICKY;
        }

        cancelled.set(false);
        startForeground(NOTIFICATION_ID, buildNotification(0));

        workerThread = new Thread(() -> {
            try {
                processStemSeparation(filePath, outputDir);
            } catch (Exception e) {
                Log.e(TAG, "Stem separation failed", e);
                sendProgress(-1, "Error: " + e.getMessage());
            } finally {
                stopForeground(STOP_FOREGROUND_REMOVE);
                stopSelf();
            }
        }, "StemSeparation");
        workerThread.start();

        return START_NOT_STICKY;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        cancelled.set(true);
        super.onDestroy();
    }

    private void processStemSeparation(String filePath, String outputDir) {
        sendProgress(0, "Decoding audio...");

        File outDir = new File(outputDir);
        if (!outDir.exists()) outDir.mkdirs();

        // Temp file for raw PCM — avoids holding entire song in Java heap
        File tempRawFile = new File(outDir, "_temp_raw.pcm");

        int sampleRate;
        int numFrames;
        try {
            // Step 1: Decode audio and stream to temp file (low Java memory)
            DecodedInfo info = decodeToFile(filePath, tempRawFile);
            if (info == null || cancelled.get()) {
                tempRawFile.delete();
                sendProgress(-1, "Decoding cancelled or failed");
                return;
            }
            sampleRate = info.sampleRate;
            numFrames = info.numFrames;
            sendProgress(10, "Audio decoded");
        } catch (Exception e) {
            Log.e(TAG, "Decode failed", e);
            tempRawFile.delete();
            sendProgress(-1, "Decode failed: " + e.getMessage());
            return;
        }

        if (cancelled.get()) {
            tempRawFile.delete();
            sendProgress(-1, "Cancelled");
            return;
        }

        // Step 2: Separate stems in C++ (all heavy memory in native heap)
        sendProgress(15, "Separating stems...");

        boolean success = nativeSeparateStems(
                tempRawFile.getAbsolutePath(), numFrames, sampleRate, outputDir);

        // Clean up temp file
        tempRawFile.delete();

        if (!success) {
            sendProgress(-1, "Native separation failed");
            return;
        }

        sendProgress(100, "Complete");
    }

    /**
     * Decode audio file to interleaved float PCM, streaming directly to a temp file.
     * This avoids holding the entire decoded audio in Java heap (prevents OOM).
     * Returns metadata (sampleRate, numFrames) or null on failure.
     */
    private DecodedInfo decodeToFile(String filePath, File outputFile) throws Exception {
        // Hold all three device-scarce resources so the finally block releases
        // them on EVERY path — a mid-decode exception must not leak a
        // MediaCodec, MediaExtractor or FileOutputStream. Modelled on
        // FingerprintEngine.decode()'s finally block.
        MediaExtractor extractor = null;
        MediaCodec codec = null;
        FileOutputStream fos = null;
        try {
            extractor = new MediaExtractor();
            extractor.setDataSource(filePath);

            int audioTrack = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    audioTrack = i;
                    format = f;
                    break;
                }
            }

            if (audioTrack < 0 || format == null) {
                return null;
            }

            extractor.selectTrack(audioTrack);
            int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);

            String mime = format.getString(MediaFormat.KEY_MIME);
            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(format, null, null, 0);
            codec.start();

            fos = new FileOutputStream(outputFile);
            // Small reusable buffer for float conversion — only a few KB in Java heap
            ByteBuffer writeBuf = ByteBuffer.allocate(8192).order(ByteOrder.LITTLE_ENDIAN);

            int totalSamples = 0;  // total float samples written (interleaved)
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;

            while (!outputDone && !cancelled.get()) {
                // Feed input
                if (!inputDone) {
                    int inputIdx = codec.dequeueInputBuffer(10_000);
                    if (inputIdx >= 0) {
                        ByteBuffer inputBuf = codec.getInputBuffer(inputIdx);
                        int read = extractor.readSampleData(inputBuf, 0);
                        if (read < 0) {
                            codec.queueInputBuffer(inputIdx, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(inputIdx, 0, read,
                                    extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }

                // Read output and stream to file
                int outputIdx = codec.dequeueOutputBuffer(info, 10_000);
                if (outputIdx >= 0) {
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true;
                    }

                    ByteBuffer outputBuf = codec.getOutputBuffer(outputIdx);
                    if (outputBuf != null && info.size > 0) {
                        outputBuf.order(ByteOrder.LITTLE_ENDIAN);
                        int shortCount = info.size / 2;

                        if (channels == 1) {
                            // Mono → stereo: duplicate each sample
                            for (int i = 0; i < shortCount; i++) {
                                float sample = outputBuf.getShort() / 32768.0f;
                                writeBuf.putFloat(sample);
                                writeBuf.putFloat(sample);
                                totalSamples += 2;
                                if (!writeBuf.hasRemaining()) {
                                    fos.write(writeBuf.array(), 0, writeBuf.position());
                                    writeBuf.clear();
                                }
                            }
                        } else {
                            // Stereo: convert 16-bit to float and write
                            for (int i = 0; i < shortCount; i++) {
                                float sample = outputBuf.getShort() / 32768.0f;
                                writeBuf.putFloat(sample);
                                totalSamples++;
                                if (!writeBuf.hasRemaining()) {
                                    fos.write(writeBuf.array(), 0, writeBuf.position());
                                    writeBuf.clear();
                                }
                            }
                        }
                    }
                    codec.releaseOutputBuffer(outputIdx, false);
                }
            }

            // Flush remaining data in writeBuf
            if (writeBuf.position() > 0) {
                fos.write(writeBuf.array(), 0, writeBuf.position());
            }

            // numFrames = total stereo samples / 2 channels
            int numFrames = totalSamples / 2;

            DecodedInfo result = new DecodedInfo();
            result.sampleRate = sampleRate;
            result.numFrames = numFrames;
            return result;
        } finally {
            // Close/flush the output file first (so the temp PCM is complete on
            // disk before the native separator reads it on the success path),
            // then release the codec and extractor. Each guarded independently;
            // secondary exceptions in cleanup are ignored so one failure can't
            // mask another leak.
            if (fos != null) {
                try { fos.close(); } catch (Exception ignored) {}
            }
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) {}
                try { codec.release(); } catch (Exception ignored) {}
            }
            if (extractor != null) {
                try { extractor.release(); } catch (Exception ignored) {}
            }
        }
    }

    // WAV writing is now handled in C++ (native heap) — removed writeWavFloat

    private void sendProgress(int percent, String message) {
        android.os.Handler mainHandler = new android.os.Handler(android.os.Looper.getMainLooper());
        mainHandler.post(() -> {
            EventChannel.EventSink sink = eventSink.get();
            if (sink != null) {
                java.util.Map<String, Object> event = new java.util.HashMap<>();
                event.put("progress", percent);
                event.put("message", message);
                sink.success(event);
            }
            // Update notification
            if (percent >= 0 && percent < 100) {
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                if (nm != null) nm.notify(NOTIFICATION_ID, buildNotification(percent));
            }
        });
    }

    private Notification buildNotification(int progress) {
        Intent cancelIntent = new Intent(this, StemSeparationService.class);
        cancelIntent.setAction("CANCEL");
        PendingIntent cancelPi = PendingIntent.getService(this, 0, cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setContentTitle("Separating Stems")
                .setContentText(progress + "%")
                .setProgress(100, progress, false)
                .addAction(android.R.drawable.ic_delete, "Cancel", cancelPi)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Stem Separation",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Shows progress during stem separation");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    private static class DecodedInfo {
        int sampleRate;
        int numFrames;
    }
}
