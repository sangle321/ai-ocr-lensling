import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lensling/domain/models.dart';
import 'package:lensling/services/local_store.dart';
import 'fakes.dart';

void main() {
  late Directory temp;
  late LocalScanStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lensling-test-');
    store = LocalScanStore(directory: Directory('${temp.path}/data'));
    await store.initialize();
  });
  tearDown(() => temp.delete(recursive: true));
  test('photo and edited metadata survive a new store instance', () async {
    final input = await File('${temp.path}/input.jpg').writeAsBytes([1, 2, 3]);
    final doc = document();
    await store.save(doc, image: input.path);
    await store.save(
      doc.copyWith(regions: [doc.regions.single.translated('Xin chào')]),
    );
    final other = LocalScanStore(directory: store.root);
    await other.initialize();
    final loaded = (await other.loadHistory()).single;
    expect(loaded.translatedText, 'Xin chào');
    expect(await File(other.imagePath(doc.id)).readAsBytes(), [1, 2, 3]);
  });
  test('damaged entries do not hide valid history', () async {
    final input = await File('${temp.path}/input.jpg').writeAsBytes([1]);
    await store.save(document(), image: input.path);
    await Directory('${store.root.path}/scans/broken').create();
    await File(
      '${store.root.path}/scans/broken/scan.json',
    ).writeAsString('{broken');
    expect(await store.loadHistory(), hasLength(1));
  });
  test('rejects path traversal in saved scan identifiers', () {
    expect(() => store.imagePath('../outside'), throwsFormatException);
  });
  test(
    'damaged preferences fall back without preventing app startup',
    () async {
      await File('${store.root.path}/settings.json').writeAsString('broken');
      expect((await store.readSettings()).source, 'auto');
    },
  );
  test('delete-all deletes photos and metadata but retains settings', () async {
    await store.writeSettings(const AppSettings(target: 'fr'));
    final input = await File('${temp.path}/input.jpg').writeAsBytes([1]);
    await store.save(document(), image: input.path);
    final path = store.imagePath('scan1');
    await store.deleteAll();
    expect(await File(path).exists(), isFalse);
    expect(await store.loadHistory(), isEmpty);
    expect((await store.readSettings()).target, 'fr');
  });
}
