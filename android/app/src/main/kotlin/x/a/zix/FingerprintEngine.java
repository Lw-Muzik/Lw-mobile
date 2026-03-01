package x.a.zix;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.util.Log;

import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.util.HashMap;
import java.util.Map;

/**
 * Decodes audio files to PCM via MediaCodec and generates Chromaprint fingerprints.
 */
public class FingerprintEngine {

    private static final String TAG = "FingerprintEngine";
    private static final long MAX_DECODE_US = 120_000_000L; // 120 seconds of audio

    static {
        System.loadLibrary("eq_app");
    }

    /** JNI: compute Chromaprint fingerprint from raw int16 PCM. */
    private static native String nativeFingerprint(short[] pcmData, int sampleRate, int channels);

    /**
     * Generates an audio fingerprint for the given file.
     * Returns a map with "fingerprint" (String) and "duration" (int, seconds),
     * or null on failure.
     */
    public static Map<String, Object> generateFingerprint(String filePath) {
        if (filePath == null || !new File(filePath).exists()) {
            return null;
        }

        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(filePath);

            // Find audio track
            int audioTrack = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat fmt = extractor.getTrackFormat(i);
                String mime = fmt.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    audioTrack = i;
                    format = fmt;
                    break;
                }
            }
            if (audioTrack < 0 || format == null) {
                return null;
            }

            extractor.selectTrack(audioTrack);

            int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            long durationUs = format.containsKey(MediaFormat.KEY_DURATION)
                    ? format.getLong(MediaFormat.KEY_DURATION)
                    : 0;
            int durationSec = (int) (durationUs / 1_000_000L);

            // Cap decode length
            long decodeLimitUs = Math.min(durationUs > 0 ? durationUs : MAX_DECODE_US, MAX_DECODE_US);

            String mime = format.getString(MediaFormat.KEY_MIME);
            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(format, null, null, 0);
            codec.start();

            // Estimate PCM buffer size: sampleRate * channels * 2 bytes * seconds
            int estimatedSamples = sampleRate * channels * (int) (decodeLimitUs / 1_000_000L + 1);
            // Use a growable short array backed by a list
            short[] pcmBuffer = new short[Math.min(estimatedSamples, sampleRate * channels * 130)];
            int pcmOffset = 0;

            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;
            long decodedUs = 0;

            while (!outputDone) {
                // Feed input
                if (!inputDone) {
                    int inIdx = codec.dequeueInputBuffer(10_000);
                    if (inIdx >= 0) {
                        ByteBuffer inBuf = codec.getInputBuffer(inIdx);
                        int read = extractor.readSampleData(inBuf, 0);
                        if (read < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            long pts = extractor.getSampleTime();
                            codec.queueInputBuffer(inIdx, 0, read, pts, 0);
                            extractor.advance();
                            if (pts > decodeLimitUs) {
                                codec.queueInputBuffer(
                                    codec.dequeueInputBuffer(10_000),
                                    0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                                inputDone = true;
                            }
                        }
                    }
                }

                // Drain output
                int outIdx = codec.dequeueOutputBuffer(info, 10_000);
                if (outIdx >= 0) {
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true;
                    }
                    ByteBuffer outBuf = codec.getOutputBuffer(outIdx);
                    if (outBuf != null && info.size > 0) {
                        outBuf.order(ByteOrder.nativeOrder());
                        ShortBuffer shorts = outBuf.asShortBuffer();
                        int shortCount = info.size / 2;

                        // Grow buffer if needed
                        if (pcmOffset + shortCount > pcmBuffer.length) {
                            int newLen = Math.max(pcmBuffer.length * 2, pcmOffset + shortCount);
                            short[] newBuf = new short[newLen];
                            System.arraycopy(pcmBuffer, 0, newBuf, 0, pcmOffset);
                            pcmBuffer = newBuf;
                        }
                        shorts.get(pcmBuffer, pcmOffset, shortCount);
                        pcmOffset += shortCount;
                    }
                    codec.releaseOutputBuffer(outIdx, false);

                    decodedUs = info.presentationTimeUs;
                    if (decodedUs > decodeLimitUs) {
                        outputDone = true;
                    }
                } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (inputDone) {
                        // Give it a few more tries then bail
                        Thread.sleep(10);
                    }
                }
                // INFO_OUTPUT_FORMAT_CHANGED and INFO_OUTPUT_BUFFERS_CHANGED are fine, loop
            }

            codec.stop();
            codec.release();
            codec = null;

            if (pcmOffset == 0) {
                return null;
            }

            // Trim buffer to actual size
            if (pcmOffset < pcmBuffer.length) {
                short[] trimmed = new short[pcmOffset];
                System.arraycopy(pcmBuffer, 0, trimmed, 0, pcmOffset);
                pcmBuffer = trimmed;
            }

            String fingerprint = nativeFingerprint(pcmBuffer, sampleRate, channels);
            if (fingerprint == null || fingerprint.isEmpty()) {
                return null;
            }

            Map<String, Object> result = new HashMap<>();
            result.put("fingerprint", fingerprint);
            result.put("duration", durationSec);
            return result;

        } catch (Exception e) {
            Log.e(TAG, "Fingerprint generation failed", e);
            return null;
        } finally {
            try { extractor.release(); } catch (Exception ignored) {}
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) {}
                try { codec.release(); } catch (Exception ignored) {}
            }
        }
    }
}
