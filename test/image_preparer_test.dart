import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lensling/services/image_preparer.dart';
import 'package:lensling/services/engines.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lensling-image-');
  });
  tearDown(() => temp.delete(recursive: true));
  test('downscales large photos and retains aspect ratio', () async {
    final image = img.Image(width: 3000, height: 1200);
    final file = await File(
      '${temp.path}/input.png',
    ).writeAsBytes(img.encodePng(image));
    final result = await LocalImagePreparer().prepare(
      file.path,
      '${temp.path}/out.jpg',
    );
    expect(result.width, 2400);
    expect(result.height, 960);
    expect(img.decodeJpg(await File(result.path).readAsBytes()), isNotNull);
  });
  test('rejects invalid image data with a useful recovery message', () async {
    final file = await File(
      '${temp.path}/input.jpg',
    ).writeAsBytes([0, 1, 2, 3]);
    await expectLater(
      LocalImagePreparer().prepare(file.path, '${temp.path}/out.jpg'),
      throwsA(isA<AppFailure>()),
    );
  });
}
