import 'dart:io';

class Files {
  static List<Map<String, String>> queryFromFolder(String path) {
    var dir = Directory(path).listSync(recursive: true);
    List<Map<String, String>> songs = dir
        .map((e) =>
            {"title": e.path.split("/").last.split(".").first, "path": e.path})
        .toList();
    return songs;
  }
}
