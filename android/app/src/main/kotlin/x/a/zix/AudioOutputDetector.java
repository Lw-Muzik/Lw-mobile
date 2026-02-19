package x.a.zix;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Build;

public class AudioOutputDetector {

    public static String getAudioOutputType(Context context) {
        if (context == null) return "speaker";

        AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audioManager == null) return "speaker";

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
            for (AudioDeviceInfo device : devices) {
                int type = device.getType();
                switch (type) {
                    case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP:
                    case AudioDeviceInfo.TYPE_BLUETOOTH_SCO:
                        return "bluetooth";
                    case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:
                    case AudioDeviceInfo.TYPE_WIRED_HEADSET:
                        return "wired_headphone";
                    case AudioDeviceInfo.TYPE_USB_DEVICE:
                    case AudioDeviceInfo.TYPE_USB_ACCESSORY:
                    case AudioDeviceInfo.TYPE_USB_HEADSET:
                        return "usb_audio";
                    default:
                        break;
                }
            }
        } else {
            if (audioManager.isBluetoothA2dpOn()) return "bluetooth";
            if (audioManager.isWiredHeadsetOn()) return "wired_headphone";
        }

        return "speaker";
    }
}
