import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  var dir = Directory("assets/autoeq.json");
  String d = File(dir.path).readAsStringSync();
  List<dynamic> t = jsonDecode(d)["speakers"];
  for (var data in t) {
    print(data["freq"]);
  }
}
