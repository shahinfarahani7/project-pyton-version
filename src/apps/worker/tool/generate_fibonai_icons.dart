// Writes the Android launcher icons from tool/brand/fibonai-mark-light.png.
//
// From src/apps/worker:
//   dart --packages=.dart_tool/package_config.json tool/generate_fibonai_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const _canvas = 0xFF0B0C0F;

/// Adaptive-icon foreground is 108dp; the mark must stay inside the 66dp
/// circular safe zone, so its width is capped at 48dp.
const _foregroundDp = 108;
const _foregroundMarkDp = 48;

/// Legacy (pre-API 26) icon is a full 48dp tile with no system mask.
const _legacyDp = 48;
const _legacyMarkDp = 30;
const _legacyCornerDp = 9;

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  final source = img.decodePng(
    File('tool/brand/fibonai-mark-light.png').readAsBytesSync(),
  );
  if (source == null) {
    stderr.writeln('tool/brand/fibonai-mark-light.png is not a PNG');
    exitCode = 1;
    return;
  }
  final mark = _cropToInk(source);
  final res = Directory('android/app/src/main/res');

  for (final entry in _densities.entries) {
    final scale = entry.value;
    final dir = Directory('${res.path}/mipmap-${entry.key}')
      ..createSync(recursive: true);

    final foreground = _place(
      size: (_foregroundDp * scale).round(),
      mark: mark,
      markWidth: (_foregroundMarkDp * scale).round(),
    );
    File('${dir.path}/ic_launcher_foreground.png')
        .writeAsBytesSync(img.encodePng(foreground));

    final legacySize = (_legacyDp * scale).round();
    final legacy = img.Image(width: legacySize, height: legacySize, numChannels: 4);
    img.fillRect(
      legacy,
      x1: 0,
      y1: 0,
      x2: legacySize - 1,
      y2: legacySize - 1,
      color: _rgba(_canvas),
      radius: (_legacyCornerDp * scale).round(),
    );
    _composite(
      legacy,
      mark,
      markWidth: (_legacyMarkDp * scale).round(),
    );
    File('${dir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(legacy));
    stdout.writeln('mipmap-${entry.key}: '
        'foreground ${foreground.width}px, legacy ${legacy.width}px');
  }
}

img.Image _place({
  required int size,
  required img.Image mark,
  required int markWidth,
}) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  _composite(out, mark, markWidth: markWidth);
  return out;
}

void _composite(img.Image target, img.Image mark, {required int markWidth}) {
  final scaled = img.copyResize(
    mark,
    width: markWidth,
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(
    target,
    scaled,
    dstX: (target.width - scaled.width) ~/ 2,
    dstY: (target.height - scaled.height) ~/ 2,
  );
}

img.Image _cropToInk(img.Image source) {
  var left = source.width, top = source.height, right = -1, bottom = -1;
  for (final pixel in source) {
    if (pixel.a == 0) continue;
    if (pixel.x < left) left = pixel.x;
    if (pixel.y < top) top = pixel.y;
    if (pixel.x > right) right = pixel.x;
    if (pixel.y > bottom) bottom = pixel.y;
  }
  return img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}

img.Color _rgba(int argb) => img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    );
