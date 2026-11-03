import 'dart:convert';

import 'package:http/http.dart' as http;

/// Local email sign-in against the API gateway (`/auth/email-*`).
///
/// Passwords are sent once and never stored. Production customer sign-in remains
/// Cognito; these routes exist only for the local BFF.
class WorkerEmailAuthClient {
  WorkerEmailAuthClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  static const minPasswordLength = 8;

  Future<WorkerEmailAuthResult> signUp({
    required String email,
    required String password,
  }) {
    return _postSession('/auth/email-signup', {
      'email': email,
      'password': password,
    }, fallback: 'Could not create the account.');
  }

  Future<WorkerEmailAuthResult> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _postSession('/auth/email-password', {
      'email': email,
      'password': password,
    }, fallback: 'Could not sign in.');
  }

  Future<WorkerEmailCodeIssue> requestCode(String email) async {
    final response = await _post('/auth/email-otp/challenges', {
      'email': email,
    }, fallback: 'Could not send a sign-in code.');
    final decoded = _decodeMap(response.body);
    final challengeId = decoded['challengeId'];
    final expiresInSeconds = decoded['expiresInSeconds'];
    if (challengeId is! String ||
        challengeId.isEmpty ||
        expiresInSeconds is! int) {
      throw WorkerEmailAuthException(
        'Sign-in code response was not recognized.',
      );
    }
    final devCode = decoded['devCode'];
    return WorkerEmailCodeIssue(
      challengeId: challengeId,
      expiresInSeconds: expiresInSeconds,
      devCode: devCode is String && devCode.isNotEmpty ? devCode : null,
    );
  }

  Future<WorkerEmailAuthResult> verifyCode({
    required String email,
    required String challengeId,
    required String code,
  }) {
    return _postSession('/auth/email-otp/verify', {
      'email': email,
      'challengeId': challengeId,
      'code': code,
    }, fallback: 'Could not verify the sign-in code.');
  }

  Future<void> logout({
    required String? sessionCookie,
    required String? csrfToken,
  }) async {
    if (sessionCookie == null ||
        sessionCookie.isEmpty ||
        csrfToken == null ||
        csrfToken.isEmpty) {
      return;
    }
    final response = await _http
        .post(
          _uri('/auth/sessions/logout'),
          headers: {
            'Accept': 'application/json',
            'Cookie': sessionCookie,
            'X-CSRF-Token': csrfToken,
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerEmailAuthException(
        workerAuthErrorMessage(response.body, fallback: 'Could not sign out.'),
      );
    }
  }

  Future<WorkerEmailAuthResult> _postSession(
    String path,
    Map<String, Object?> body, {
    required String fallback,
  }) async {
    final response = await _post(path, body, fallback: fallback);
    return parseWorkerEmailAuthResult(
      response.body,
      sessionCookie: readSessionCookieHeader(response.headers['set-cookie']),
      csrfToken: response.headers['x-csrf-token'],
    );
  }

  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    required String fallback,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _uri(path),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on WorkerEmailAuthException {
      rethrow;
    } catch (_) {
      throw WorkerEmailAuthException(
        'Could not reach the sign-in service. Check that the API gateway is running.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerEmailAuthException(
        workerAuthErrorMessage(response.body, fallback: fallback),
      );
    }
    return response;
  }

  Uri _uri(String path) {
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$basePath$path', query: null, fragment: null);
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw WorkerEmailAuthException('Sign-in response was not recognized.');
    }
    return decoded.cast<String, dynamic>();
  }
}

class WorkerEmailAuthException implements Exception {
  WorkerEmailAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorkerEmailAuthResult {
  const WorkerEmailAuthResult({
    required this.sessionPublicId,
    required this.expiresAtUtc,
    required this.role,
    this.sessionCookie,
    this.csrfToken,
  });

  final String sessionPublicId;
  final DateTime expiresAtUtc;
  final String role;
  final String? sessionCookie;
  final String? csrfToken;
}

class WorkerEmailCodeIssue {
  const WorkerEmailCodeIssue({
    required this.challengeId,
    required this.expiresInSeconds,
    this.devCode,
  });

  final String challengeId;
  final int expiresInSeconds;
  final String? devCode;
}

WorkerEmailAuthResult parseWorkerEmailAuthResult(
  String body, {
  String? sessionCookie,
  String? csrfToken,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw WorkerEmailAuthException('Sign-in response was not recognized.');
  }
  final sessionPublicId = decoded['sessionPublicId'];
  final expiresAt = decoded['expiresAt'];
  if (sessionPublicId is! String ||
      sessionPublicId.isEmpty ||
      expiresAt is! String) {
    throw WorkerEmailAuthException('Sign-in response was not recognized.');
  }
  final role = decoded['role'];
  return WorkerEmailAuthResult(
    sessionPublicId: sessionPublicId,
    expiresAtUtc: DateTime.parse(expiresAt).toUtc(),
    role: role is String && role.isNotEmpty ? role : 'customer',
    sessionCookie: sessionCookie,
    csrfToken: csrfToken,
  );
}

/// `Set-Cookie` value suitable for a later `Cookie` header. Secrets stay out of logs.
String? readSessionCookieHeader(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'((?:__Host-)?edgemint-session)=([^;,\s]+)',
  ).firstMatch(setCookie);
  if (match == null) {
    return null;
  }
  return '${match.group(1)}=${match.group(2)}';
}

String workerAuthErrorMessage(String body, {required String fallback}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      if (detail is Map) {
        final nested = detail['detail'];
        if (nested is String && nested.trim().isNotEmpty) {
          return nested.trim();
        }
        final title = detail['title'];
        if (title is String && title.trim().isNotEmpty) {
          return title.trim();
        }
      }
      final title = decoded['title'];
      if (title is String && title.trim().isNotEmpty) {
        return title.trim();
      }
    }
  } catch (_) {
    // Fall through to the plain-text or fallback message.
  }
  final trimmed = body.trim();
  if (trimmed.isNotEmpty &&
      trimmed.length < 180 &&
      !trimmed.startsWith('{') &&
      !trimmed.startsWith('<')) {
    return trimmed;
  }
  return fallback;
}
