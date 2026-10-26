import 'dart:math' as math;
import 'dart:ui';
import 'models.dart';

/// Groups nearby horizontal lines without crossing column gutters. Rotated
/// regions retain their polygons and are shown separately below the image.
List<TextRegion> groupParagraphs(
  List<TextRegion> input, {
  double minConfidence = .5,
}) {
  final lines =
      input
          .where(
            (r) =>
                r.text.trim().isNotEmpty &&
                r.confidence >= minConfidence &&
                r.points.length == 4 &&
                r.points.every((p) => p.dx.isFinite && p.dy.isFinite) &&
                r.bounds.width > 0 &&
                r.bounds.height > 0,
          )
          .toList()
        ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
  final groups = <List<TextRegion>>[];
  for (final line in lines) {
    List<TextRegion>? best;
    double bestGap = double.infinity;
    for (final group in groups) {
      final previous = group.last;
      if (!line.canOverlay ||
          !previous.canOverlay ||
          line.angle.abs() > .06 ||
          previous.angle.abs() > .06) {
        continue;
      }
      final a = previous.bounds, b = line.bounds;
      final gap = b.top - a.bottom;
      final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
      final sameColumn =
          overlap > math.min(a.width, b.width) * .65 &&
          (a.left - b.left).abs() < math.max(a.height, b.height) * 1.5;
      final similarHeight =
          math.max(a.height, b.height) / math.min(a.height, b.height) < 1.65;
      if (sameColumn &&
          similarHeight &&
          gap >= -a.height * .15 &&
          gap < a.height * .85 &&
          gap < bestGap) {
        best = group;
        bestGap = gap;
      }
    }
    if (best == null) {
      groups.add([line]);
    } else {
      best.add(line);
    }
  }
  final output = groups.map((g) {
    if (g.length == 1) {
      return g.single;
    }
    final box = g.map((r) => r.bounds).reduce((a, b) => a.expandToInclude(b));
    return TextRegion(
      text: g.map((r) => r.text).join(' '),
      points: [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft],
      confidence: g.map((r) => r.confidence).reduce((a, b) => a + b) / g.length,
      background: g.first.background,
    );
  }).toList();
  // Connected horizontal spans form columns. A stable total ordering avoids
  // comparator cycles when a heading spans several columns.
  output.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  final columns = <List<TextRegion>>[];
  double right = double.negativeInfinity;
  for (final region in output) {
    if (columns.isEmpty || region.bounds.left >= right) {
      columns.add([region]);
      right = region.bounds.right;
    } else {
      columns.last.add(region);
      right = math.max(right, region.bounds.right);
    }
  }
  return columns
      .expand(
        (column) => column
          ..sort((a, b) {
            final top = a.bounds.top.compareTo(b.bounds.top);
            return top == 0 ? a.bounds.left.compareTo(b.bounds.left) : top;
          }),
      )
      .toList();
}

List<Offset> rectanglePoints(Rect r) => [
  r.topLeft,
  r.topRight,
  r.bottomRight,
  r.bottomLeft,
];
