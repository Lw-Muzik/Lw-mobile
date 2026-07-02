package x.a.zix;

import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES30;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import io.flutter.view.TextureRegistry;

/**
 * Manages a dedicated GL render thread that:
 * 1. Sets up EGL context bound to a Flutter SurfaceTexture
 * 2. Creates a projectM instance
 * 3. Runs a render loop feeding PCM from VisualizerTapProcessor
 * 4. Renders projectM frames into the Flutter Texture widget
 */
public class ProjectMRenderer {
    private static final String TAG = "ProjectMRenderer";
    private static final String PRESETS_DIR = "milkdrop_presets";

    private final Context context;
    private final TextureRegistry textureRegistry;

    // Flutter texture
    private TextureRegistry.SurfaceTextureEntry textureEntry;
    private SurfaceTexture surfaceTexture;
    private long flutterTextureId = -1;

    // EGL state
    private EGLDisplay eglDisplay = EGL14.EGL_NO_DISPLAY;
    private EGLContext eglContext = EGL14.EGL_NO_CONTEXT;
    private EGLSurface eglSurface = EGL14.EGL_NO_SURFACE;

    // GL thread
    private HandlerThread glThread;
    private Handler glHandler;
    private boolean rendering = false;

    // projectM native handle
    private long pmHandle = 0;

    // Render parameters
    private int width = 512;
    private int height = 512;
    private int targetFps = 30;
    private long frameIntervalMs = 1000 / 30;

    // Configurable parameters (set before or after start, used by createProjectM)
    private float beatSensitivity = 1.0f;
    private double presetDuration = 30.0;
    private boolean presetLocked = false;
    private boolean hardCutEnabled = true;
    private int meshWidth = 48;
    private int meshHeight = 36;

    // Preset management
    private List<String> presetPaths = new ArrayList<>();
    private int currentPresetIndex = -1;
    private String presetsBaseDir;

    // Native methods (JNI bridge in projectm_bridge.cpp)
    private native long nativeCreate();
    private native void nativeDestroy(long handle);
    private native void nativeSetWindowSize(long handle, int width, int height);
    private native void nativeRenderFrame(long handle);
    private native void nativeAddPcmFloat(long handle, float[] samples);
    private native void nativeLoadPresetFile(long handle, String path, boolean smooth);
    private native void nativeLoadPresetData(long handle, String data, boolean smooth);
    private native void nativeSetBeatSensitivity(long handle, float sensitivity);
    private native void nativeSetPresetDuration(long handle, double seconds);
    private native void nativeSetPresetLocked(long handle, boolean locked);
    private native void nativeSetFps(long handle, int fps);
    private native void nativeSetHardCutEnabled(long handle, boolean enabled);
    private native void nativeSetSoftCutDuration(long handle, double seconds);
    private native void nativeSetMeshSize(long handle, int width, int height);
    private native void nativeSetAspectCorrection(long handle, boolean enabled);
    private native void nativeSetTextureSearchPaths(long handle, String[] paths);

    static {
        System.loadLibrary("eq_app");
    }

    public ProjectMRenderer(Context context, TextureRegistry textureRegistry) {
        this.context = context;
        this.textureRegistry = textureRegistry;
        this.presetsBaseDir = new File(context.getCacheDir(), PRESETS_DIR).getAbsolutePath();
    }

    /**
     * Initialize the Flutter texture and return its ID.
     * Must be called on the main thread.
     */
    public long init(int width, int height) {
        // Idempotent: if a previous session left a texture entry behind, tear
        // it (and any running GL thread / projectM handle) down before creating
        // a new one. Without this, a second init() overwrote textureEntry and
        // surfaceTexture, leaking the prior Flutter TextureRegistry entry and
        // SurfaceTexture. release() fully stops+releases prior state.
        if (textureEntry != null) {
            release();
        }

        this.width = width;
        this.height = height;

        // Create Flutter texture entry
        textureEntry = textureRegistry.createSurfaceTexture();
        surfaceTexture = textureEntry.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(width, height);
        flutterTextureId = textureEntry.id();

        Log.i(TAG, "Flutter texture created: id=" + flutterTextureId + " size=" + width + "x" + height);
        return flutterTextureId;
    }

    /**
     * Start the render loop on a dedicated GL thread.
     */
    public void start() {
        // `rendering` is only set true on the GL thread (inside the posted
        // task), so a rapid second start() would slip past a `rendering`-only
        // guard and spawn a second HandlerThread, leaking the first. glThread
        // is assigned synchronously here on the caller thread and nulled in
        // stop(), so guarding on it rejects double-start deterministically.
        if (rendering || glThread != null) return;

        // Extract presets from assets on first use
        extractPresetsIfNeeded();

        glThread = new HandlerThread("projectm-gl");
        glThread.start();
        glHandler = new Handler(glThread.getLooper());

        glHandler.post(() -> {
            try {
                setupEGL();
                createProjectM();
                rendering = true;
                VisualizerTapProcessor.getInstance().setTapEnabled(true);
                scheduleFrame();
                Log.i(TAG, "Render loop started at " + targetFps + " fps");
            } catch (Exception e) {
                Log.e(TAG, "Failed to start render loop", e);
                cleanupEGL();
            }
        });
    }

