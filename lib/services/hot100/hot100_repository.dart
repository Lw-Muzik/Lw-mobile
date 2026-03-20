import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import 'hot100_failure.dart';
import 'hot100_model.dart';

abstract class Hot100Repository {
  Future<Either<Hot100Failure, List<Hot100Song>>> fetchChart();
}

class Hot100RepositoryImpl implements Hot100Repository {
  final Dio _dio;

  Hot100RepositoryImpl({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        ));

  @override
  Future<Either<Hot100Failure, List<Hot100Song>>> fetchChart() async {
    try {
      final response = await _dio.get('/get/hot100');

      if (response.statusCode != 200) {
        return Left(ServerFailure(
          'Server returned ${response.statusCode}',
        ));
      }

      final data = response.data;
      if (data is! Map || !data.containsKey('songs')) {
        return const Left(ParseFailure('Invalid response format'));
      }

      final songs = (data['songs'] as List)
          .map((e) => Hot100Song.fromJson(e as Map<String, dynamic>))
          .where((s) => s.title.isNotEmpty && s.url.isNotEmpty)
          .toList();

      return Right(songs);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return const Left(NetworkFailure('Connection timed out'));
      }
      if (e.type == DioExceptionType.connectionError) {
        return const Left(NetworkFailure('No internet connection'));
      }
      return Left(NetworkFailure(e.message ?? 'Network error'));
    } catch (e) {
      debugPrint('Hot100Repository error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }
}
