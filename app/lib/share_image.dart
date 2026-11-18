import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 长图的高度预算（逻辑像素 × 像素比）。卡片很长时按比例降低像素比，
/// 免得超过 GPU 纹理上限，或者渲染到一半被杀掉。
const double shareImagePixelBudget = 3000;

/// 每逻辑像素的目标像素比：一般卡片 2 倍，很长的卡片最低降到 0.5 倍。
double shareImagePixelRatio(double logicalHeight) {
  if (!logicalHeight.isFinite || logicalHeight <= 0) {
    return 2;
  }
  return (shareImagePixelBudget / logicalHeight).clamp(0.5, 2);
}

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
    final image = await object.toImage(
      pixelRatio: shareImagePixelRatio(object.size.height),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return null;
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
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
