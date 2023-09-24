// function to load artwork from songs ,albums ,artists and genres using ArtworkType
import 'package:eq_app/Helpers/index.dart';
import 'package:on_audio_query/on_audio_query.dart';

Future<void> fetchMetaData() async {
  // fetch artwork for artists first
  var artists = await OnAudioQuery().queryArtists();
  for (var artist in artists) {
    // save artwork
    await fetchArtwork("", artist.id,
        type: ArtworkType.ARTIST, other: artist.getMap['artist'] ?? 'Unknown');
  }
  // fetch artwork for albums
  var albums = await OnAudioQuery().queryAlbums();
  for (var album in albums) {
    // save artwork
    await fetchArtwork("", album.id,
        type: ArtworkType.ALBUM, other: album.getMap['album'] ?? 'Unknown');
  }
  // fetch artwork for genres
  var genres = await OnAudioQuery().queryGenres();
  for (var genre in genres) {
    await fetchArtwork("", genre.id,
        type: ArtworkType.GENRE, other: genre.getMap['genre'] ?? 'Unknown');
  }
  // fetch artwork for songs
  var songs = await OnAudioQuery().querySongs();
  for (var song in songs) {
    // save artwork
    await fetchArtwork(song.data, song.id, type: ArtworkType.AUDIO);
  }
}
