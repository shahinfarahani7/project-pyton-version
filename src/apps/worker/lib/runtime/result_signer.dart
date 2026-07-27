import 'dart:convert';

import 'package:crypto/crypto.dart';

class ResultSigner {
  const ResultSigner({required this.signingMaterial});

  final String signingMaterial;

  String sign({
    required String assignmentId,
    required int fenceToken,
    required String resultSha256,
    required String outputArtifactId,
  }) {
    final payload = '$assignmentId|$fenceToken|$resultSha256|$outputArtifactId';
    final mac = Hmac(sha256, utf8.encode(signingMaterial));
    return base64Encode(mac.convert(utf8.encode(payload)).bytes);
  }
}
