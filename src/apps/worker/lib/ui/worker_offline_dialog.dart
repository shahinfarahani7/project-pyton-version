import 'package:flutter/material.dart';

import 'worker_theme.dart';

const workerOfflineDialogRouteName = 'worker-offline-connection';

/// Blocks the worker until the phone has a network again.
class WorkerOfflineGate extends StatefulWidget {
  const WorkerOfflineGate({
    super.key,
    required this.offline,
    required this.child,
  });

  final bool offline;
  final Widget child;

  @override
  State<WorkerOfflineGate> createState() => _WorkerOfflineGateState();
}

class _WorkerOfflineGateState extends State<WorkerOfflineGate> {
  Route<void>? _route;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(WorkerOfflineGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offline != widget.offline) {
      _schedule();
    }
  }

  @override
  void dispose() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    super.dispose();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.offline) {
        _show();
      } else {
        _dismiss();
      }
    });
  }

  void _show() {
    final current = _route;
    if (current != null && current.isActive) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _OfflineConnectionRoute(
      context: context,
      barrierLabel: 'No connection',
      settings: const RouteSettings(name: workerOfflineDialogRouteName),
      builder: (context) => const WorkerOfflineConnectionDialog(),
    );
    _route = route;
    navigator.push(route);
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(absorbing: widget.offline, child: widget.child);
  }
}

class _OfflineConnectionRoute extends DialogRoute<void> {
  _OfflineConnectionRoute({
    required super.context,
    required super.builder,
    required super.settings,
    super.barrierLabel,
  }) : super(barrierDismissible: false);

  @override
  RoutePopDisposition get popDisposition => RoutePopDisposition.doNotPop;
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
