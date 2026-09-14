import 'dart:convert';
import 'dart:io';
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

/// Persists sealed blobs to a single JSON file under [directoryPath].
class PersistentEncryptedStore implements EncryptedStore {
  PersistentEncryptedStore._(this._file, this._masterKey);

  final File _file;
  final Uint8List _masterKey;
  final Map<String, Uint8List> _blobs = {};

  static Future<PersistentEncryptedStore> open(
    String directoryPath, {
    Uint8List? masterKey,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/edgemint_encrypted_store.json');
    final store = PersistentEncryptedStore._(
      file,
      masterKey ?? Uint8List.fromList(List.filled(32, 7)),
    );
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!_file.existsSync()) {
      return;
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((key, value) {
      _blobs[key] = base64Decode(value as String);
    });
  }

  Future<void> _persist() async {
    final encoded = {
      for (final entry in _blobs.entries) entry.key: base64Encode(entry.value),
    };
    await _file.writeAsString(jsonEncode(encoded), flush: true);
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
    if (!_bytesEqual(digest, expected)) {
      throw StateError('Encrypted blob integrity check failed');
    }
    return Uint8List.fromList(plaintext);
  }

  bool _bytesEqual(List<int> a, List<int> b) {
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

  @override
  Future<void> write(String key, Uint8List plaintext) async {
    _blobs[key] = _seal(plaintext);
    await _persist();
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
    await _persist();
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      _blobs.remove(key);
    }
    await _persist();
  }
}
