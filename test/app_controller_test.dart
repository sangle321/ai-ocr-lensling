import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lensling/app_controller.dart';
import 'package:lensling/services/engines.dart';
import 'fakes.dart';

void main() {
  late FakeOcr ocr;
  late FakeTranslator translator;
  late FakeStore store;
  late AppController c;
  setUp(() async {
    ocr = FakeOcr();
    translator = FakeTranslator();
    store = FakeStore();
    c = AppController(
      ocr: ocr,
      translator: translator,
      store: store,
      images: FakeImages(),
    );
    await c.initialize();
  });
  tearDown(() => c.dispose());

  test('recognizes, detects, translates and durably saves one scan', () async {
    await c.scan('input.jpg');
    expect(c.current!.source, 'en');
    expect(c.current!.isTranslated, isTrue);
    expect(c.current!.translatedText, contains('Xin chào'));
    expect(store.docs.values.single.isTranslated, isTrue);
    expect(c.error, isNull);
    expect(c.busy, isFalse);
  });
  test(
    'missing packs preserve OCR and explicit download enables retry',
    () async {
      translator.status = PairStatus.downloadable;
      await c.scan('input.jpg');
      expect(c.current!.originalText, 'Hello world');
      expect(store.docs.values.single.originalText, 'Hello world');
      expect(c.error, contains('Language packs'));
      expect(translator.calls, 0);
      await c.downloadPair('en', 'vi');
      await c.translate();
      expect(c.current!.isTranslated, isTrue);
      expect(c.history, hasLength(1));
    },
  );
  test('failed translation preserves recognized text across restart', () async {
    translator.fail = true;
    await c.scan('input.jpg');
    final reloaded = AppController(
      ocr: FakeOcr(),
      translator: FakeTranslator(),
      store: store,
      images: FakeImages(),
    );
    await reloaded.initialize();
    expect(reloaded.history.single.originalText, 'Hello world');
    expect(reloaded.history.single.isTranslated, isFalse);
    reloaded.dispose();
  });
  test('uncertain identification never silently defaults to English', () async {
    translator.detected = null;
    await c.scan('input.jpg');
    expect(c.current!.source, 'auto');
    expect(c.error, contains('uncertain'));
    expect(translator.calls, 0);
    await c.changePair(source: 'en', target: 'vi');
    await c.translate();
    expect(c.current!.isTranslated, isTrue);
  });
  test('unsupported scripts leave original accessible', () async {
    translator.detected = 'ar';
    await c.scan('input.jpg');
    expect(c.current!.originalText, isNotEmpty);
    expect(translator.calls, 0);
  });
  test('incomplete batch never corrupts saved OCR', () async {
    translator.incomplete = true;
    await c.scan('input.jpg');
    expect(c.error, contains('incomplete'));
    expect(c.current!.isTranslated, isFalse);
    expect(store.docs.values.single.originalText, 'Hello world');
  });
  test(
    'editing invalidates translation and timing until retranslation',
    () async {
      await c.scan('input.jpg');
      await c.editRegion(0, 'Hello corrected world');
      expect(c.current!.translationMs, isNull);
      expect(c.current!.isTranslated, isFalse);
      expect(c.current!.originalText, 'Hello corrected world');
      await c.translate();
      expect(c.current!.translatedText, contains('corrected'));
    },
  );
  test('target change clears old-language results', () async {
    await c.scan('input.jpg');
    await c.changePair(source: 'en', target: 'fr');
    expect(c.current!.target, 'fr');
    expect(c.current!.isTranslated, isFalse);
    expect(store.docs.values.single.translationMs, isNull);
  });
  test('auto language can be rerun after a correction', () async {
    await c.scan('input.jpg');
    translator.detected = 'fr';
    await c.changePair(source: 'auto', target: 'vi');
    expect(c.current!.source, 'fr');
    expect(c.current!.isTranslated, isFalse);
  });
  test(
    'confidence preference does not change a reopened scan language',
    () async {
      await c.scan('input.jpg');
      await c.changePair(source: 'en', target: 'fr');
      c.settings = c.settings.copyWith(target: 'vi');
      await c.updateSettings(c.settings.copyWith(confidence: .7));
      expect(c.current!.target, 'fr');
    },
  );
  test('empty OCR does not replace previous scan', () async {
    await c.scan('input.jpg');
    final id = c.current!.id;
    ocr.lines = [];
    await c.scan('blank.jpg');
    expect(c.current!.id, id);
    expect(c.history, hasLength(1));
    expect(c.error, contains('No clear text'));
  });
  test('rapid captures cannot run overlapping native OCR', () async {
    ocr.pending = Completer<void>();
    final first = c.scan('first.jpg');
    await Future<void>.delayed(Duration.zero);
    await c.scan('second.jpg');
    expect(ocr.calls, 1);
    ocr.pending!.complete();
    await first;
    expect(c.history, hasLength(1));
  });
  test('delete-all removes current result as well as history', () async {
    await c.scan('input.jpg');
    await c.deleteAll();
    expect(c.current, isNull);
    expect(c.history, isEmpty);
    expect(store.docs, isEmpty);
  });
}
