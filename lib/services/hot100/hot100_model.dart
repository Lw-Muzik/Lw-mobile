class Hot100Song {
  final String title;
  final String artist;
  final String artWork;
  final String url;

  const Hot100Song({
    required this.title,
    required this.artist,
    required this.artWork,
    required this.url,
  });

  factory Hot100Song.fromJson(Map<String, dynamic> json) => Hot100Song(
    title: (json['title'] as String? ?? '').trim(),
    artist: (json['artist'] as String? ?? '').trim(),
    artWork: (json['artWork'] as String? ?? '').trim(),
    url: (json['url'] as String? ?? '').trim(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'artWork': artWork,
    'url': url,
  };
}
