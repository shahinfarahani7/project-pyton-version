import 'package:flutter/foundation.dart';

/// Shared worker access token source for heartbeat and assignment commands.
class WorkerAccessTokenProvider {
  WorkerAccessTokenProvider({
    String? initialToken,
    String Function()? readToken,
  })  : _readToken = readToken,
        _token = initialToken ?? '';

  final String Function()? _readToken;
  String _token;

  String get current {
    final dynamicToken = _readToken?.call();
    if (dynamicToken != null && dynamicToken.isNotEmpty) {
      return dynamicToken;
    }
    return _token;
  }

  void update(String token) {
    _token = token;
  }

  String requireToken() {
    final value = current;
    if (value.isEmpty) {
      if (kDebugMode) {
        throw StateError('Worker access token is not configured');
      }
      throw StateError('Worker access token is not configured');
    }
    return value;
  }
}