    /**
     * Stop the render loop and release all resources.
     */
    public void stop() {
        rendering = false;
        if (glHandler != null) {
            glHandler.post(() -> {
                destroyProjectM();
                cleanupEGL();
                VisualizerTapProcessor.getInstance().setTapEnabled(false);
                Log.i(TAG, "Render loop stopped");
            });
        }
        if (glThread != null) {
            glThread.quitSafely();
            try {
                glThread.join(1000);
            } catch (InterruptedException ignored) {}
            glThread = null;
            glHandler = null;
        }
    }

    /**
     * Release the Flutter texture entry. Call after stop().
     */
    public void release() {
        stop();
        if (textureEntry != null) {
            textureEntry.release();
            textureEntry = null;
            surfaceTexture = null;
            flutterTextureId = -1;
        }
    }

    // ---- Preset control ----

    public void loadPreset(String path) {
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeLoadPresetFile(pmHandle, path, true);
            });
        }
    }

    public void nextPreset() {
        if (presetPaths.isEmpty()) return;
        currentPresetIndex = (currentPresetIndex + 1) % presetPaths.size();
        loadPreset(presetPaths.get(currentPresetIndex));
    }

    public void previousPreset() {
        if (presetPaths.isEmpty()) return;
        currentPresetIndex = (currentPresetIndex - 1 + presetPaths.size()) % presetPaths.size();
        loadPreset(presetPaths.get(currentPresetIndex));
    }

    public void loadPresetByIndex(int index) {
        if (index < 0 || index >= presetPaths.size()) return;
        currentPresetIndex = index;
        loadPreset(presetPaths.get(index));
    }

    public String getCurrentPresetName() {
        if (currentPresetIndex < 0 || currentPresetIndex >= presetPaths.size()) return "";
        String path = presetPaths.get(currentPresetIndex);
        return new File(path).getName().replaceAll("\\.milk$", "");
    }

    public List<String> getPresetNames() {
        List<String> names = new ArrayList<>();
        for (String path : presetPaths) {
            names.add(new File(path).getName().replaceAll("\\.milk$", ""));
        }
        return names;
    }

    // ---- Parameter control ----

    public void setFps(int fps) {
        this.targetFps = Math.max(15, Math.min(60, fps));
        this.frameIntervalMs = 1000 / this.targetFps;
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetFps(pmHandle, this.targetFps);
            });
        }
    }

    public void setBeatSensitivity(float sensitivity) {
        this.beatSensitivity = sensitivity;
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetBeatSensitivity(pmHandle, sensitivity);
            });
        }
    }

    public void setPresetDuration(double seconds) {
        this.presetDuration = seconds;
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetPresetDuration(pmHandle, seconds);
            });
        }
    }

    public void setPresetLocked(boolean locked) {
        this.presetLocked = locked;
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetPresetLocked(pmHandle, locked);
            });
        }
    }

    public void setSize(int w, int h) {
        this.width = w;
        this.height = h;
        if (surfaceTexture != null) {
            surfaceTexture.setDefaultBufferSize(w, h);
        }
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetWindowSize(pmHandle, w, h);
            });
        }
    }

    public void setMeshSize(int w, int h) {
        this.meshWidth = w;
        this.meshHeight = h;
        if (glHandler != null && pmHandle != 0) {
            glHandler.post(() -> {
                if (pmHandle != 0) nativeSetMeshSize(pmHandle, w, h);
            });
        }
    }

    public long getFlutterTextureId() {
        return flutterTextureId;
    }

    // ---- EGL setup ----

    private void setupEGL() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
            throw new RuntimeException("eglGetDisplay failed");
        }

        int[] version = new int[2];
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw new RuntimeException("eglInitialize failed");
        }

        int[] configAttribs = {
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_DEPTH_SIZE, 16,
            EGL14.EGL_RENDERABLE_TYPE, 0x0040, /* EGL_OPENGL_ES3_BIT_KHR */
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_NONE
        };

        EGLConfig[] configs = new EGLConfig[1];
        int[] numConfigs = new int[1];
        if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)) {
            throw new RuntimeException("eglChooseConfig failed");
        }
        if (numConfigs[0] == 0) {
            throw new RuntimeException("No EGL config found for GLES 3.0");
        }

        int[] contextAttribs = {
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 3,
            EGL14.EGL_NONE
        };
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT,
                contextAttribs, 0);
        if (eglContext == EGL14.EGL_NO_CONTEXT) {
            throw new RuntimeException("eglCreateContext failed");
        }

        int[] surfaceAttribs = { EGL14.EGL_NONE };
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surfaceTexture,
                surfaceAttribs, 0);
        if (eglSurface == EGL14.EGL_NO_SURFACE) {
            throw new RuntimeException("eglCreateWindowSurface failed");
        }

        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw new RuntimeException("eglMakeCurrent failed");
        }

        Log.i(TAG, "EGL initialized: GLES " + GLES30.glGetString(GLES30.GL_VERSION));
    }

    private void cleanupEGL() {
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT);
            if (eglSurface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(eglDisplay, eglSurface);
                eglSurface = EGL14.EGL_NO_SURFACE;
            }
            if (eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(eglDisplay, eglContext);
                eglContext = EGL14.EGL_NO_CONTEXT;
            }
            EGL14.eglTerminate(eglDisplay);
            eglDisplay = EGL14.EGL_NO_DISPLAY;
        }
    }

    // ---- projectM lifecycle ----

    private void createProjectM() {
        pmHandle = nativeCreate();
        if (pmHandle == 0) {
            throw new RuntimeException("projectm_create failed");
        }

        nativeSetWindowSize(pmHandle, width, height);
        nativeSetFps(pmHandle, targetFps);
        nativeSetAspectCorrection(pmHandle, true);
        nativeSetMeshSize(pmHandle, meshWidth, meshHeight);
        nativeSetPresetDuration(pmHandle, presetDuration);
        nativeSetSoftCutDuration(pmHandle, 3.0);
        nativeSetHardCutEnabled(pmHandle, hardCutEnabled);
        nativeSetPresetLocked(pmHandle, presetLocked);
        nativeSetBeatSensitivity(pmHandle, beatSensitivity);

        // Set texture search path
        nativeSetTextureSearchPaths(pmHandle, new String[]{ presetsBaseDir });

        // Scan and load first preset
        scanPresets();
        if (!presetPaths.isEmpty()) {
            currentPresetIndex = 0;
            nativeLoadPresetFile(pmHandle, presetPaths.get(0), false);
        }

        Log.i(TAG, "projectM created with " + presetPaths.size() + " presets");
    }

    private void destroyProjectM() {
        if (pmHandle != 0) {
            nativeDestroy(pmHandle);
            pmHandle = 0;
        }
    }

    // ---- Render loop ----

    private void scheduleFrame() {
        if (!rendering || glHandler == null) return;
        glHandler.postDelayed(this::renderFrame, frameIntervalMs);
    }

    private void renderFrame() {
        if (!rendering || pmHandle == 0) return;

        long frameStart = System.nanoTime();

        // Feed PCM data from the audio pipeline
        float[] pcm = VisualizerTapProcessor.getInstance().getLatestPcm();
        if (pcm != null) {
            nativeAddPcmFloat(pmHandle, pcm);
        }

        // Render projectM frame
        nativeRenderFrame(pmHandle);

        // Swap EGL buffers to push frame to Flutter texture
        if (!EGL14.eglSwapBuffers(eglDisplay, eglSurface)) {
            Log.e(TAG, "eglSwapBuffers failed: " + EGL14.eglGetError());
        }

        // Adaptive scheduling: if this frame took longer than the budget,
        // schedule next frame immediately instead of adding delay on top.
        // This prevents frame queue buildup that causes stuttering.
        long renderTimeMs = (System.nanoTime() - frameStart) / 1_000_000;
        long delay = Math.max(0, frameIntervalMs - renderTimeMs);
        if (!rendering || glHandler == null) return;
        glHandler.postDelayed(this::renderFrame, delay);
    }

    // ---- Preset extraction ----

    private void extractPresetsIfNeeded() {
        File dir = new File(presetsBaseDir);
        if (dir.exists() && dir.list() != null && dir.list().length > 0) {
            return; // Already extracted
        }
        dir.mkdirs();

        AssetManager assets = context.getAssets();
        try {
            String[] files = assets.list(PRESETS_DIR);
            if (files == null || files.length == 0) {
                Log.w(TAG, "No presets found in assets/" + PRESETS_DIR);
                return;
            }
            for (String name : files) {
                if (!name.endsWith(".milk")) continue;
                try (InputStream in = assets.open(PRESETS_DIR + "/" + name);
                     FileOutputStream out = new FileOutputStream(new File(dir, name))) {
                    byte[] buf = new byte[8192];
                    int len;
                    while ((len = in.read(buf)) != -1) {
                        out.write(buf, 0, len);
                    }
                }
            }
            Log.i(TAG, "Extracted " + files.length + " presets to " + presetsBaseDir);
        } catch (IOException e) {
            Log.e(TAG, "Failed to extract presets", e);
        }
    }

    private void scanPresets() {
        presetPaths.clear();
        File dir = new File(presetsBaseDir);
        if (!dir.exists()) return;

        File[] files = dir.listFiles((d, name) -> name.endsWith(".milk"));
        if (files == null) return;

        Arrays.sort(files);
        for (File f : files) {
            presetPaths.add(f.getAbsolutePath());
        }
    }
}
