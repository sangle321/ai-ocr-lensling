import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lensling/app_controller.dart';
import 'package:lensling/ui/app.dart';
import 'fakes.dart';

void main() {
  testWidgets('capture remains accessible with large text on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = AppController(
      ocr: FakeOcr(),
      translator: FakeTranslator(),
      store: FakeStore(),
      images: FakeImages(),
    );
    await tester.pumpWidget(LenslingApp(controller: c));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Take a photo'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('home, history and settings are usable on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(
      ocr: FakeOcr(),
      translator: FakeTranslator(),
      store: FakeStore(),
      images: FakeImages(),
    );
    await tester.pumpWidget(LenslingApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('A new way to\nread the world.'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('A world of words awaits.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Make it yours.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('language-packs route shows real installation state', (
    tester,
  ) async {
    final c = AppController(
      ocr: FakeOcr(),
      translator: FakeTranslator(),
      store: FakeStore(),
      images: FakeImages(),
    );
    await tester.pumpWidget(LenslingApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Language packs'));
    await tester.pumpAndSettle();
    expect(find.text('Ready for offline translation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
