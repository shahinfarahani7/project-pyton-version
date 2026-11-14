import 'package:flutter/material.dart';

import 'worker_theme.dart';

/// Blocks the worker until the phone has a network again.
///
/// This is an overlay, not a [DialogRoute]. Pushing and removing a route when
/// the radio flaps calls [NavigatorState.removeRoute] on a route that may
/// already be gone, and that throws in release. The system then shows the
/// Android Close app dialog.
class WorkerOfflineGate extends StatelessWidget {
  const WorkerOfflineGate({
    super.key,
    required this.offline,
    required this.child,
  });

  final bool offline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !offline,
      child: Stack(
        children: [
          AbsorbPointer(absorbing: offline, child: child),
          if (offline) ...[
            const ModalBarrier(
              dismissible: false,
              color: Colors.black54,
            ),
            const Center(child: WorkerOfflineConnectionDialog()),
          ],
        ],
      ),
    );
  }
}

class WorkerOfflineConnectionDialog extends StatelessWidget {
  const WorkerOfflineConnectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.wifi_off_rounded,
        color: WorkerColors.warning,
        size: 32,
      ),
      title: const Text('No connection'),
      content: const Text(
        'FibonAI Worker is offline. Connect to Wi-Fi or mobile data to continue. '
        'This message closes when the connection is back.',
      ),
    );
  }
}
