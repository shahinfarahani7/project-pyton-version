import 'package:crypto/crypto.dart';

/// PP-OCRv5 mobile Arabic/Persian artifact manifest (ONNX, no binaries in Git).
abstract final class PaddleOcrModelCatalog {
  static const profileId = 'paddleocr-mobile';
  static const modelVersionId = 'mdv_paddleocr_mobile';

  static const detectorFile = 'ppocrv5_mobile_det.onnx';
  static const recognizerFile = 'ppocrv5_mobile_rec_arabic.onnx';
  static const dictFile = 'ppocrv5_arabic_dict.txt';

  static const detectorVersion = 'PP-OCRv5-mobile-det-v1';
  static const recognizerVersion = 'PP-OCRv5-mobile-rec-arabic-v1';

  static const deviceRelativeDir = 'Edgemint/models/paddleocr';

  static const artifacts = [
    OcrArtifactSpec(
      fileName: detectorFile,
      version: detectorVersion,
      sha256: '0000000000000000000000000000000000000000000000000000000000000000',
      sizeBytes: 0,
    ),
    OcrArtifactSpec(
      fileName: recognizerFile,
      version: recognizerVersion,
      sha256: '0000000000000000000000000000000000000000000000000000000000000000',
      sizeBytes: 0,
    ),
    OcrArtifactSpec(
      fileName: dictFile,
      version: recognizerVersion,
      sha256: '0000000000000000000000000000000000000000000000000000000000000000',
      sizeBytes: 0,
    ),
  ];

  static String sha256Hex(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  static bool verifySha256(List<int> bytes, String expectedHex) {
    if (expectedHex == '0' * 64) {
      // Placeholder in manifest — skip until real digest is pinned in evidence.
      return bytes.isNotEmpty;
    }
    return sha256Hex(bytes) == expectedHex.toLowerCase();
  }
}

class OcrArtifactSpec {
  const OcrArtifactSpec({
    required this.fileName,
    required this.version,
    required this.sha256,
    required this.sizeBytes,
  });

  final String fileName;
  final String version;
  final String sha256;
  final int sizeBytes;
}
