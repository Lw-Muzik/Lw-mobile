// To parse this JSON data, do
//
//     final artworkModel = artworkModelFromJson(jsonString);

import 'package:meta/meta.dart';
import 'dart:convert';

ArtworkModel artworkModelFromJson(String str) => ArtworkModel.fromJson(json.decode(str));

String artworkModelToJson(ArtworkModel data) => json.encode(data.toJson());

class ArtworkModel {
    final List<Result> results;

    ArtworkModel({
        required this.results,
    });

    factory ArtworkModel.fromJson(Map<String, dynamic> json) => ArtworkModel(
        results: List<Result>.from(json["results"].map((x) => Result.fromJson(x))),
    );

    Map<String, dynamic> toJson() => {
        "results": List<dynamic>.from(results.map((x) => x.toJson())),
    };
}

class Result {
    final String url;
    final int width;
    final int height;

    Result({
        required this.url,
        required this.width,
        required this.height,
    });

    factory Result.fromJson(Map<String, dynamic> json) => Result(
        url: json["url"],
        width: json["width"],
        height: json["height"],
    );

    Map<String, dynamic> toJson() => {
        "url": url,
        "width": width,
        "height": height,
    };
}
