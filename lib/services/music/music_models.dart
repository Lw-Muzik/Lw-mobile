class MusicSong {
  final String id;
  final String title;
  final String artist;
  final String artwork;

  const MusicSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.artwork,
  });

  factory MusicSong.fromJson(Map<String, dynamic> json) => MusicSong(
        id: (json['id'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? '').trim(),
        artist: (json['artist'] as String? ?? '').trim(),
        artwork: (json['artwork'] as String? ?? '').trim(),
      );
}

class MusicSongDetail extends MusicSong {
  final String? duration;
  final String? uploadDate;
  final int? plays;
  final int? downloads;
  final List<String> audioUrls;
  final List<MusicSong> relatedSongs;

  const MusicSongDetail({
    required super.id,
    required super.title,
    required super.artist,
    required super.artwork,
    this.duration,
    this.uploadDate,
    this.plays,
    this.downloads,
    required this.audioUrls,
    required this.relatedSongs,
  });

  factory MusicSongDetail.fromJson(Map<String, dynamic> json) =>
      MusicSongDetail(
        id: (json['id'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? '').trim(),
        artist: (json['artist'] as String? ?? '').trim(),
        artwork: (json['artwork'] as String? ?? '').trim(),
        duration: json['duration'] as String?,
        uploadDate: json['uploadDate'] as String?,
        plays: json['plays'] as int?,
        downloads: json['downloads'] as int?,
        audioUrls: (json['audioUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        relatedSongs: (json['relatedSongs'] as List?)
                ?.map((e) => MusicSong.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class MusicArtist {
  final String id;
  final String name;
  final String image;

  const MusicArtist({
    required this.id,
    required this.name,
    required this.image,
  });

  factory MusicArtist.fromJson(Map<String, dynamic> json) => MusicArtist(
        id: (json['id'] as String? ?? '').trim(),
        name: (json['name'] as String? ?? '').trim(),
        image: (json['image'] as String? ?? '').trim(),
      );
}

class MusicArtistDetail extends MusicArtist {
  final String? bio;
  final String? genre;
  final int? views;
  final int? listeners;
  final List<MusicSong> songs;

  const MusicArtistDetail({
    required super.id,
    required super.name,
    required super.image,
    this.bio,
    this.genre,
    this.views,
    this.listeners,
    required this.songs,
  });

  factory MusicArtistDetail.fromJson(Map<String, dynamic> json) =>
      MusicArtistDetail(
        id: (json['id'] as String? ?? '').trim(),
        name: (json['name'] as String? ?? '').trim(),
        image: (json['image'] as String? ?? '').trim(),
        bio: json['bio'] as String?,
        genre: json['genre'] as String?,
        views: json['views'] as int?,
        listeners: json['listeners'] as int?,
        songs: (json['songs'] as List?)
                ?.map((e) => MusicSong.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
