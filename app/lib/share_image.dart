import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 高度不再影响清晰度；宽屏限制到 2048 像素，手机按 3 倍渲染。
double shareImagePixelRatio(double logicalWidth) =>
    logicalWidth.isFinite && logicalWidth > 0
    ? math.min(3.0, 2048 / logicalWidth)
    : 3.0;

const _tileHeight = 1024;
const _maxPixels = 40 * 1000 * 1000;

/// 把 [key] 指向的 RepaintBoundary 画成 PNG。
/// 拿不到边界、或者渲染失败，都返回 null，调用方退回只分享文字。
Future<Uint8List?> captureBoundaryPng(GlobalKey key) async {
  final object = key.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary || !object.attached) {
    return null;
  }
  if (!object.hasSize || object.size.isEmpty) {
    return null;
  }
  try {
    final layer = object.layer;
    if (layer is! OffsetLayer) return null;
    final ratio = shareImagePixelRatio(object.size.width);
    final width = (object.size.width * ratio).ceil();
    final height = (object.size.height * ratio).ceil();
    // 超出资源预算走原有文字回退，不再悄悄生成模糊图片。
    if (width * height > _maxPixels) return null;
    final png = _PngRows(width, height);
    try {
      for (var top = 0; top < height; top += _tileHeight) {
        final rows = math.min(_tileHeight, height - top);
        final image = await layer.toImage(
          Rect.fromLTWH(0, top / ratio, width / ratio, rows / ratio),
          pixelRatio: ratio,
        );
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          if (data == null) return null;
          // 浮点舍入可能让 tile 多出一行/列，只取目标像素范围。
          png.addRows(data, rows, image.width * 4);
        } finally {
          image.dispose();
        }
      }
      return png.finish();
    } finally {
      png.close();
    }
  } catch (_) {
    return null;
  }
}

/// 将每段的原始像素流式写入同一张 PNG，不创建整张长图的 GPU 纹理，
/// 也不在内存里拼接整张 RGBA 位图。IDAT 共用一个连续的 zlib 数据流。
class _PngRows implements Sink<List<int>> {
  _PngRows(this.width, int height) {
    _bytes.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 6);
    _chunk('IHDR', header.buffer.asUint8List());
    _compressed = ZLibEncoder().startChunkedConversion(this);
  }

  final int width;
  final _bytes = BytesBuilder(copy: false);
  late final Sink<List<int>> _compressed;
  bool _closed = false;

  void addRows(ByteData pixels, int rows, int stride) {
    final source = pixels.buffer.asUint8List(
      pixels.offsetInBytes,
      pixels.lengthInBytes,
    );
    final rowLength = width * 4;
    final filtered = Uint8List((rowLength + 1) * rows);
    for (var row = 0; row < rows; row++) {
      // 每行首字节 0 表示 PNG 的 None filter；像素原样无损保存。
      final start = row * (rowLength + 1) + 1;
      filtered.setRange(start, start + rowLength, source, row * stride);
    }
    _compressed.add(filtered);
  }

  Uint8List finish() {
    close();
    _chunk('IEND', const []);
    return _bytes.takeBytes();
  }

  @override
  void add(List<int> data) => _chunk('IDAT', data);

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _compressed.close();
  }

  void _chunk(String type, List<int> data) {
    final chunk = Uint8List(data.length + 12);
    final view = ByteData.sublistView(chunk);
    view.setUint32(0, data.length);
    chunk.setRange(4, 8, type.codeUnits);
    chunk.setRange(8, 8 + data.length, data);
    var crc = 0xffffffff;
    for (var i = 4; i < chunk.length - 4; i++) {
      crc = _crcTable[(crc ^ chunk[i]) & 0xff] ^ (crc >>> 8);
    }
    view.setUint32(chunk.length - 4, crc ^ 0xffffffff);
    _bytes.add(chunk);
  }

  static final _crcTable = List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
    return crc;
  });
}

/// 文件名只留 ASCII 安全字符；卡片 id 来自服务端。
String shareImageFileName(String cardId) {
  final safe = cardId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return 'proclan-${safe.isEmpty ? 'card' : safe}.png';
}

/// 把 PNG 写到临时目录。失败返回 null，原因交给调用方统一处理。
Future<File?> writeShareImage(Uint8List bytes, String cardId) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${shareImageFileName(cardId)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  } catch (_) {
    return null;
  }
}
