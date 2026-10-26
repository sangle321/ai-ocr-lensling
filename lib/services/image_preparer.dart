import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../domain/models.dart';
import 'engines.dart';

class PreparedImage {
  const PreparedImage(this.path, this.width, this.height);
  final String path;
  final int width;
  final int height;
}

abstract interface class ImagePreparer {
  Future<PreparedImage> prepare(String input, String output);
  Future<List<TextRegion>> sampleBackgrounds(
    String path,
    List<TextRegion> regions,
  );
}

class LocalImagePreparer implements ImagePreparer {
  @override
  Future<PreparedImage> prepare(String input, String output) =>
      compute(_prepare, (input, output));
  @override
  Future<List<TextRegion>> sampleBackgrounds(
    String path,
    List<TextRegion> regions,
  ) => compute(_sample, (path, regions));
}

PreparedImage _prepare((String, String) paths) {
  final file = File(paths.$1);
  if (file.lengthSync() > 40 * 1024 * 1024) {
    throw const AppFailure('Choose a photo smaller than 40 MB.');
  }
  final bytes = file.readAsBytesSync();
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) {
    throw const AppFailure(
      'This image format is not supported. Choose a JPEG, PNG or WebP photo.',
    );
  }
  if (info.width * info.height > 40000000) {
    throw const AppFailure(
      'This photo is too large to process safely. Choose a photo under 40 megapixels.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const AppFailure('The photo could not be opened.');
  }
  var image = img.bakeOrientation(decoded);
  final longest = math.max(image.width, image.height);
  if (longest > 2400) {
    image = img.copyResize(
      image,
      width: (image.width * 2400 / longest).round(),
      height: (image.height * 2400 / longest).round(),
      interpolation: img.Interpolation.average,
    );
  }
  // Strip location and other EXIF metadata from retained photos.
  image.exif.clear();
  File(paths.$2).writeAsBytesSync(img.encodeJpg(image, quality: 92));
  return PreparedImage(paths.$2, image.width, image.height);
}

List<TextRegion> _sample((String, List<TextRegion>) request) {
  final image = img.decodeJpg(File(request.$1).readAsBytesSync());
  if (image == null) {
    return request.$2;
  }
  return request.$2.map((r) {
    final b = r.bounds;
    final samples = <img.Pixel>[];
    for (var i = 0; i < 12; i++) {
      final x = (b.left + b.width * i / 11).round().clamp(0, image.width - 1);
      for (final y in [b.top - 3, b.bottom + 3]) {
        samples.add(image.getPixel(x, y.round().clamp(0, image.height - 1)));
      }
    }
    int median(num Function(img.Pixel) channel) {
      final values = samples.map((p) => channel(p).toInt()).toList()..sort();
      return values[values.length ~/ 2];
    }

    return TextRegion(
      text: r.text,
      points: r.points,
      confidence: r.confidence,
      background:
          0xff000000 |
          median((p) => p.r) << 16 |
          median((p) => p.g) << 8 |
          median((p) => p.b),
    );
  }).toList();
}
