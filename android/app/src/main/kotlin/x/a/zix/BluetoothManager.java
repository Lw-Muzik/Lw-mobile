package x.a.zix;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;

import java.util.ArrayList;

public class BluetoothManager {
  private  BluetoothAdapter bluetoothAdapter;
  private BluetoothDevice bluetoothDevice;
    ArrayList<String> deviceArrayAdapter = new ArrayList<String>();
//    private final BroadcastReceiver batteryReceiver = new BroadcastReceiver() {
//        @Override
//        public void onReceive(Context context, Intent intent) {
//
//        }
//
//        @Override
//        public void onReceive(Context context, Intent intent) {
//            if (BluetoothDevice.ACTION_BATTERY_LEVEL_CHANGED.equals(intent.getAction())) {
//                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
//                int batteryLevel = intent.getIntExtra(BluetoothDevice.EXTRA_BATTERY_LEVEL, 0);
//                deviceArrayAdapter.add(device.getName() + ": " + batteryLevel + "%");
//            }
//        }
//    };
  @SuppressLint({"MissingPermission", "NewApi"})
  public void showConnectedDevice(){
      for (BluetoothDevice device : bluetoothAdapter.getBondedDevices()) {

          deviceArrayAdapter.add(device.getName() + ": " + device.getType() + "%");
      }
  }
}
