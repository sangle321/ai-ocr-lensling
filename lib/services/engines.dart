import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import '../domain/models.dart';

class OcrOutput {
  const OcrOutput(this.regions, this.elapsedMs);
  final List<TextRegion> regions;
  final double elapsedMs;
}

abstract interface class OcrEngine {
  Future<void> initialize();
  Future<OcrOutput> recognize(String path);
  Future<void> dispose();
}

class PaddleEngine implements OcrEngine {
  final PaddleOcr _engine = PaddleOcr();
  @override
  Future<void> initialize() async {
    await _engine.init(
      config: const PaddleOcrConfig(recScoreThresh: 0),
      engine: const EngineConfig(numThreads: 4),
    );
    final folder = await getTemporaryDirectory();
    final file = File('${folder.path}/lensling-warmup.png');
    final blank = img.Image(width: 320, height: 128);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      blank,
      'HELLO',
      font: img.arial48,
      x: 20,
      y: 32,
      color: img.ColorRgb8(0, 0, 0),
    );
    try {
      await file.writeAsBytes(img.encodePng(blank));
      await _engine.recognize(file.path);
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<OcrOutput> recognize(String path) async {
    final result = await _engine.recognize(path);
    return OcrOutput(
      result.results
          .map(
            (r) => TextRegion(
              text: r.text,
              points: r.points
                  .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
                  .toList(),
              confidence: r.confidence,
            ),
          )
          .toList(),
      result.totalTimeMs.toDouble(),
    );
  }

  @override
  Future<void> dispose() => _engine.dispose();
}

enum PairStatus { installed, downloadable, unsupported }

abstract interface class Translator {
  Future<List<String>> supportedLanguages();
  Future<String?> identify(String text);
  Future<PairStatus> pairStatus(String source, String target);
  Future<void> downloadPair(
    String source,
    String target, {
    required bool wifiOnly,
  });
  Future<List<String>> translate(
    List<String> texts,
    String source,
    String target,
  );
  Future<void> deleteLanguage(String language);
  Future<void> dispose();
}

class NativeTranslator implements Translator {
  static const _channel = MethodChannel('app.lensling/translation');
  @override
  Future<List<String>> supportedLanguages() async =>
      await _channel.invokeListMethod<String>('supportedLanguages') ?? [];
  @override
  Future<String?> identify(String text) =>
      _channel.invokeMethod<String>('identify', {'text': text});
  @override
  Future<PairStatus> pairStatus(String source, String target) async {
    if (source == target) {
      return PairStatus.installed;
    }
    final status = await _channel.invokeMethod<String>('pairStatus', {
      'source': source,
      'target': target,
    });
    return switch (status) {
      'installed' => PairStatus.installed,
      'downloadable' => PairStatus.downloadable,
      _ => PairStatus.unsupported,
    };
  }

  @override
  Future<void> downloadPair(
    String source,
    String target, {
    required bool wifiOnly,
  }) => _channel.invokeMethod<void>('downloadPair', {
    'source': source,
    'target': target,
    'wifiOnly': wifiOnly,
  });
  @override
  Future<List<String>> translate(
    List<String> texts,
    String source,
    String target,
  ) async {
    if (source == target) {
      return List.of(texts);
    }
    return await _channel.invokeListMethod<String>('translate', {
          'texts': texts,
          'source': source,
          'target': target,
        }) ??
        [];
  }

  @override
  Future<void> deleteLanguage(String language) =>
      _channel.invokeMethod<void>('deleteLanguage', {'language': language});
  @override
  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String readableError(Object error) {
  if (error is AppFailure) {
    return error.message;
  }
  if (error is PlatformException) {
    return error.message ??
        'The device could not complete this operation. Try again.';
  }
  if (error is PaddleOcrException) {
    return 'OCR could not finish. Try a smaller, clearer JPEG or PNG photo.';
  }
  return 'Could not complete this operation. Check device storage and try again.';
}
