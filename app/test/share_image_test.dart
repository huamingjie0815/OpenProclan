import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proclan_app/share_image.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('shareImagePixelRatio', () {
    test('keeps short cards at 2x', () {
      expect(shareImagePixelRatio(300), 2);
      expect(shareImagePixelRatio(1500), 2);
    });

    test('lowers the ratio as the card grows', () {
      expect(shareImagePixelRatio(3000), 1);
      expect(shareImagePixelRatio(6000), closeTo(0.5, 1e-9));
      expect(shareImagePixelRatio(24000), closeTo(0.5, 1e-9));
    });

    test('falls back to 2x without a usable height', () {
      expect(shareImagePixelRatio(0), 2);
      expect(shareImagePixelRatio(-10), 2);
      expect(shareImagePixelRatio(double.nan), 2);
      expect(shareImagePixelRatio(double.infinity), 2);
    });
  });

  group('shareImageFileName', () {
    test('keeps safe characters and always ends in .png', () {
      expect(shareImageFileName('0f8c2b9e-1d3a'), 'proclan-0f8c2b9e-1d3a.png');
    });

    test('strips path separators and spaces', () {
      expect(shareImageFileName('../../etc/passwd'), 'proclan-etcpasswd.png');
    });

    test('falls back for an empty id', () {
      expect(shareImageFileName(''), 'proclan-card.png');
      expect(shareImageFileName('///'), 'proclan-card.png');
    });
  });

  testWidgets('captures a repaint boundary as a png', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: const SizedBox(
              width: 60,
              height: 40,
              child: ColoredBox(color: Color(0xFFCC0000)),
            ),
          ),
        ),
      ),
    );

    final bytes = await tester.runAsync(() => captureBoundaryPng(key));
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 8), _pngMagic);
    expect(bytes.length, greaterThan(100));
  });

  testWidgets('returns null when the key is not on a repaint boundary', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: key, width: 10, height: 10),
      ),
    );

    expect(await tester.runAsync(() => captureBoundaryPng(key)), isNull);
  });

  testWidgets('returns null when the key is not in the tree', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await tester.runAsync(() => captureBoundaryPng(GlobalKey())), isNull);
  });
}
