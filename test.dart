import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  /*
  [  +64 ms] E/.example.eq_ap(21623): JNI ERROR (app bug): accessed deleted Global 0x4002
[   +1 ms] F/.example.eq_ap(21623): java_vm_ext.cc:577] JNI DETECTED ERROR IN APPLICATION: use of deleted global reference 0x4002
*/
  var dir = Directory("assets/autoeq.json");
  String d = File(dir.path).readAsStringSync();
  List<dynamic> t = jsonDecode(d)["speakers"];
  for (var data in t) {
    print(data["freq"]);
  }
}
