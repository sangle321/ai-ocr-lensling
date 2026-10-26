import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../services/engines.dart';
import 'result_view.dart';
import 'packs_screen.dart';
import 'translation_credit.dart';

const ink = Color(0xff172e2b);
const teal = Color(0xff146b5c);
const paper = Color(0xfff7f8f4);

class LenslingApp extends StatelessWidget {
  const LenslingApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lensling',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: paper,
        onSurface: ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xffe2e8df)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xffdceee3),
      ),
    ),
    home: HomeScreen(controller: controller),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  static const _share = MethodChannel('app.lensling/import');
  int _tab = 0;
  bool _picking = false;
  bool _checkingShare = false;
  bool _wasBusy = false;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onControllerChanged);
    unawaited(_start());
    _share.setMethodCallHandler((call) async {
      if (call.method == 'imageAvailable') {
        await _checkShared();
      }
    });
  }

  void _onControllerChanged() {
    final becameIdle = _wasBusy && !c.busy;
    _wasBusy = c.busy;
    if (becameIdle) {
      unawaited(_checkShared());
    }
  }

  Future<void> _start() async {
    await c.initialize();
    if (!mounted) {
      return;
    }
    if (Platform.isAndroid && c.engineReady) {
      try {
        final lost = await _picker.retrieveLostData();
        if (lost.files?.isNotEmpty ?? false) {
          await c.scan(lost.files!.first.path);
          await _removePickerCopy(lost.files!.first.path);
        }
        if (lost.exception != null) {
          _showError(
            'The previous photo could not be recovered. Please choose it again.',
          );
        }
      } catch (e) {
        _showError(readableError(e));
      }
    }
    await _checkShared();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkShared());
    }
  }

  Future<void> _checkShared() async {
    if (!mounted || _checkingShare || c.busy || !c.engineReady || _picking) {
      return;
    }
    _checkingShare = true;
    String? path;
    try {
      path = await _share.invokeMethod<String>('takeImage');
      if (path != null && mounted) {
        setState(() => _tab = 0);
        await c.scan(path);
      }
    } on MissingPluginException {
      /* Tests and unsupported hosts. */
    } catch (e) {
      _showError(readableError(e));
    } finally {
      _checkingShare = false;
      if (path != null) {
        try {
          await _share.invokeMethod<void>('releaseImage', {'path': path});
        } catch (_) {
          /* Temporary imports are also cleared by the OS. */
        }
        unawaited(_checkShared());
      }
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking || c.busy) {
      return;
    }
    setState(() => _picking = true);
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      if (image != null && mounted) {
        await c.scan(image.path);
        await _removePickerCopy(image.path);
      }
    } catch (e) {
      _showError(readableError(e));
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
      unawaited(_checkShared());
    }
  }

  Future<void> _removePickerCopy(String path) async {
    try {
      final cache = await (await getTemporaryDirectory())
          .resolveSymbolicLinks();
      final image = File(path);
      final resolved = await image.resolveSymbolicLinks();
      // Delete only app-owned temporary copies, never a gallery original.
      if (resolved.startsWith('$cache${Platform.pathSeparator}')) {
        await image.delete();
      }
    } on FileSystemException {
      /* OS cache cleanup can have already removed it. */
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onControllerChanged);
    _share.setMethodCallHandler(null);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.document_scanner_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'lensling',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Language packs',
            onPressed: !c.initialized || c.busy
                ? null
                : () => openPacks(context, c),
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (c.busy) ...[
              const LinearProgressIndicator(minHeight: 3),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  c.progress,
                  style: const TextStyle(color: teal),
                  semanticsLabel: c.progress,
                ),
              ),
            ],
            if (c.error != null)
              _ErrorBanner(
                message: c.error!,
                onClose: c.dismissError,
                onRetry: c.initialized ? null : () => c.initialize(),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (_tab) {
                  1 => _History(
                    c: c,
                    onOpen: (doc) {
                      c.open(doc);
                      setState(() => _tab = 0);
                    },
                  ),
                  2 => _Settings(c: c),
                  _ => _scanPage(),
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Scan',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    ),
  );

  Widget _scanPage() => ListView(
    key: const ValueKey('scan'),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    children: [
      LanguageBar(c: c),
      const SizedBox(height: 24),
      if (c.current == null) ...[
        const Text(
          'A new way to\nread the world.',
          style: TextStyle(
            fontSize: 36,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Point. Capture. Understand.\nTranslate text in photos, right on your device.',
          style: TextStyle(fontSize: 16, height: 1.6, color: Color(0xff5e716b)),
        ),
        const SizedBox(height: 28),
      ] else ...[
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your scan',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: c.busy ? null : c.clearCurrent,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New scan'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ResultView(c: c),
        const SizedBox(height: 24),
      ],
      FilledButton.icon(
        onPressed: !c.engineReady || c.busy || _picking
            ? null
            : () => _pick(ImageSource.camera),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Take a photo', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: !c.engineReady || c.busy || _picking
            ? null
            : () => _pick(ImageSource.gallery),
        icon: const Icon(Icons.photo_library_outlined),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        label: const Text('Import from photos'),
      ),
      const SizedBox(height: 18),
      if (c.engineError != null)
        _ErrorBanner(message: c.engineError!, onRetry: c.retryEngine)
      else if (!c.engineReady)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Preparing the on-device reader…',
              style: TextStyle(color: teal),
            ),
          ),
        )
      else
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 14, color: teal),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Your photos and text stay on this device.',
                style: TextStyle(fontSize: 12, color: Color(0xff5e716b)),
              ),
            ),
          ],
        ),
      if (c.current == null) ...[
        const SizedBox(height: 28),
        const _CaptureIllustration(),
      ],
    ],
  );
}

