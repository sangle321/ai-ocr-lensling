import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'services/engines.dart';
import 'services/image_preparer.dart';
import 'services/local_store.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    LenslingApp(
      controller: AppController(
        ocr: PaddleEngine(),
        translator: NativeTranslator(),
        store: LocalScanStore(),
        images: LocalImagePreparer(),
      ),
    ),
  );
}
