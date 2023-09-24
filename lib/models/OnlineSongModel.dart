import 'dart:convert';

OnlineSongModel onlineSongModelFromJson(String str) =>
    OnlineSongModel.fromJson(json.decode(str));

String onlineSongModelToJson(OnlineSongModel data) =>
    json.encode(data.toJson());

class OnlineSongModel {
  final String title;
  final String artist;
  final String artWork;
  final String url;

  OnlineSongModel({
    required this.title,
    required this.artist,
    required this.artWork,
    required this.url,
  });

  factory OnlineSongModel.fromJson(Map<String, dynamic> json) =>
      OnlineSongModel(
        title: json["title"],
        artist: json["artist"],
        artWork: json["artWork"],
        url: json["url"],
      );

  Map<String, dynamic> toJson() => {
        "title": title,
        "artist": artist,
        "artWork": artWork,
        "url": url,
      };
}
