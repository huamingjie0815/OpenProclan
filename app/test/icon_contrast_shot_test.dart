import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proclan_app/feed_client.dart';
import 'package:proclan_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFeed implements FeedClient {
  @override
  Future<List<String>> categories() async => const [];

  @override
  Future<void> deleteCard(String id) async {}

  @override
  Future<List<FeedCard>> feed() async => const [];

  @override
  Map<String, String> imageHeadersFor(String url) => const {};
}

Future<({int minLum, int maxLum, int dark, int light})> _iconLuma(
  WidgetTester tester,
) async {
  final button = tester.renderObject(find.byKey(const Key('open-menu')));
  var boundary = button;
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final rect = MatrixUtils.transformRect(
    button.getTransformTo(boundary),
    button.paintBounds,
  );
  final future = (boundary.debugLayer! as OffsetLayer).toImage(
    rect,
    pixelRatio: 2,
  );
  final bytes = await tester.runAsync(() async {
    final image = await future;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  var minLum = 255;
  var maxLum = 0;
  var dark = 0;
  var light = 0;
  final pixels = bytes!;
  for (var i = 0; i < pixels.length; i += 4) {
    final lum = (pixels[i] + pixels[i + 1] + pixels[i + 2]) ~/ 3;
    if (lum < minLum) {
      minLum = lum;
    }
    if (lum > maxLum) {
      maxLum = lum;
    }
    if (lum < 80) {
      dark++;
    }
    if (lum > 210) {
      light++;
    }
  }
  return (minLum: minLum, maxLum: maxLum, dark: dark, light: light);
}

void main() {
  testWidgets('menu icon repaints when the theme changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProclanApp(
        client: _FakeFeed(),
        pollEvery: null,
        locales: LocaleController(prefs),
        themes: ThemeController(prefs),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final dark = await _iconLuma(tester);
    expect(dark.light, greaterThan(40), reason: 'dark mode stroke');
    expect(dark.maxLum, greaterThan(220));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final light = await _iconLuma(tester);
    expect(light.dark, greaterThan(40), reason: 'light mode stroke');
    expect(light.minLum, lessThan(50));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final again = await _iconLuma(tester);
    expect(again.light, greaterThan(40), reason: 'stroke returns to light');
    expect(again.maxLum, greaterThan(220));
  });
}
