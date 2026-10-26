import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TranslationCredit extends StatelessWidget {
  const TranslationCredit({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Text(
        'Translation powered by Apple',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Color(0xff697b71)),
      );
    }
    return Center(
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Automatic translations'),
            content: const SingleChildScrollView(
              child: Text(
                'THIS SERVICE MAY CONTAIN TRANSLATIONS POWERED BY GOOGLE. GOOGLE DISCLAIMS ALL WARRANTIES '
                'RELATED TO THE TRANSLATIONS, EXPRESS OR IMPLIED, INCLUDING ANY WARRANTIES OF ACCURACY, '
                'RELIABILITY, AND ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR '
                'PURPOSE AND NONINFRINGEMENT.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await const MethodChannel(
                      'app.lensling/import',
                    ).invokeMethod<void>('translationInfo');
                  } on PlatformException {
                    /* A browser may not be installed. */
                  }
                },
                child: const Text('About Google Translate'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(
            'assets/branding/google_translate.png',
            width: 176,
            semanticLabel:
                'Powered by Google Translate. View translation information.',
          ),
        ),
      ),
    );
  }
}
