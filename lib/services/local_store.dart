import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

abstract interface class ScanStore {
  Future<void> initialize();
  Future<AppSettings> readSettings();
  Future<void> writeSettings(AppSettings settings);
  Future<List<ScanDocument>> loadHistory();
  String imagePath(String id);
  Future<String> temporaryImagePath();
  Future<void> save(ScanDocument document, {String? image});
  Future<void> delete(String id);
  Future<void> deleteAll();
}

class LocalScanStore implements ScanStore {
  LocalScanStore({Directory? directory}) : _root = directory;
  Directory? _root;
  Directory get root => _root!;
  Directory _scan(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid scan identifier');
    }
    return Directory('${root.path}/scans/$id');
  }

  @override
  Future<void> initialize() async {
    _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/lensling',
    );
    await Directory('${root.path}/scans').create(recursive: true);
    // Incomplete writes never become history entries; clear abandoned temp data.
    final temp = Directory('${root.path}/temp');
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
    await temp.create();
  }

  @override
  Future<AppSettings> readSettings() async {
    final file = File('${root.path}/settings.json');
    if (!await file.exists()) {
      return const AppSettings();
    }
    try {
      return AppSettings.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      return const AppSettings();
    } on TypeError {
      return const AppSettings();
    }
  }

  @override
  Future<void> writeSettings(AppSettings settings) =>
      _atomicJson(File('${root.path}/settings.json'), settings.toJson());
  @override
  Future<List<ScanDocument>> loadHistory() async {
    final results = <ScanDocument>[];
    await for (final entry in Directory('${root.path}/scans').list()) {
      if (entry is! Directory) {
        continue;
      }
      final file = File('${entry.path}/scan.json');
      if (!await file.exists()) {
        continue;
      }
      // A damaged entry must not prevent access to all other saved scans.
      try {
        final document = ScanDocument.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
        if (document.width <= 0 ||
            document.height <= 0 ||
            document.regions.isEmpty ||
            document.regions.any(
              (r) =>
                  r.points.length != 4 ||
                  !r.confidence.isFinite ||
                  r.points.any((p) => !p.dx.isFinite || !p.dy.isFinite),
            )) {
          continue;
        }
        if (await File(imagePath(document.id)).exists() &&
            await FileSystemEntity.identical(
              _scan(document.id).path,
              entry.path,
            )) {
          results.add(document);
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on RangeError {
        continue;
      }
    }
    return results..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  String imagePath(String id) => '${_scan(id).path}/photo.jpg';
  @override
  Future<String> temporaryImagePath() async =>
      '${root.path}/temp/${DateTime.now().microsecondsSinceEpoch}.jpg';
  @override
  Future<void> save(ScanDocument document, {String? image}) async {
    final dir = _scan(document.id);
    await dir.create(recursive: true);
    if (image != null) {
      await File(image).copy(imagePath(document.id));
    }
    await _atomicJson(File('${dir.path}/scan.json'), document.toJson());
  }

  @override
  Future<void> delete(String id) async {
    final directory = _scan(id);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> deleteAll() async {
    final scans = Directory('${root.path}/scans');
    if (await scans.exists()) {
      await scans.delete(recursive: true);
    }
    await scans.create(recursive: true);
  }

  Future<void> _atomicJson(File destination, Map<String, dynamic> value) async {
    final temp = File('${destination.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    // On supported mobile filesystems rename replaces a file atomically.
    await temp.rename(destination.path);
  }
}
