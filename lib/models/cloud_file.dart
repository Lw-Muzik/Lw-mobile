import '/exports/exports.dart';

enum CloudProvider { googleDrive, dropbox }

class CloudFile {
  final CloudProvider provider;
  final String fileId;
  final String name;
  final String folderPath;
  final int size;
  final String mimeType;
  final String? thumbnailUrl;
  final DateTime? modifiedDate;

  CloudFile({
    required this.provider,
    required this.fileId,
    required this.name,
    required this.folderPath,
    required this.size,
    required this.mimeType,
    this.thumbnailUrl,
    this.modifiedDate,
  });

  String get folderName =>
      folderPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Root';

  /// Convert to SongModel for the existing player pipeline.
  /// [streamUrl] is the direct HTTP URL for audio streaming.
  SongModel toSongModel(String streamUrl) => SongModel({
        "_id": fileId.hashCode.abs(),
        "_data": streamUrl,
        "title": name.replaceAll(
            RegExp(r'\.(mp3|m4a|flac|wav|ogg|aac|wma)$', caseSensitive: false),
            ''),
        "artist": "Cloud",
        "album": thumbnailUrl ?? "",
        "duration": 0,
        "_display_name": name,
        "_display_name_wo_ext": name.split('.').first,
        "_size": size,
        "file_extension": name.split('.').last,
      });

  Map<String, dynamic> toJson() => {
        'provider': provider.index,
        'fileId': fileId,
        'name': name,
        'folderPath': folderPath,
        'size': size,
        'mimeType': mimeType,
        'thumbnailUrl': thumbnailUrl,
        'modifiedDate': modifiedDate?.toIso8601String(),
      };

  factory CloudFile.fromJson(Map<String, dynamic> json) => CloudFile(
        provider: CloudProvider.values[json['provider'] as int],
        fileId: json['fileId'] as String,
        name: json['name'] as String,
        folderPath: json['folderPath'] as String,
        size: json['size'] as int,
        mimeType: json['mimeType'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        modifiedDate: json['modifiedDate'] != null
            ? DateTime.parse(json['modifiedDate'] as String)
            : null,
      );
}
