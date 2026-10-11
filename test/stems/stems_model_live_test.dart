/// The real model hosts, through the real HTTP client: one 19.7 MB file is
/// fetched, our host first and Hugging Face after it, and verified against the
/// embedded fingerprint.
///
/// Skipped by default — it depends on two servers nobody here controls. Ask
/// for it by name, e.g. after uploading the files to our host:
///
///     flutter test --run-skipped --tags live test/stems/stems_model_live_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/stems/stems_manifest.dart';
import 'package:eq_app/services/stems/stems_model_store.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('stems_live_test');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('vocals.onnx downloads and verifies from the listed hosts', () async {
    const real = StemsModelManifest.spleeter4StemsFp16;
    final vocals = real.files.first;
    final store = StemsModelStore(
      manifest: StemsModelManifest(
        id: real.id,
        version: real.version,
        totalBytes: vocals.size,
        files: [vocals],
      ),
      baseDirectory: () async => base,
    );

    await store.download();

    expect(await store.isReady(), isTrue);
    final file = File('${(await store.directory()).path}/${vocals.name}');
    expect(await file.length(), vocals.size);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
