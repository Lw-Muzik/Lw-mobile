package x.a.zix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
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
import java.io.IOException;
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
    private static final int NOTIFICATION_ID = 9001;

    static {
        System.loadLibrary("eq_app");
    }

    // Native C++ stem separation: frequency-band crossover + Mid/Side decomposition
    private static native boolean nativeSeparateStems(
            float[] pcm, int numFrames, int sampleRate,
            float[] outVocals, float[] outDrums, float[] outBass, float[] outOther);

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

        // Step 1: Decode audio to float PCM
        float[] pcmData;
        int sampleRate;
        try {
            DecodedAudio decoded = decodeToFloat(filePath);
            if (decoded == null || cancelled.get()) {
                sendProgress(-1, "Decoding cancelled or failed");
                return;
            }
            pcmData = decoded.samples;
            sampleRate = decoded.sampleRate;
            sendProgress(10, "Audio decoded");
        } catch (Exception e) {
            Log.e(TAG, "Decode failed", e);
            sendProgress(-1, "Decode failed: " + e.getMessage());
            return;
        }

        // Step 2: Separate stems via C++ (frequency-band + M/S spatial separation)
        sendProgress(15, "Separating stems...");

        File outDir = new File(outputDir);
        if (!outDir.exists()) outDir.mkdirs();

        int numFrames = pcmData.length / 2; // stereo → frame count
        int stereoLen = numFrames * 2;

        // Allocate output buffers for 4 stems
        float[] vocalsData = new float[stereoLen];
        float[] drumsData  = new float[stereoLen];
        float[] bassData   = new float[stereoLen];
        float[] otherData  = new float[stereoLen];

        if (cancelled.get()) { sendProgress(-1, "Cancelled"); return; }

        // Call native C++ separation (Butterworth crossovers + M/S decomposition)
        boolean success = nativeSeparateStems(pcmData, numFrames, sampleRate,
                vocalsData, drumsData, bassData, otherData);

        if (!success) {
            sendProgress(-1, "Native separation failed");
            return;
        }
        sendProgress(60, "Stems separated");

        // Step 3: Write 4 WAV files
        String[] stemNames = {"vocals", "drums", "bass", "other"};
        float[][] stemData = {vocalsData, drumsData, bassData, otherData};

        for (int i = 0; i < 4; i++) {
            if (cancelled.get()) { sendProgress(-1, "Cancelled"); return; }
            sendProgress(60 + (i + 1) * 10, "Writing " + stemNames[i] + "...");
            try {
                writeWavFloat(new File(outDir, stemNames[i] + ".wav"),
                        stemData[i], sampleRate, 2);
            } catch (IOException e) {
                Log.e(TAG, "Failed to write " + stemNames[i], e);
                sendProgress(-1, "Write failed: " + e.getMessage());
                return;
            }
        }

        // Free large buffers early
        vocalsData = null; drumsData = null; bassData = null; otherData = null;
        pcmData = null;

        sendProgress(100, "Complete");
    }

    /**
     * Decode audio file to interleaved float PCM using MediaCodec.
     */
    private DecodedAudio decodeToFloat(String filePath) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
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
            extractor.release();
            return null;
        }

        extractor.selectTrack(audioTrack);
        int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
        int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
        long durationUs = format.containsKey(MediaFormat.KEY_DURATION)
                ? format.getLong(MediaFormat.KEY_DURATION) : 0;

        // Estimate output size
        int estimatedFrames = (int) ((durationUs / 1_000_000.0) * sampleRate) + sampleRate;
        int estimatedSamples = estimatedFrames * channels;

        String mime = format.getString(MediaFormat.KEY_MIME);
        MediaCodec codec = MediaCodec.createDecoderByType(mime);
        codec.configure(format, null, null, 0);
        codec.start();

        float[] output = new float[estimatedSamples];
        int outputPos = 0;

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

            // Read output
            int outputIdx = codec.dequeueOutputBuffer(info, 10_000);
            if (outputIdx >= 0) {
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true;
                }

                ByteBuffer outputBuf = codec.getOutputBuffer(outputIdx);
                if (outputBuf != null && info.size > 0) {
                    outputBuf.order(ByteOrder.LITTLE_ENDIAN);
                    int shortCount = info.size / 2;

                    // Grow buffer if needed
                    if (outputPos + shortCount > output.length) {
                        float[] bigger = new float[(outputPos + shortCount) * 2];
                        System.arraycopy(output, 0, bigger, 0, outputPos);
                        output = bigger;
                    }

                    // Convert 16-bit PCM to float
                    for (int i = 0; i < shortCount; i++) {
                        output[outputPos++] = outputBuf.getShort() / 32768.0f;
                    }
                }
                codec.releaseOutputBuffer(outputIdx, false);
            }
        }

        codec.stop();
        codec.release();
        extractor.release();

        // Trim to actual size
        if (outputPos < output.length) {
            float[] trimmed = new float[outputPos];
            System.arraycopy(output, 0, trimmed, 0, outputPos);
            output = trimmed;
        }

        // If mono, convert to stereo
        if (channels == 1) {
            float[] stereo = new float[output.length * 2];
            for (int i = 0; i < output.length; i++) {
                stereo[i * 2] = output[i];
                stereo[i * 2 + 1] = output[i];
            }
            output = stereo;
            channels = 2;
        }

        DecodedAudio result = new DecodedAudio();
        result.samples = output;
        result.sampleRate = sampleRate;
        result.channels = channels;
        return result;
    }

    /**
     * Write interleaved float PCM to a WAV file (IEEE float format).
     */
    private static void writeWavFloat(File file, float[] data, int sampleRate, int channels)
            throws IOException {
        int dataSize = data.length * 4; // float32 = 4 bytes
        int fileSize = 44 + dataSize - 8;

        FileOutputStream fos = new FileOutputStream(file);
        ByteBuffer header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);

        // RIFF header
        header.put("RIFF".getBytes());
        header.putInt(fileSize);
        header.put("WAVE".getBytes());

        // fmt chunk
        header.put("fmt ".getBytes());
        header.putInt(16);                          // chunk size
        header.putShort((short) 3);                 // IEEE float
        header.putShort((short) channels);
        header.putInt(sampleRate);
        header.putInt(sampleRate * channels * 4);   // byte rate
        header.putShort((short) (channels * 4));    // block align
        header.putShort((short) 32);                // bits per sample

        // data chunk
        header.put("data".getBytes());
        header.putInt(dataSize);

        fos.write(header.array());

        // Write float data in chunks
        int chunkSize = 4096;
        ByteBuffer buf = ByteBuffer.allocate(chunkSize * 4).order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < data.length; i += chunkSize) {
            buf.clear();
            int end = Math.min(i + chunkSize, data.length);
            for (int j = i; j < end; j++) {
                buf.putFloat(data[j]);
            }
            buf.flip();
            fos.write(buf.array(), 0, buf.remaining());
        }

        fos.close();
    }

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

    private static class DecodedAudio {
        float[] samples;
        int sampleRate;
        int channels;
    }
}
