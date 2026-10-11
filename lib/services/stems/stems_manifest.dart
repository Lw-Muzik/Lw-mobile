/// The separation model the Stems tab downloads on first use.
///
/// Embedded rather than fetched: a manifest that can change under an installed
/// app is a way to make it run files nobody reviewed. The fingerprints below
/// are what every downloaded byte is checked against before the native engine
/// is allowed to load it.
///
/// Deezer's Spleeter 4-stem weights (MIT, per the authors' JOSS paper),
/// converted to ONNX at fp16 by Best-Practice / sherpa-onnx (Apache-2.0).
library;

import 'package:flutter/foundation.dart';

@immutable
class StemsModelFile {
  /// The name the file is saved under — what the native loader opens.
  final String name;

  /// Exact size in bytes.
  final int size;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;

  /// Where to fetch it, tried in order: our own host first, Hugging Face as
  /// the fallback.
  final List<String> urls;

  const StemsModelFile({
    required this.name,
    required this.size,
    required this.sha256,
    required this.urls,
  });
}

@immutable
class StemsModelManifest {
  final String id;
  final int version;
  final int totalBytes;
  final List<StemsModelFile> files;

  const StemsModelManifest({
    required this.id,
    required this.version,
    required this.totalBytes,
    required this.files,
  });

  /// The folder a model version lives in, so two versions never share files.
  String get directoryName => '$id-v$version';

  /// Identifies this exact model for facts remembered about it — the device
  /// speed test is only valid for the model it was run on.
  String get key => '$id.v$version';

  static const spleeter4StemsFp16 = StemsModelManifest(
    id: 'spleeter-4stems-fp16',
    version: 1,
    totalBytes: 78856560,
    files: [
      StemsModelFile(
        name: 'vocals.onnx',
        size: 19714141,
        sha256:
            'db47148ab1c52709ce694893f532c91abfe3edc4d46238939570e036a22878ca',
        urls: [
          'https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/vocals.onnx',
          'https://huggingface.co/Best-Practice/spleeter-4stems-onnx/resolve/main/vocals.fp16.onnx',
        ],
      ),
      StemsModelFile(
        name: 'drums.onnx',
        size: 19714140,
        sha256:
            '7ae4002e5633634674f74dc3356d5875b0da894d59ce0f60e844bb8f9cb8aa92',
        urls: [
          'https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/drums.onnx',
          'https://huggingface.co/Best-Practice/spleeter-4stems-onnx/resolve/main/drums.fp16.onnx',
        ],
      ),
      StemsModelFile(
        name: 'bass.onnx',
        size: 19714139,
        sha256:
            'ba4c4949a27222492cca49859901a873b4b71461dc48c7c5a51f93d31eb11f55',
        urls: [
          'https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/bass.onnx',
          'https://huggingface.co/Best-Practice/spleeter-4stems-onnx/resolve/main/bass.fp16.onnx',
        ],
      ),
      StemsModelFile(
        name: 'other.onnx',
        size: 19714140,
        sha256:
            '3cc59116cb7195946ab9596d8ca25984d09c0f8a70db8cf85d063132f97bc61d',
        urls: [
          'https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/other.onnx',
          'https://huggingface.co/Best-Practice/spleeter-4stems-onnx/resolve/main/other.fp16.onnx',
        ],
      ),
    ],
  );
}
