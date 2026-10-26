import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:lensling/domain/models.dart';
import 'package:lensling/domain/paragraphs.dart';
import 'fakes.dart';

void main() {
  test('merges neighboring lines into sentences in reading order', () {
    final result = groupParagraphs([
      line('second line', y: 35),
      line('First line'),
    ]);
    expect(result.single.text, 'First line second line');
    expect(result.single.bounds, const Rect.fromLTWH(10, 10, 180, 45));
  });
  test('keeps separated columns in column order', () {
    final result = groupParagraphs([
      line('Right', x: 260),
      line('Left', y: 50),
    ]);
    expect(result.map((r) => r.text), ['Left', 'Right']);
  });
  test('filters empty, low-confidence and malformed regions', () {
    final result = groupParagraphs([
      line(''),
      line('noise', confidence: .2),
      const TextRegion(text: 'broken', points: [], confidence: 1),
      line('valid'),
    ]);
    expect(result.single.text, 'valid');
  });
  test('rotated regions retain original geometry and avoid overlays', () {
    const rotated = TextRegion(
      text: 'vertical',
      confidence: 1,
      points: [Offset(10, 10), Offset(10, 80), Offset(30, 80), Offset(30, 10)],
    );
    final result = groupParagraphs([rotated]);
    expect(result.single.canOverlay, isFalse);
    expect(result.single.points, rotated.points);
  });
  test('heading and body are not merged when font sizes differ', () {
    final result = groupParagraphs([
      line('Heading', height: 45),
      line('Body', y: 60),
    ]);
    expect(result, hasLength(2));
  });
}