class _CaptureIllustration extends StatelessWidget {
  const _CaptureIllustration();
  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: Container(
      height: 232,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xffe7eee5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -20,
            top: -35,
            child: Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                color: Color(0xffd3e3cf),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Transform.rotate(
            angle: -.07,
            child: Container(
              width: 218,
              height: 184,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xfffffcf3),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x150d3024),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'こんにちは',
                    style: TextStyle(color: Color(0xff78857b), fontSize: 19),
                  ),
                  SizedBox(height: 14),
                  Divider(color: Color(0xffd7ded1)),
                  SizedBox(height: 8),
                  Text(
                    'Hello, world.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: teal,
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'A little closer, in any language.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 24,
            top: 24,
            child: Icon(Icons.crop_free, color: teal, size: 34),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.offline_bolt_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'ON-DEVICE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class LanguageBar extends StatelessWidget {
  const LanguageBar({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) {
    final source = c.current?.source ?? c.settings.source;
    final target = c.current?.target ?? c.settings.target;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: _LanguageButton(
                label: 'FROM',
                value: source == 'auto'
                    ? 'Detect language'
                    : languageName(source),
                onTap: c.busy || !c.initialized
                    ? null
                    : () async {
                        final code = await pickLanguage(
                          context,
                          c.availableLanguages,
                          allowAuto: true,
                        );
                        if (code != null) {
                          await c.changePair(source: code, target: target);
                        }
                      },
              ),
            ),
            IconButton(
              tooltip: 'Swap languages',
              onPressed: c.busy || source == 'auto'
                  ? null
                  : () => c.changePair(source: target, target: source),
              icon: const Icon(Icons.swap_horiz, color: teal),
            ),
            Expanded(
              child: _LanguageButton(
                label: 'TO',
                value: languageName(target),
                onTap: c.busy || !c.initialized
                    ? null
                    : () async {
                        final code = await pickLanguage(
                          context,
                          c.availableLanguages,
                        );
                        if (code != null) {
                          await c.changePair(target: code, source: source);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.label, required this.value, this.onTap});
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.3,
              color: Color(0xff697b71),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<String?> pickLanguage(
  BuildContext context,
  List<AppLanguage> options, {
  bool allowAuto = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Choose a language',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (allowAuto)
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('Detect language'),
                    onTap: () => Navigator.pop(context, 'auto'),
                  ),
                for (final language in options)
                  ListTile(
                    title: Text(language.name),
                    subtitle: Text(language.nativeName),
                    trailing: Text(
                      language.code.toUpperCase(),
                      style: const TextStyle(color: teal),
                    ),
                    onTap: () => Navigator.pop(context, language.code),
                  ),
                if (options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No translation languages are available on this device.',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

class _History extends StatelessWidget {
  const _History({required this.c, required this.onOpen});
  final AppController c;
  final ValueChanged<ScanDocument> onOpen;
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('history'),
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Your discoveries.',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${c.history.length} scans · Stored only on this device',
        style: const TextStyle(color: Color(0xff697b71)),
      ),
      const SizedBox(height: 24),
      if (c.history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Column(
            children: [
              Icon(Icons.history, size: 54, color: teal),
              SizedBox(height: 18),
              Text(
                'A world of words awaits.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('Your saved scans will appear here.'),
            ],
          ),
        ),
      for (final doc in c.history)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(c.store.imagePath(doc.id)),
                  width: 56,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 56,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              title: Text(
                doc.isTranslated ? doc.translatedText : doc.originalText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${languageName(doc.source)} → ${languageName(doc.target)}\n${formatDate(doc.createdAt)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              onTap: c.busy ? null : () => onOpen(doc),
              trailing: IconButton(
                tooltip: 'Delete scan',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: c.busy
                    ? null
                    : () async {
                        if (await confirmDelete(context, all: false)) {
                          await c.delete(doc.id);
                        }
                      },
              ),
            ),
          ),
        ),
    ],
  );
}

String formatDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Settings extends StatefulWidget {
  const _Settings({required this.c});
  final AppController c;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  AppController get c => widget.c;
  double? _confidence;
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('settings'),
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Make it yours.',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(
                Icons.download_for_offline_outlined,
                color: teal,
              ),
              title: const Text('Language packs'),
              subtitle: const Text('Prepare for your next adventure'),
              trailing: const Icon(Icons.chevron_right),
              onTap: !c.initialized || c.busy
                  ? null
                  : () => openPacks(context, c),
            ),
            SwitchListTile(
              title: const Text('Download over Wi-Fi only'),
              subtitle: Text(
                Platform.isIOS
                    ? 'Apple manages downloads through its system prompt.'
                    : 'Language packs are about 30 MB each.',
              ),
              value: c.settings.wifiOnly,
              onChanged: c.busy || !c.initialized || Platform.isIOS
                  ? null
                  : (value) =>
                        c.updateSettings(c.settings.copyWith(wifiOnly: value)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.document_scanner_outlined, color: teal),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Text recognition',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('PP-OCRv6 · Small · Bundled'),
              const SizedBox(height: 6),
              const Text(
                'Ready offline. Recognition quality varies by language and photo.',
                style: TextStyle(color: Color(0xff697b71), height: 1.5),
              ),
              const SizedBox(height: 18),
              Text(
                'Confidence filter: ${((_confidence ?? c.settings.confidence) * 100).round()}%',
              ),
              Slider(
                value: _confidence ?? c.settings.confidence,
                min: .1,
                max: .95,
                divisions: 17,
                label:
                    '${((_confidence ?? c.settings.confidence) * 100).round()}%',
                onChanged: c.busy || !c.initialized
                    ? null
                    : (value) => setState(() => _confidence = value),
                onChangeEnd: (value) async {
                  await c.updateSettings(
                    c.settings.copyWith(confidence: value),
                  );
                  if (mounted) {
                    setState(() => _confidence = null);
                  }
                },
              ),
              const Text(
                'Applies to new scans. Lower it to keep less certain text.',
                style: TextStyle(fontSize: 12, color: Color(0xff697b71)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, color: teal),
              const SizedBox(height: 12),
              const Text(
                'Private by design',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Photos, recognized text and translations stay on this device. '
                'Cloud translation is unavailable in this version. Language pack downloads need internet.',
                style: TextStyle(height: 1.6, color: Color(0xff697b71)),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: c.busy || c.history.isEmpty
                    ? null
                    : () async {
                        if (await confirmDelete(context, all: true)) {
                          await c.deleteAll();
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete all scan history'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const TranslationCredit(),
      Center(
        child: TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Lensling',
            applicationVersion: '1.0.0',
            applicationLegalese:
                'OCR: PaddleOCR PP-OCRv6 and paddle_ocr_native (Apache-2.0).',
          ),
          child: const Text('Open-source licenses'),
        ),
      ),
    ],
  );
}

Future<bool> confirmDelete(BuildContext context, {required bool all}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(all ? 'Delete all scans?' : 'Delete this scan?'),
        content: const Text(
          'The saved photo and text will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onClose, this.onRetry});
  final String message;
  final VoidCallback? onClose, onRetry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xffffefdb),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20, color: Color(0xff8a551d)),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(height: 1.5))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    ),
  );
}
