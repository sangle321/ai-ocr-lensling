import 'dart:async';
import 'dart:ui';
import 'package:lensling/domain/models.dart';
import 'package:lensling/services/engines.dart';
import 'package:lensling/services/image_preparer.dart';
import 'package:lensling/services/local_store.dart';

TextRegion line(
  String text, {
  double x = 10,
  double y = 10,
  double width = 180,
  double height = 20,
  double confidence = .95,
}) => TextRegion(
  text: text,
  confidence: confidence,
  points: [
    Offset(x, y),
    Offset(x + width, y),
    Offset(x + width, y + height),
    Offset(x, y + height),
  ],
);

ScanDocument document({String id = 'scan1'}) => ScanDocument(
  id: id,
  createdAt: DateTime(2026, 10, 26, 12),
  width: 300,
  height: 400,
  regions: [line('Hello world')],
  source: 'en',
  target: 'vi',
  ocrMs: 123,
);

class FakeOcr implements OcrEngine {
  List<TextRegion> lines = [line('Hello world')];
  Completer<void>? pending;
  int calls = 0;
  bool fail = false;
  @override
  Future<void> initialize() async {
    if (fail) {
      throw Exception('engine');
    }
  }

  @override
  Future<OcrOutput> recognize(String path) async {
    calls++;
    await pending?.future;
    return OcrOutput(lines, 123);
  }

  @override
  Future<void> dispose() async {}
}

class FakeTranslator implements Translator {
  PairStatus status = PairStatus.installed;
  String? detected = 'en';
  bool fail = false;
  bool incomplete = false;
  int calls = 0;
  @override
  Future<List<String>> supportedLanguages() async => ['en', 'vi', 'fr', 'ja'];
  @override
  Future<String?> identify(String text) async => detected;
  @override
  Future<PairStatus> pairStatus(String source, String target) async => status;
  @override
  Future<void> downloadPair(
    String source,
    String target, {
    required bool wifiOnly,
  }) async {
    status = PairStatus.installed;
  }

  @override
  Future<List<String>> translate(
    List<String> texts,
    String source,
    String target,
  ) async {
    calls++;
    if (fail) {
      throw const AppFailure('Translation failed. Your text is saved.');
    }
    if (incomplete) {
      return [];
    }
    return texts.map((text) => 'Xin chào: $text').toList();
  }

  @override
  Future<void> deleteLanguage(String language) async {
    status = PairStatus.downloadable;
  }

  @override
  Future<void> dispose() async {}
}

class FakeStore implements ScanStore {
  final docs = <String, ScanDocument>{};
  AppSettings settings = const AppSettings();
  @override
  Future<void> initialize() async {}
  @override
  Future<AppSettings> readSettings() async => settings;
  @override
  Future<void> writeSettings(AppSettings value) async {
    settings = value;
  }

  @override
  Future<List<ScanDocument>> loadHistory() async => docs.values.toList();
  @override
  String imagePath(String id) => 'unused-$id.jpg';
  @override
  Future<String> temporaryImagePath() async => 'unused-temp.jpg';
  @override
  Future<void> save(ScanDocument document, {String? image}) async {
    docs[document.id] = document;
  }

  @override
  Future<void> delete(String id) async {
    docs.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    docs.clear();
  }
}

class FakeImages implements ImagePreparer {
  @override
  Future<PreparedImage> prepare(String input, String output) async =>
      PreparedImage(output, 300, 400);
  @override
  Future<List<TextRegion>> sampleBackgrounds(
    String path,
    List<TextRegion> regions,
  ) async => regions;
}
