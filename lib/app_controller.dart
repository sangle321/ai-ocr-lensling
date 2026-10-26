import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'domain/models.dart';
import 'domain/paragraphs.dart';
import 'services/engines.dart';
import 'services/image_preparer.dart';
import 'services/local_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.ocr,
    required this.translator,
    required this.store,
    required this.images,
  });
  final OcrEngine ocr;
  final Translator translator;
  final ScanStore store;
  final ImagePreparer images;
  AppSettings settings = const AppSettings();
  List<ScanDocument> history = [];
  List<AppLanguage> availableLanguages = [];
  ScanDocument? current;
  bool initialized = false;
  bool engineReady = false;
  bool busy = false;
  String progress = '';
  String? error;
  String? engineError;
  bool _disposed = false;
  Future<void>? _starting;

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> initialize() => _starting ??= _initialize();
  Future<void> _initialize() async {
    try {
      await store.initialize();
      settings = await store.readSettings();
      history = await store.loadHistory();
      final codes = await translator.supportedLanguages();
      availableLanguages = languages
          .where((l) => codes.contains(l.code))
          .toList();
      if (availableLanguages.isNotEmpty &&
          !availableLanguages.any((l) => l.code == settings.target)) {
        settings = settings.copyWith(target: availableLanguages.first.code);
      }
      if (settings.source != 'auto' &&
          !availableLanguages.any((l) => l.code == settings.source)) {
        settings = settings.copyWith(source: 'auto');
      }
      initialized = true;
      notifyListeners();
      await retryEngine();
    } catch (e) {
      error = readableError(e);
      _starting = null;
      notifyListeners();
    }
  }

  Future<void> retryEngine() async {
    engineError = null;
    notifyListeners();
    try {
      await ocr.initialize();
      engineReady = true;
    } catch (e) {
      engineReady = false;
      engineError =
          'The OCR engine could not start. Check free storage and retry.';
    }
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    if (busy) {
      return;
    }
    await _run('Saving preferences…', () async {
      await store.writeSettings(next);
      settings = next;
    });
  }

  Future<void> changePair({required String source, required String target}) =>
      _run('Updating languages…', () async {
        final next = settings.copyWith(source: source, target: target);
        await store.writeSettings(next);
        settings = next;
        final doc = current;
        if (doc == null) {
          return;
        }
        final resolved = source == 'auto'
            ? await translator.identify(doc.originalText)
            : source;
        final actual =
            resolved != null &&
                availableLanguages.any((l) => l.code == resolved)
            ? resolved
            : 'auto';
        if (doc.source != actual || doc.target != target) {
          await _persist(
            doc.copyWith(
              source: actual,
              target: target,
              regions: doc.regions.map((r) => r.withText(r.text)).toList(),
              clearTranslation: true,
            ),
          );
        }
        if (actual == 'auto') {
          throw const AppFailure(
            'The source language is uncertain. Select it manually.',
          );
        }
      });

  Future<void> scan(String path) async {
    if (busy || !initialized || !engineReady) {
      return;
    }
    await _run('Preparing your photo…', () async {
      final tempPath = await store.temporaryImagePath();
      try {
        final image = await images.prepare(path, tempPath);
        progress = 'Reading text on your device…';
        notifyListeners();
        final result = await ocr.recognize(image.path);
        var paragraphs = groupParagraphs(
          result.regions,
          minConfidence: settings.confidence,
        );
        if (paragraphs.isEmpty) {
          throw const AppFailure(
            'No clear text found. Try better lighting, move closer, or lower the confidence filter in Settings.',
          );
        }
        paragraphs = await images.sampleBackgrounds(image.path, paragraphs);
        final document = ScanDocument(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}',
          createdAt: DateTime.now(),
          width: image.width,
          height: image.height,
          regions: paragraphs,
          source: settings.source,
          target: settings.target,
          ocrMs: result.elapsedMs,
        );
        await store.save(document, image: image.path);
        current = document;
        _replaceHistory(document);
        // OCR is durable even when identification or translation fails.
        if (settings.source == 'auto') {
          final code = await translator.identify(document.originalText);
          if (code == null || !availableLanguages.any((l) => l.code == code)) {
            throw const AppFailure(
              'Text saved. The source language is uncertain or unsupported. Select the source language and translate again.',
            );
          }
          await _persist(document.copyWith(source: code));
        }
        await _translateCurrent();
      } finally {
        final file = File(tempPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    });
  }

  Future<void> translate() =>
      _run('Checking language packs…', _translateCurrent);
  Future<void> _translateCurrent() async {
    final doc = current;
    if (doc == null) {
      return;
    }
    if (doc.source == 'auto') {
      throw const AppFailure('Select a source language before translating.');
    }
    final status = await translator.pairStatus(doc.source, doc.target);
    if (status == PairStatus.unsupported) {
      throw const AppFailure(
        'This language pair is unavailable on this device. Your recognized text is saved.',
      );
    }
    if (status != PairStatus.installed) {
      throw const AppFailure(
        'Text saved. Open Language packs to download this pair, then tap Translate again.',
      );
    }
    progress = 'Translating on your device…';
    notifyListeners();
    final watch = Stopwatch()..start();
    final translated = await translator.translate(
      doc.regions.map((r) => r.text).toList(),
      doc.source,
      doc.target,
    );
    if (translated.length != doc.regions.length ||
        translated.any((s) => s.trim().isEmpty)) {
      throw const AppFailure(
        'Translation was incomplete. Your original text is saved; try again.',
      );
    }
    await _persist(
      doc.copyWith(
        regions: [
          for (var i = 0; i < translated.length; i++)
            doc.regions[i].translated(translated[i]),
        ],
        translationMs: watch.elapsedMilliseconds,
      ),
    );
  }

  Future<void> editRegion(int index, String text) async {
    if (current == null || text.trim().isEmpty) {
      return;
    }
    await _run('Saving correction…', () async {
      final doc = current!;
      final regions = doc.regions.map((r) => r.withText(r.text)).toList();
      regions[index] = regions[index].withText(text.trim());
      await _persist(doc.copyWith(regions: regions, clearTranslation: true));
    });
  }

  Future<void> downloadPair(String source, String target) => _run(
    'Downloading language packs…',
    () => translator.downloadPair(source, target, wifiOnly: settings.wifiOnly),
  );
  Future<void> deleteLanguage(String code) =>
      _run('Removing language pack…', () => translator.deleteLanguage(code));

  void open(ScanDocument doc) {
    if (busy) {
      return;
    }
    current = doc;
    error = null;
    notifyListeners();
  }

  void clearCurrent() {
    if (busy) {
      return;
    }
    current = null;
    error = null;
    notifyListeners();
  }

  Future<void> delete(String id) => _run('Deleting scan…', () async {
    await store.delete(id);
    history.removeWhere((d) => d.id == id);
    if (current?.id == id) {
      current = null;
    }
  });
  Future<void> deleteAll() => _run('Deleting history…', () async {
    await store.deleteAll();
    history = [];
    current = null;
  });
  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<void> _persist(ScanDocument doc) async {
    await store.save(doc);
    current = doc;
    _replaceHistory(doc);
  }

  void _replaceHistory(ScanDocument doc) {
    history = [doc, ...history.where((d) => d.id != doc.id)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (busy) {
      return;
    }
    busy = true;
    error = null;
    progress = label;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = readableError(e);
    } finally {
      busy = false;
      progress = '';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Native OCR serializes disposal behind any in-flight recognition.
    ocr.dispose();
    translator.dispose();
    super.dispose();
  }
}
