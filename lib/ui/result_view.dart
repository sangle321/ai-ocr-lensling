import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import 'app.dart';
import 'translation_credit.dart';

class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.c});
  final AppController c;
  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _translated = true;
  @override
  Widget build(BuildContext context) {
    final c = widget.c, doc = widget.c.current!;
    final showTranslation = _translated && doc.isTranslated;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Scanned photo. Tap to switch original and translated text.',
          button: true,
          child: GestureDetector(
            onTap: doc.isTranslated
                ? () => setState(() => _translated = !_translated)
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: doc.width / doc.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(c.store.imagePath(doc.id)),
                      fit: BoxFit.fill,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (showTranslation)
                      CustomPaint(painter: TranslationPainter(doc)),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          showTranslation ? 'TRANSLATED' : 'ORIGINAL',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: teal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (doc.isTranslated)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Original')),
                  ButtonSegment(value: true, label: Text('Translation')),
                ],
                selected: {_translated},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _translated = value.single),
              ),
            Text(
              '${doc.regions.length} paragraphs · OCR ${(doc.ocrMs / 1000).toStringAsFixed(2)}s',
              style: const TextStyle(fontSize: 11, color: Color(0xff697b71)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: c.busy ? null : c.translate,
                icon: const Icon(Icons.translate, size: 20),
                label: Text(
                  Platform.isAndroid
                      ? 'Translate with Google'
                      : doc.isTranslated
                      ? 'Translate again'
                      : 'Translate',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Copy all text',
              onPressed: () => _copy(
                context,
                showTranslation ? doc.translatedText : doc.originalText,
              ),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const TranslationCredit(),
        if (doc.regions.any((r) => !r.canOverlay))
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'Rotated and vertical text appears in the list below.',
              style: TextStyle(fontSize: 12, color: Color(0xff697b71)),
            ),
          ),
        const SizedBox(height: 20),
        for (var i = 0; i < doc.regions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'PARAGRAPH ${i + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: teal,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${(doc.regions[i].confidence * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xff697b71),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit recognized text',
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            minWidth: 36,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: c.busy
                              ? null
                              : () => _edit(context, c, i, doc.regions[i].text),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                        ),
                      ],
                    ),
                    SelectableText(
                      showTranslation
                          ? doc.regions[i].translation!
                          : doc.regions[i].text,
                      style: const TextStyle(fontSize: 16, height: 1.6),
                    ),
                    if (showTranslation)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          doc.regions[i].text,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xff697b71),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    AppController c,
    int index,
    String value,
  ) async {
    final input = TextEditingController(text: value);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct the recognized text'),
        content: TextField(
          controller: input,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Enter the text in the photo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Wait until the closing route has stopped using the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (edited != null && edited.trim().isNotEmpty) {
      await c.editRegion(index, edited);
      if (mounted) {
        setState(() => _translated = false);
      }
    }
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Text copied')));
    }
  }
}

class TranslationPainter extends CustomPainter {
  TranslationPainter(this.document);
  final ScanDocument document;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / document.width, size.height / document.height);
    for (final region in document.regions) {
      if (!region.canOverlay || region.translation == null) {
        continue;
      }
      final origin = region.points.first;
      final width = (region.points[1] - origin).distance;
      final height = (region.points[3] - origin).distance;
      if (width < 3 || height < 3) {
        continue;
      }
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(region.angle);
      final rect = Rect.fromLTWH(0, 0, width, height);
      canvas.clipRect(rect);
      final background = Color(region.background);
      canvas.drawRect(rect, Paint()..color = background);
      final color = background.computeLuminance() > .4
          ? const Color(0xff142b26)
          : Colors.white;
      final padding = math.min(3.0, math.min(width, height) * .06);
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      double low = 1, high = math.min(80, height);
      for (var attempt = 0; attempt < 12; attempt++) {
        final fontSize = (low + high) / 2;
        painter.text = TextSpan(
          text: region.translation,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.15,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        );
        painter.layout(maxWidth: width - padding * 2);
        if (painter.height > height - padding * 2 ||
            painter.didExceedMaxLines) {
          high = fontSize;
        } else {
          low = fontSize;
        }
      }
      painter.text = TextSpan(
        text: region.translation,
        style: TextStyle(
          fontSize: low,
          height: 1.15,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      );
      painter.layout(maxWidth: width - padding * 2);
      painter.paint(canvas, Offset(padding, (height - painter.height) / 2));
      painter.dispose();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TranslationPainter oldDelegate) =>
      oldDelegate.document != document;
}
