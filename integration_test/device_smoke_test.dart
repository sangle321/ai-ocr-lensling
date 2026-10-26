import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lensling/services/engines.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled OCR recognizes a local image without network', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Device OCR smoke test'))),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1000, 280),
      Paint()..color = Colors.white,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: 'HELLO WORLD',
        style: TextStyle(
          color: Colors.black,
          fontSize: 90,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(60, 80));
    final image = await recorder.endRecording().toImage(1000, 280);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${(await getTemporaryDirectory()).path}/ocr-smoke.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    final engine = PaddleEngine();
    try {
      await engine.initialize();
      final result = await engine.recognize(file.path);
      expect(
        result.regions.map((r) => r.text).join(' ').toUpperCase(),
        contains('HELLO'),
      );
      expect(result.regions.every((r) => r.points.length == 4), isTrue);
    } finally {
      await engine.dispose();
      await file.delete();
      image.dispose();
      text.dispose();
    }
  });
}
