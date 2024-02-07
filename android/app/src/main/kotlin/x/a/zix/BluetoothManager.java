package x.a.zix;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;

import java.util.ArrayList;

public class BluetoothManager {
  private  BluetoothAdapter bluetoothAdapter;
  private BluetoothDevice bluetoothDevice;
    ArrayList<String> deviceArrayAdapter = new ArrayList<String>();

  @SuppressLint({"MissingPermission", "NewApi"})
  public void showConnectedDevice(){
      for (BluetoothDevice device : bluetoothAdapter.getBondedDevices()) {

          deviceArrayAdapter.add(device.getName() + ": " + device.getType() + "%");
      }
  }
}
