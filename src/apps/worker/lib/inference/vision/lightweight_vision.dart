import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class LightweightVision {
  const LightweightVision();

  img.Image decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null || image.width < 2 || image.height < 2) {
      throw const FormatException('IMAGE_DECODE_FAILED');
    }
    return image;
  }

  double blurVariance(Uint8List bytes) {
    final image = decode(bytes);
    final sampled = img.copyResize(image, width: math.min(512, image.width));
    var sum = 0.0;
    var sumSquares = 0.0;
    var count = 0;
    for (var y = 1; y < sampled.height - 1; y++) {
      for (var x = 1; x < sampled.width - 1; x++) {
        final center = _gray(sampled.getPixel(x, y));
        final laplacian = 4 * center -
            _gray(sampled.getPixel(x - 1, y)) -
            _gray(sampled.getPixel(x + 1, y)) -
            _gray(sampled.getPixel(x, y - 1)) -
            _gray(sampled.getPixel(x, y + 1));
        sum += laplacian;
        sumSquares += laplacian * laplacian;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    return sumSquares / count - mean * mean;
  }

  Map<String, dynamic> documentQuality(Uint8List bytes) {
    final image = decode(bytes);
    final sampled = img.copyResize(image, width: math.min(512, image.width));
    var sum = 0.0;
    var sumSquares = 0.0;
    var clippedDark = 0;
    var clippedLight = 0;
    final total = sampled.width * sampled.height;
    for (final pixel in sampled) {
      final gray = _gray(pixel);
      sum += gray;
      sumSquares += gray * gray;
      if (gray <= 8) clippedDark++;
      if (gray >= 247) clippedLight++;
    }
    final mean = sum / total;
    final contrast = math.sqrt(math.max(0, sumSquares / total - mean * mean));
    final sharpness = blurVariance(bytes);
    final exposureScore = (1 - (mean - 180).abs() / 180).clamp(0.0, 1.0);
    final contrastScore = (contrast / 64).clamp(0.0, 1.0);
    final sharpnessScore = (sharpness / 500).clamp(0.0, 1.0);
    final clipping = (clippedDark + clippedLight) / total;
    final score = (0.35 * exposureScore +
            0.25 * contrastScore +
            0.40 * sharpnessScore -
            0.20 * clipping)
        .clamp(0.0, 1.0);
    return {
      'score': score,
      'brightness': mean,
      'contrast': contrast,
      'sharpness': sharpness,
      'clippedRatio': clipping,
      'acceptable': score >= 0.45,
    };
  }

  Map<String, dynamic> duplicate(Uint8List first, Uint8List second) {
    final a = _differenceHash(decode(first));
    final b = _differenceHash(decode(second));
    var distance = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) distance++;
    }
    final similarity = 1 - distance / a.length;
    return {
      'hammingDistance': distance,
      'similarity': similarity,
      'duplicate': distance <= 6,
      'algorithm': 'dHash-64',
    };
  }

  List<bool> _differenceHash(img.Image source) {
    final image = img.copyResize(source, width: 9, height: 8);
    final bits = <bool>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        bits.add(_gray(image.getPixel(x, y)) > _gray(image.getPixel(x + 1, y)));
      }
    }
    return bits;
  }

  double _gray(img.Pixel pixel) =>
      0.299 * pixel.r.toDouble() +
      0.587 * pixel.g.toDouble() +
      0.114 * pixel.b.toDouble();
}
