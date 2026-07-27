import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Encrypted local blob store. Production Android uses Keystore-backed keys via platform channel.
abstract class EncryptedStore {
  Future<void> write(String key, Uint8List plaintext);
  Future<Uint8List?> read(String key);
  Future<void> delete(String key);
  Future<void> deleteAll(Iterable<String> keys);
}

class InMemoryEncryptedStore implements EncryptedStore {
  InMemoryEncryptedStore({Uint8List? masterKey}) : _masterKey = masterKey ?? Uint8List.fromList(List.filled(32, 7));

  final Uint8List _masterKey;
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<void> write(String key, Uint8List plaintext) async {
    _blobs[key] = _seal(plaintext);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final sealed = _blobs[key];
    if (sealed == null) {
      return null;
    }
    return _open(sealed);
  }

  @override
  Future<void> delete(String key) async {
    _blobs.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      _blobs.remove(key);
    }
  }

  Uint8List _seal(Uint8List plaintext) {
    final mac = Hmac(sha256, _masterKey);
    final digest = mac.convert(plaintext).bytes;
    return Uint8List.fromList([...digest, ...plaintext]);
  }

  Uint8List _open(Uint8List sealed) {
    if (sealed.length < 32) {
      throw StateError('Corrupt encrypted blob');
    }
    final digest = sealed.sublist(0, 32);
    final plaintext = sealed.sublist(32);
    final mac = Hmac(sha256, _masterKey);
    final expected = mac.convert(plaintext).bytes;
    if (!listEquals(digest, expected)) {
      throw StateError('Encrypted blob integrity check failed');
    }
    return Uint8List.fromList(plaintext);
  }

  bool listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

String sha256HexString(String value) => sha256Hex(utf8.encode(value));

String blobRef(String assignmentId, int sequence) => 'ckpt/$assignmentId/$sequence';
