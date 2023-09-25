// function to load artwork from songs, albums, artists, and genres using ArtworkType
// ignore_for_file: use_build_context_synchronously

import 'dart:developer';

import 'package:eq_app/Helpers/index.dart';
import 'package:eq_app/controllers/PlayerController.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> fetchMetaData(BuildContext context) async {
  var controller = Provider.of<PlayerController>(context, listen: false);
  String query = "...";
  SharedPreferences prefs = await SharedPreferences.getInstance();
  // Maintain a set to keep track of processed file IDs
  Set<String> processedFileIds = <String>{};
  List<String>? processedFiles = prefs.getStringList("processedFileIds");
  if (processedFiles == null) {
    log("empty");
    // processedFileIds = processedFiles!.toSet();
    prefs.setStringList("processedFileIds", processedFileIds.toList());
  } else {
    processedFileIds = processedFiles.toSet();
  }
  Future<void> processArtists() async {
    var artists = await OnAudioQuery().queryArtists();
    if (artists.isNotEmpty) {
      controller.textHeader = "Working on artists";
      for (var artist in artists) {
        // Check if the artist's ID is in the set of processed IDs
        if (!processedFileIds.contains(artist.id.toString())) {
          // save artwork
          await fetchArtwork("", artist.id,
              type: ArtworkType.ARTIST,
              other: artist.getMap['artist'] ?? 'Unknown');
          query = "${artist.getMap['artist'] ?? 'Unknown'}";
          controller.text = query;

          // Add the artist's ID to the set of processed IDs
          processedFileIds.add(artist.id.toString());

          // await Future.delayed(const Duration(milliseconds: 90));
        }
      }
    }
  }

  Future<void> processAlbums() async {
    var albums = await OnAudioQuery().queryAlbums();
    if (albums.isNotEmpty) {
      controller.textHeader = "Working on albums";
      await Future.delayed(const Duration(seconds: 1));
      for (var album in albums) {
        if (!processedFileIds.contains(album.id.toString())) {
          // save artwork
          await fetchArtwork("", album.id,
              type: ArtworkType.ALBUM,
              other: album.getMap['album'] ?? 'Unknown');
          query = "${album.getMap['album'] ?? 'Unknown'}";
          controller.text = query;
          processedFileIds.add(album.id.toString());
        }
      }
    }
  }

  Future<void> processGenres() async {
    var genres = await OnAudioQuery().queryGenres();
    if (genres.isNotEmpty) {
      controller.textHeader = "Working on genres";
      for (var genre in genres) {
        if (!processedFileIds.contains(genre.id.toString())) {
          await fetchArtwork("", genre.id,
              type: ArtworkType.GENRE, other: genre.genre);
          query = genre.genre;
          controller.text = query;
          processedFileIds.add(genre.id.toString());
        }
      }
    }
  }

  Future<void> processSongs() async {
    var songs = await OnAudioQuery().querySongs();
    if (songs.isNotEmpty) {
      controller.textHeader = "Working on songs";
      for (var song in songs) {
        if (!processedFileIds.contains(song.id.toString())) {
          // save artwork
          await fetchArtwork(song.data, song.id, type: ArtworkType.AUDIO);
          query = song.title;
          controller.text = query;
          processedFileIds.add(song.id.toString());
        }
      }
    }
  }

  await processArtists();
  await processAlbums();
  await processGenres();
  await processSongs();
  prefs
      .setStringList("processedFileIds", processedFileIds.toList())
      .then((value) {
    controller.textHeader = "";
    controller.text = "All files assembled";
  });
  return query;
}
