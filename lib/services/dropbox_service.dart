import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/cloud_file.dart';
import 'cloud_auth_service.dart';

class DropboxService {
  final CloudAuthService _auth;

  DropboxService(this._auth);

  static const _apiUrl = 'https://api.dropboxapi.com/2';
  static const _contentUrl = 'https://content.dropboxapi.com/2';
  static const _audioExtensions = [
    'mp3', 'm4a', 'flac', 'wav', 'ogg', 'aac', 'wma'
  ];

  Future<List<CloudFile>> listAudioFiles() async {
    final headers = await _auth.getDropboxAuthHeaders();
    if (headers.isEmpty) return [];

    final allFiles = <CloudFile>[];
    String? cursor;
    bool hasMore = true;

    // Initial search
    var response = await http.post(
      Uri.parse('$_apiUrl/files/search_v2'),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'query': ' ',
        'options': {
          'file_extensions': _audioExtensions,
          'file_status': {'tag': 'active'},
          'max_results': 100,
        },
      }),
    );

    if (response.statusCode != 200) return [];

    while (hasMore) {
      final data = json.decode(response.body);
      final matches = data['matches'] as List? ?? [];

      for (final match in matches) {
        final metadata = match['metadata']?['metadata'];
        if (metadata == null) continue;
        final tag = metadata['.tag'];
        if (tag != 'file') continue;

        final pathLower = metadata['path_lower'] as String? ?? '';
        final name = metadata['name'] as String? ?? '';
        final size = metadata['size'] as int? ?? 0;
        final parentPath = pathLower.substring(0, pathLower.lastIndexOf('/'));

        allFiles.add(CloudFile(
          provider: CloudProvider.dropbox,
          fileId: pathLower,
          name: name,
          folderPath: parentPath.isEmpty ? '/' : parentPath,
          size: size,
          mimeType: _mimeFromExtension(name),
          modifiedDate: metadata['server_modified'] != null
              ? DateTime.tryParse(metadata['server_modified'] as String)
              : null,
        ));
      }

      hasMore = data['has_more'] as bool? ?? false;
      cursor = data['cursor'] as String?;

      if (hasMore && cursor != null) {
        response = await http.post(
          Uri.parse('$_apiUrl/files/search/continue_v2'),
          headers: {
            ...headers,
            'Content-Type': 'application/json',
          },
          body: json.encode({'cursor': cursor}),
        );
        if (response.statusCode != 200) break;
      }
    }

    return allFiles;
  }

  Future<String?> getTemporaryLink(String path) async {
    final headers = await _auth.getDropboxAuthHeaders();
    if (headers.isEmpty) return null;

    final response = await http.post(
      Uri.parse('$_apiUrl/files/get_temporary_link'),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: json.encode({'path': path}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['link'] as String?;
    }
    return null;
  }

  Future<String?> getThumbnail(String path) async {
    final headers = await _auth.getDropboxAuthHeaders();
    if (headers.isEmpty) return null;

    final response = await http.post(
      Uri.parse('$_contentUrl/files/get_thumbnail_v2'),
      headers: {
        ...headers,
        'Dropbox-API-Arg': json.encode({
          'resource': {'.tag': 'path', 'path': path},
          'format': {'.tag': 'png'},
          'size': {'.tag': 'w256h256'},
        }),
      },
    );

    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      // Return as data URI for simplicity
      final base64Data = base64Encode(response.bodyBytes);
      return 'data:image/png;base64,$base64Data';
    }
    return null;
  }

  String _mimeFromExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'aac' => 'audio/aac',
      'wma' => 'audio/x-ms-wma',
      _ => 'audio/mpeg',
    };
  }
}
