import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proclan_app/share_image.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('shareImagePixelRatio', () {
    test('renders phone widths at 3x', () {
      expect(shareImagePixelRatio(360), 3);
      expect(shareImagePixelRatio(430), 3);
    });

    test('bounds tile width on wide screens', () {
      expect(shareImagePixelRatio(1024), 2);
      expect(shareImagePixelRatio(2048), 1);
    });

    test('falls back to 3x without a usable width', () {
      expect(shareImagePixelRatio(0), 3);
      expect(shareImagePixelRatio(-10), 3);
      expect(shareImagePixelRatio(double.nan), 3);
      expect(shareImagePixelRatio(double.infinity), 3);
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
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 180);
      expect(frame.image.height, 120);
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets('long cards keep 3x resolution and pixels across tile seams', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          children: [
            RepaintBoundary(
              key: key,
              child: const SizedBox(
                height: 6100.5,
                child: CustomPaint(painter: _Stripes()),
              ),
            ),
          ],
        ),
      ),
    );
    // Narrow the viewport to keep this regression test cheap, while retaining
    // a full-height, offscreen card and fractional layout dimensions.
    await tester.binding.setSurfaceSize(const Size(60.5, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    await tester.runAsync(() async {
      final bytes = await captureBoundaryPng(key);
      expect(bytes, isNotNull);
      final codec = await ui.instantiateImageCodec(bytes!);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      expect(image.width, 182);
      expect(image.height, 18302);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      // Check both sides of every tile seam and the bottom offscreen content.
      for (var seam = 1024; seam < image.height - 1; seam += 1024) {
        for (final y in [seam - 1, seam]) {
          final red = (y ~/ 3).isEven;
          final offset = (y * image.width + 30) * 4;
          expect(pixels.getUint8(offset), red ? 255 : 0, reason: 'row $y');
          expect(pixels.getUint8(offset + 2), red ? 0 : 255, reason: 'row $y');
          expect(pixels.getUint8(offset + 3), 255, reason: 'row $y');
        }
      }
      expect(pixels.getUint8(((18300 * image.width) + 30) * 4), 255);
      image.dispose();
      codec.dispose();
    });
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

class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < size.height; y++) {
      paint.color = y.isEven ? const Color(0xFFFF0000) : const Color(0xFF0000FF);
      canvas.drawRect(Rect.fromLTWH(0, y.toDouble(), size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}
