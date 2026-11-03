import 'dart:convert';

import 'package:edgemint_worker/api/worker_email_auth_client.dart';
import 'package:edgemint_worker/config/worker_config.dart';
import 'package:edgemint_worker/platform/worker_runtime_channel.dart';
import 'package:edgemint_worker/runtime/encrypted_store.dart';
import 'package:edgemint_worker/runtime/worker_email_session_store.dart';
import 'package:edgemint_worker/runtime/worker_mission_progress_store.dart';
import 'package:edgemint_worker/ui/tabs/worker_profile_tab.dart';
import 'package:edgemint_worker/ui/worker_login_screen.dart';
import 'package:edgemint_worker/ui/worker_theme.dart';
import 'package:edgemint_worker/worker_app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('api gateway follows the worker host on port 8080', () {
    final config = WorkerConfig(baseUrl: Uri.parse('http://10.0.2.2:8081'));
    expect(config.apiGatewayBaseUrl, Uri.parse('http://10.0.2.2:8080'));

    final override = WorkerConfig(
      baseUrl: Uri.parse('http://10.0.2.2:8081'),
      apiBaseUrl: Uri.parse('http://127.0.0.1:9090'),
    );
    expect(override.apiGatewayBaseUrl, Uri.parse('http://127.0.0.1:9090'));
  });

  test('auth error prefers the nested detail', () {
    expect(
      workerAuthErrorMessage(
        jsonEncode({
          'detail': {
            'code': 'AUTH_INVALID_CREDENTIAL',
            'title': 'Invalid credentials',
            'detail': 'The email or password is incorrect.',
          },
        }),
        fallback: 'Could not sign in.',
      ),
      'The email or password is incorrect.',
    );
  });

  test('session cookie header keeps the development cookie name', () {
    expect(
      readSessionCookieHeader(
        'edgemint-session=abc123; HttpOnly; Path=/; SameSite=strict',
      ),
      'edgemint-session=abc123',
    );
  });

  test('email session round-trips and toString omits the cookie', () async {
    final store = WorkerEmailSessionStore(InMemoryEncryptedStore());
    final session = WorkerEmailSession(
      email: 'worker@example.com',
      sessionPublicId: 'ses_1',
      expiresAtUtc: DateTime.utc(2026, 12, 1),
      sessionCookie: 'edgemint-session=secret',
      csrfToken: 'csrf-secret',
    );
    await store.write(session);

    final loaded = await store.read();
    expect(loaded?.email, 'worker@example.com');
    expect(loaded?.sessionCookie, 'edgemint-session=secret');
    expect(loaded.toString(), isNot(contains('secret')));
  });

  test('expired email session is cleared', () async {
    final encrypted = InMemoryEncryptedStore();
    await WorkerEmailSessionStore(encrypted).write(
      WorkerEmailSession(
        email: 'old@example.com',
        sessionPublicId: 'ses_old',
        expiresAtUtc: DateTime.utc(2020, 1, 1),
      ),
    );
    final controller = _controller(
      encrypted: encrypted,
      client: MockClient((_) async => http.Response('no', 404)),
    );
    addTearDown(controller.dispose);

    await controller.loadEmailSession();

    expect(controller.needsEmailSignIn, isTrue);
    expect(await WorkerEmailSessionStore(encrypted).read(), isNull);
  });

  test('sign-in stores the email session and sign-out revokes it', () async {
    final requests = <http.Request>[];
    final controller = _controller(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/email-password') {
          return _sessionResponse();
        }
        if (request.url.path == '/auth/sessions/logout') {
          return http.Response('{"status":"revoked"}', 200);
        }
        return http.Response('missing', 404);
      }),
    );
    addTearDown(controller.dispose);

    final error = await controller.signInWithEmailPassword(
      email: 'Worker@Example.com',
      password: 'edgemint-dev',
    );
    await _settleEnrollment();

    expect(error, isNull);
    expect(controller.emailSignedIn, isTrue);
    expect(controller.needsEmailSignIn, isFalse);
    expect(controller.accountProfile?.email, 'worker@example.com');
    expect(controller.accountProfile?.username, 'worker');
    expect(controller.isDailyMissionCompletedToday, isTrue);
    final signIn = requests.firstWhere(
      (request) => request.url.path == '/auth/email-password',
    );
    expect(signIn.url.host, '10.0.2.2');
    expect(signIn.url.port, 8080);
    expect(jsonDecode(signIn.body), {
      'email': 'Worker@Example.com',
      'password': 'edgemint-dev',
    });

    await controller.signOutEmail();

    expect(controller.emailSignedIn, isFalse);
    expect(controller.accountProfile, isNull);
    final logout = requests.lastWhere(
      (request) => request.url.path == '/auth/sessions/logout',
    );
    expect(_header(logout, 'cookie'), 'edgemint-session=tok');
    expect(_header(logout, 'x-csrf-token'), 'csrf-1');
    await controller.loadEmailSession();
    expect(controller.emailSignedIn, isFalse);
  });

  test('a restored sign-in marks the daily mission for today', () async {
    final encrypted = InMemoryEncryptedStore();
    await WorkerMissionProgressStore(encrypted).writeDailyMissionDay(
      workerLocalCalendarDay(DateTime.now().subtract(const Duration(days: 1))),
    );
    await WorkerEmailSessionStore(encrypted).write(
      WorkerEmailSession(
        email: 'worker@example.com',
        sessionPublicId: 'ses_keep',
        expiresAtUtc: DateTime.utc(2026, 12, 1),
      ),
    );
    final controller = _controller(
      encrypted: encrypted,
      client: MockClient((_) async => http.Response('no', 404)),
    );
    addTearDown(controller.dispose);

    await controller.loadEmailSession();

    expect(controller.emailSignedIn, isTrue);
    expect(controller.isDailyMissionCompletedToday, isTrue);
  });

  test('signup rejects a short password before calling the server', () async {
    final controller = _controller(
      client: MockClient((request) async {
        fail('server should not be called for ${request.url}');
      }),
    );
    addTearDown(controller.dispose);

    final error = await controller.signUpWithEmail(
      email: 'new@example.com',
      password: 'short',
      confirmPassword: 'short',
    );

    expect(error, 'Use a password of at least 8 characters.');
    expect(controller.emailSignedIn, isFalse);
  });

  testWidgets('password sign-in shows a local validation error', (
    tester,
  ) async {
    final controller = _controller(
      client: MockClient((request) async {
        fail('server should not be called for ${request.url}');
      }),
    );
    addTearDown(controller.dispose);
    await _pumpLogin(tester, controller);

    await tester.enterText(find.byKey(const Key('worker-login-password')), '');
    await tester.tap(find.byKey(const Key('worker-login-submit')));
    await tester.pump();

    expect(find.text('Enter your password.'), findsOneWidget);
    expect(controller.emailSignedIn, isFalse);
  });

  testWidgets('email code sign-in opens a session', (tester) async {
    final controller = _controller(
      client: MockClient((request) async {
        if (request.url.path == '/auth/email-otp/challenges') {
          return http.Response(
            jsonEncode({
              'challengeId': 'otp_1',
              'expiresInSeconds': 300,
              'emailDispatched': false,
              'devCode': '123456',
            }),
            200,
          );
        }
        if (request.url.path == '/auth/email-otp/verify') {
          expect(jsonDecode(request.body), {
            'email': 'worker@example.com',
            'challengeId': 'otp_1',
            'code': '123456',
          });
          return _sessionResponse();
        }
        return http.Response('missing', 404);
      }),
    );
    addTearDown(controller.dispose);
    await _pumpLogin(tester, controller);

    await tester.enterText(
      find.byKey(const Key('worker-login-email')),
      'worker@example.com',
    );
    await tester.tap(find.byKey(const Key('worker-login-method-otp')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('worker-login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Development code: 123456'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('worker-login-otp')), '123456');
    await tester.tap(find.byKey(const Key('worker-login-submit')));
    await tester.pumpAndSettle();

    expect(controller.emailSignedIn, isTrue);
    expect(find.byKey(const Key('worker-login-error')), findsNothing);
  });

  testWidgets('signed-in profile can sign out', (tester) async {
    final controller = _controller(
      client: MockClient((request) async {
        if (request.url.path == '/auth/email-password') {
          return _sessionResponse();
        }
        if (request.url.path == '/auth/sessions/logout') {
          return http.Response('{"status":"revoked"}', 200);
        }
        return http.Response('missing', 404);
      }),
    );
    addTearDown(controller.dispose);
    final error = await controller.signInWithEmailPassword(
      email: 'worker@example.com',
      password: 'edgemint-dev',
    );
    expect(error, isNull);

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkerTheme(),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              Scaffold(body: WorkerProfileTab(controller: controller)),
        ),
      ),
    );

    expect(find.text('w•••@example.com'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(controller.needsEmailSignIn, isTrue);
    expect(find.text('Not set'), findsNWidgets(2));
  });
}

WorkerAppController _controller({
  required http.Client client,
  EncryptedStore? encrypted,
}) {
  return WorkerAppController(
    config: WorkerConfig(baseUrl: Uri.parse('http://10.0.2.2:8081')),
    httpClient: client,
    encryptedStore: encrypted ?? InMemoryEncryptedStore(),
    platform: NoopWorkerRuntimeChannel(),
  );
}

http.Response _sessionResponse() {
  return http.Response(
    jsonEncode({
      'sessionPublicId': 'ses_worker',
      'workspaceId': '00000000-0000-0000-0000-000000000001',
      'authorizationGeneration': 1,
      'expiresAt': '2026-12-01T00:00:00Z',
      'role': 'customer',
    }),
    200,
    headers: {
      'set-cookie': 'edgemint-session=tok; HttpOnly; Path=/',
      'x-csrf-token': 'csrf-1',
    },
  );
}

String? _header(http.Request request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  return null;
}

Future<void> _settleEnrollment() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _pumpLogin(
  WidgetTester tester,
  WorkerAppController controller,
) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWorkerTheme(),
      home: WorkerLoginScreen(controller: controller),
    ),
  );
}
