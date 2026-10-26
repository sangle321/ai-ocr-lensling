import 'dart:io';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain/models.dart';
import '../services/engines.dart';
import 'app.dart';

Future<void> openPacks(BuildContext context, AppController controller) =>
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PacksScreen(c: controller)));

class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key, required this.c});
  final AppController c;
  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  late String _source;
  late String _target;
  late Future<PairStatus> _status;
  @override
  void initState() {
    super.initState();
    final c = widget.c;
    _source = c.current?.source ?? c.settings.source;
    if (_source == 'auto') {
      _source = 'en';
    }
    _target = c.current?.target ?? c.settings.target;
    _refresh();
  }

  void _refresh() {
    _status = widget.c.translator.pairStatus(_source, _target);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final c = widget.c;
      return Scaffold(
        appBar: AppBar(title: const Text('Language packs')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.travel_explore, size: 56, color: teal),
            const SizedBox(height: 24),
            const Text(
              'Ready before you go.',
              style: TextStyle(
                fontSize: 30,
                letterSpacing: -.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              Platform.isIOS
                  ? 'Apple will ask to download the languages you need. Once installed, translation works offline. '
                        'Apple manages pack sizes and removal in system settings.'
                  : 'Download both languages while you have a connection. Each pack is about 30 MB; English is used '
                        'as a bridge between other languages. Photos and text are never uploaded.',
              style: const TextStyle(height: 1.6, color: Color(0xff697b71)),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Source language'),
                    subtitle: Text(languageName(_source)),
                    trailing: const Icon(Icons.expand_more),
                    onTap: c.busy
                        ? null
                        : () async {
                            final code = await pickLanguage(
                              context,
                              c.availableLanguages,
                            );
                            if (code != null && mounted) {
                              setState(() {
                                _source = code;
                                _refresh();
                              });
                            }
                          },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('Target language'),
                    subtitle: Text(languageName(_target)),
                    trailing: const Icon(Icons.expand_more),
                    onTap: c.busy
                        ? null
                        : () async {
                            final code = await pickLanguage(
                              context,
                              c.availableLanguages,
                            );
                            if (code != null && mounted) {
                              setState(() {
                                _target = code;
                                _refresh();
                              });
                            }
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FutureBuilder<PairStatus>(
              future: _status,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('Could not check packs on this device.'),
                      TextButton(
                        onPressed: () => setState(_refresh),
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final installed = snapshot.data == PairStatus.installed;
                final unsupported = snapshot.data == PairStatus.unsupported;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          installed
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          color: teal,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            installed
                                ? 'Ready for offline translation'
                                : unsupported
                                ? 'This pair is unavailable on your device'
                                : 'Download needed',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!installed && !unsupported)
                      FilledButton.icon(
                        onPressed: c.busy
                            ? null
                            : () async {
                                await c.downloadPair(_source, _target);
                                if (mounted) {
                                  setState(_refresh);
                                }
                              },
                        icon: const Icon(Icons.download),
                        label: Text(
                          c.busy ? 'Downloading…' : 'Download language pair',
                        ),
                      ),
                    if (installed && _source != _target && Platform.isAndroid)
                      TextButton.icon(
                        onPressed: c.busy
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      'Remove ${languageName(_target)}?',
                                    ),
                                    content: const Text(
                                      'Pairs using this language will need a new download. Your scans stay saved.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Keep'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await c.deleteLanguage(_target);
                                  if (mounted) {
                                    setState(_refresh);
                                  }
                                }
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove target pack'),
                      ),
                  ],
                );
              },
            ),
            if (c.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: LinearProgressIndicator(),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  c.error!,
                  style: const TextStyle(color: Color(0xff8a551d), height: 1.5),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              Platform.isIOS
                  ? 'A download can show a system confirmation. Keep this screen open until it finishes.'
                  : c.settings.wifiOnly
                  ? 'Wi-Fi only is on. A download may wait until you connect to Wi-Fi.'
                  : 'Downloads may use mobile data. Change this in Settings.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xff697b71),
              ),
            ),
          ],
        ),
      );
    },
  );
}
