import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Transport failures are connectivity events. They are not runtime crashes.
abstract final class NetworkFailure {
  static bool isTransport(Object error) {
    final seen = <int>{};
    Object? current = error;
    while (current != null && seen.add(identityHashCode(current))) {
      if (current is SocketException ||
          current is TimeoutException ||
          current is http.ClientException) {
        return true;
      }
      final text = current.toString().toLowerCase();
      if (text.contains('no route to host') ||
          text.contains('connection refused') ||
          text.contains('network is unreachable') ||
          text.contains('failed host lookup') ||
          text.contains('network unavailable') ||
          text.contains('socketexception')) {
        return true;
      }
      current = null;
    }
    return false;
  }
}

enum ConnectivityState { online, offline, reconnecting }

/// Independent of execution phase and of server-sync state.
class ConnectivitySession {
  ConnectivityState state = ConnectivityState.online;
  int attempt = 0;

  void lost() {
    if (state == ConnectivityState.online) {
      state = ConnectivityState.offline;
    }
  }

  Duration beginReconnect() {
    state = ConnectivityState.reconnecting;
    return ReconnectBackoff.delayForAttempt(attempt);
  }

  void stillOffline() {
    attempt += 1;
    state = ConnectivityState.offline;
  }

  void restored() {
    attempt = 0;
    state = ConnectivityState.online;
  }
}

abstract final class ReconnectBackoff {
  static const delays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  static Duration delayForAttempt(int attempt) {
    final index = attempt < 0
        ? 0
        : (attempt >= delays.length ? delays.length - 1 : attempt);
    return delays[index];
  }
}

enum SyncReplay { send, dropWithoutComplete }

abstract final class AssignmentSyncReconciler {
  static SyncReplay decide({
    required String kind,
    required DateTime? leaseExpiresAt,
    required DateTime now,
    required bool reassigned,
  }) {
    final expired =
        leaseExpiresAt != null && !leaseExpiresAt.toUtc().isAfter(now.toUtc());
    if (kind == 'complete' && (expired || reassigned)) {
      return SyncReplay.dropWithoutComplete;
    }
    return SyncReplay.send;
  }
}
