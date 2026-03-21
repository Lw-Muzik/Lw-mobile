import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../hot100/hot100_failure.dart';
import 'music_models.dart';

abstract class MusicRepository {
  Future<Either<Hot100Failure, List<MusicSong>>> fetchPopular({int offset = 0});
  Future<Either<Hot100Failure, List<MusicArtist>>> fetchArtists({int? page});
  Future<Either<Hot100Failure, List<MusicSong>>> search(String query);
  Future<Either<Hot100Failure, MusicSongDetail>> fetchSongDetail(String id);
  Future<Either<Hot100Failure, MusicArtistDetail>> fetchArtistDetail(
      String slug, String id);
  Future<Either<Hot100Failure, List<MusicSong>>> fetchArtistSongs(String id,
      {String sort = 'popular'});
}

class MusicRepositoryImpl implements MusicRepository {
  final Dio _dio;

  MusicRepositoryImpl({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json'},
            ));

  @override
  Future<Either<Hot100Failure, List<MusicSong>>> fetchPopular(
      {int offset = 0}) async {
    try {
      final response =
          await _dio.get('/api/v1/music/popular', queryParameters: {
        if (offset > 0) 'offset': offset,
      });
      return Right(_parseSongList(response.data));
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  @override
  Future<Either<Hot100Failure, List<MusicArtist>>> fetchArtists({int? page}) async {
    try {
      final response = await _dio.get('/api/v1/music/artists', queryParameters: {
        if (page != null) 'page': page,
      });
      final data = response.data;
      if (data is! Map || !data.containsKey('artists')) {
        return const Left(ParseFailure('Invalid response format'));
      }
      final artists = (data['artists'] as List)
          .map((e) => MusicArtist.fromJson(e as Map<String, dynamic>))
          .where((a) => a.name.isNotEmpty && a.name != 'nodata')
          .toList();
      return Right(artists);
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  @override
  Future<Either<Hot100Failure, List<MusicSong>>> search(String query) async {
    try {
      final response = await _dio
          .get('/api/v1/music/search', queryParameters: {'q': query});
      return Right(_parseSongList(response.data));
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  @override
  Future<Either<Hot100Failure, MusicSongDetail>> fetchSongDetail(
      String id) async {
    try {
      final response = await _dio.get('/api/v1/music/song/$id');
      return Right(MusicSongDetail.fromJson(response.data));
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  @override
  Future<Either<Hot100Failure, MusicArtistDetail>> fetchArtistDetail(
      String slug, String id) async {
    try {
      final response = await _dio.get('/api/v1/music/artist/$slug/$id');
      return Right(MusicArtistDetail.fromJson(response.data));
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  @override
  Future<Either<Hot100Failure, List<MusicSong>>> fetchArtistSongs(String id,
      {String sort = 'popular'}) async {
    try {
      final response = await _dio
          .get('/api/v1/music/artist/$id/songs', queryParameters: {
        'sort': sort,
      });
      final data = response.data;
      if (data is List) {
        return Right(data
            .map((e) => MusicSong.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return Right(_parseSongList(data));
    } catch (e) {
      return Left(_handleError(e));
    }
  }

  List<MusicSong> _parseSongList(dynamic data) {
    if (data is! Map || !data.containsKey('songs')) return [];
    return (data['songs'] as List)
        .map((e) => MusicSong.fromJson(e as Map<String, dynamic>))
        .where((s) => s.title.isNotEmpty)
        .toList();
  }

  Hot100Failure _handleError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return const NetworkFailure('Connection timed out');
      }
      if (e.type == DioExceptionType.connectionError) {
        return const NetworkFailure('No internet connection');
      }
      return NetworkFailure(e.message ?? 'Network error');
    }
    debugPrint('MusicRepository error: $e');
    return ServerFailure(e.toString());
  }
}
