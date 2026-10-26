import 'dart:math' as math;
import 'dart:ui';

class AppLanguage {
  const AppLanguage(this.code, this.name, this.nativeName);
  final String code;
  final String name;
  final String nativeName;
}

// Deliberately conservative OCR/translation intersection. Device availability
// further filters this list; recognition quality still needs a golden corpus.
const languages = [
  AppLanguage('en', 'English', 'English'),
  AppLanguage('vi', 'Vietnamese', 'Tiếng Việt'),
  AppLanguage('zh', 'Chinese', '中文'),
  AppLanguage('ja', 'Japanese', '日本語'),
  AppLanguage('fr', 'French', 'Français'),
  AppLanguage('de', 'German', 'Deutsch'),
  AppLanguage('es', 'Spanish', 'Español'),
  AppLanguage('it', 'Italian', 'Italiano'),
  AppLanguage('pt', 'Portuguese', 'Português'),
  AppLanguage('id', 'Indonesian', 'Bahasa Indonesia'),
  AppLanguage('nl', 'Dutch', 'Nederlands'),
  AppLanguage('pl', 'Polish', 'Polski'),
  AppLanguage('tr', 'Turkish', 'Türkçe'),
];

String languageName(String code) => languages
    .firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage(code, code, code),
    )
    .name;

class TextRegion {
  const TextRegion({
    required this.text,
    required this.points,
    required this.confidence,
    this.translation,
    this.background = 0xfff7f6f0,
  });
  final String text;
  final List<Offset> points;
  final double confidence;
  final String? translation;
  final int background;
  Rect get bounds => Rect.fromLTRB(
    points.map((p) => p.dx).reduce(math.min),
    points.map((p) => p.dy).reduce(math.min),
    points.map((p) => p.dx).reduce(math.max),
    points.map((p) => p.dy).reduce(math.max),
  );
  double get angle =>
      math.atan2(points[1].dy - points[0].dy, points[1].dx - points[0].dx);
  bool get canOverlay =>
      angle.abs() < math.pi / 9 && bounds.width > bounds.height * .65;

  TextRegion withText(String value) => TextRegion(
    text: value,
    points: points,
    confidence: confidence,
    background: background,
  );
  TextRegion translated(String value) => TextRegion(
    text: text,
    points: points,
    confidence: confidence,
    background: background,
    translation: value,
  );
  Map<String, dynamic> toJson() => {
    'text': text,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'confidence': confidence,
    'translation': translation,
    'background': background,
  };
  factory TextRegion.fromJson(Map<String, dynamic> json) => TextRegion(
    text: json['text'] as String,
    points: (json['points'] as List)
        .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList(),
    confidence: (json['confidence'] as num).toDouble(),
    translation: json['translation'] as String?,
    background: json['background'] as int,
  );
}

class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.createdAt,
    required this.width,
    required this.height,
    required this.regions,
    required this.source,
    required this.target,
    required this.ocrMs,
    this.translationMs,
  });
  final String id;
  final DateTime createdAt;
  final int width;
  final int height;
  final List<TextRegion> regions;
  final String source;
  final String target;
  final double ocrMs;
  final int? translationMs;
  String get originalText => regions.map((r) => r.text).join('\n\n');
  String get translatedText => regions
      .map((r) => r.translation ?? '')
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  bool get isTranslated =>
      regions.isNotEmpty && regions.every((r) => r.translation != null);
  ScanDocument copyWith({
    List<TextRegion>? regions,
    String? source,
    String? target,
    int? translationMs,
    bool clearTranslation = false,
  }) => ScanDocument(
    id: id,
    createdAt: createdAt,
    width: width,
    height: height,
    regions: regions ?? this.regions,
    source: source ?? this.source,
    target: target ?? this.target,
    ocrMs: ocrMs,
    translationMs: clearTranslation
        ? null
        : translationMs ?? this.translationMs,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'width': width,
    'height': height,
    'regions': regions.map((r) => r.toJson()).toList(),
    'source': source,
    'target': target,
    'ocrMs': ocrMs,
    'translationMs': translationMs,
  };
  factory ScanDocument.fromJson(Map<String, dynamic> json) => ScanDocument(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    width: json['width'] as int,
    height: json['height'] as int,
    regions: (json['regions'] as List)
        .map((r) => TextRegion.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    source: json['source'] as String,
    target: json['target'] as String,
    ocrMs: (json['ocrMs'] as num).toDouble(),
    translationMs: json['translationMs'] as int?,
  );
}

class AppSettings {
  const AppSettings({
    this.source = 'auto',
    this.target = 'vi',
    this.wifiOnly = true,
    this.confidence = .5,
  });
  final String source;
  final String target;
  final bool wifiOnly;
  final double confidence;
  AppSettings copyWith({
    String? source,
    String? target,
    bool? wifiOnly,
    double? confidence,
  }) => AppSettings(
    source: source ?? this.source,
    target: target ?? this.target,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    confidence: confidence ?? this.confidence,
  );
  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'wifiOnly': wifiOnly,
    'confidence': confidence,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    source: json['source'] as String? ?? 'auto',
    target: json['target'] as String? ?? 'vi',
    wifiOnly: json['wifiOnly'] as bool? ?? true,
    confidence: ((json['confidence'] as num?)?.toDouble() ?? .5).clamp(.1, .95),
  );
}
