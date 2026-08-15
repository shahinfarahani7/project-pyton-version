import 'package:flutter/material.dart';

import 'runtime/execution_status.dart';
import 'runtime/gemma_bootstrap.dart';
import 'ui/gemma_download_dialog.dart';
import 'worker_app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GemmaBootstrap.ensureInitialized();
  runApp(const EdgeMintWorkerApp());
}

class EdgeMintWorkerApp extends StatelessWidget {
  const EdgeMintWorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EdgeMint Worker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25C7A5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const WorkerHomePage(),
    );
  }
}

class WorkerHomePage extends StatefulWidget {
  const WorkerHomePage({super.key});

  @override
  State<WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<WorkerHomePage> {
  late final WorkerAppController _controller;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = WorkerAppController();
    _controller.addListener(_onControllerChanged);
    _controller.bootstrap();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _runTaskWithGemma() async {
    await _controller.pollAndRunTask();
    if (!mounted) {
      return;
    }
    if (!_controller.backendOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.backendMessage)),
      );
      return;
    }
    if (_controller.executionStatus.phase == ExecutionPhase.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.executionStatus.detail ?? 'Task run failed')),
      );
    }
  }

  Future<void> _startGemmaDownload() async {
    if (!_controller.canStartGemmaDownload || _controller.isGemmaReady) {
      return;
    }

    final confirmed = await showGemmaDownloadDialog(context);
    if (!mounted || confirmed != true) {
      return;
    }

    await _controller.downloadGemmaModel();
    if (!mounted || _controller.modelPhase != ModelInstallPhase.failed) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_controller.modelError ?? 'Model download failed')),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_selectedNavIndex) {
          0 => 'EdgeMint',
          1 => 'Missions',
          2 => 'Models',
          3 => 'Earnings',
          _ => 'Profile',
        }),
        actions: [
          IconButton(
            onPressed: _controller.bootstrap,
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh',
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: (index) => setState(() => _selectedNavIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Missions'),
          NavigationDestination(icon: Icon(Icons.view_in_ar_outlined), label: 'Models'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
      body: SafeArea(
        child: switch (_selectedNavIndex) {
          0 => _homeTab(context),
          1 => _missionsTab(context),
          2 => _modelsTab(context),
          3 => _placeholderTab(context, 'Earnings', 'Payout history will appear here.'),
          _ => _placeholderTab(context, 'Profile', 'Worker profile settings will appear here.'),
        },
      ),
    );
  }

  Widget _homeTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready for missions',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(_controller.backendMessage),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Worker availability'),
                  value: _controller.available,
                  onChanged: (value) => setState(() => _controller.available = value),
                ),
                if (_controller.isGemmaReady)
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_controller.gemmaDownloadLabel)),
                    ],
                  )
                else
                  FilledButton.icon(
                    onPressed: _controller.canStartGemmaDownload ? _startGemmaDownload : null,
                    icon: const Icon(Icons.download_for_offline),
                    label: Text(_controller.gemmaDownloadLabel),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _controller.isGemmaDownloading || !_controller.isGemmaReady
                      ? null
                      : _runTaskWithGemma,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run task with model'),
                ),
                if (!_controller.isGemmaReady && _controller.backendOnline && !_controller.usesDevMockInference) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Model not ready — on x86 MEmu use dev mock (auto), or sideload on ARM64 device.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_controller.usesDevMockInference) ...[
                  const SizedBox(height: 8),
                  Text(
                    'x86 emulator: dev mock OCR active. Real Qwen3 needs ARM64 phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _readinessCard(context, _controller),
        Center(child: Text('Last sync ${_controller.lastSync}')),
      ],
    );
  }

  Widget _missionsTab(BuildContext context) {
    final phase = _controller.executionStatus.phase;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task queue', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _controller.backendOnline
                      ? '1. Create a task in the customer portal (Tasks → New Task)\n'
                        '2. Tap Poll & run below (works even before model is ready)\n'
                        '3. Install Qwen3 to execute inference on the device'
                      : 'Backend offline — run: adb reverse tcp:8081 tcp:8081',
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _controller.backendOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: _controller.backendOnline ? Colors.green : Colors.orange,
                  ),
                  title: const Text('Worker gateway'),
                  subtitle: Text(_controller.backendMessage),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment),
                  title: const Text('Last run status'),
                  subtitle: Text(
                    phase.name +
                        (_controller.executionStatus.taskType != null
                            ? ' · ${_controller.executionStatus.taskType}'
                            : '') +
                        (_controller.lastPortalTaskId != null
                            ? '\nTask: ${_controller.lastPortalTaskId}'
                            : ''),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _controller.canPollAssignments ? _runTaskWithGemma : null,
                  icon: const Icon(Icons.sync),
                  label: const Text('Poll & run next task'),
                ),
                if (_controller.backendOnline && !_controller.isGemmaReady) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Polling works now. Install Qwen3 (Home tab) to run the task on-device.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_controller.taskRunLogs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _taskRunLogPanel(context, _controller),
        ],
        if (_controller.executionStatus.detail != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Last result'),
              subtitle: Text(_controller.executionStatus.detail!),
            ),
          ),
        ],
      ],
    );
  }

  Widget _modelsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _modelCard(context, _controller, onDownload: _startGemmaDownload),
      ],
    );
  }

  Widget _placeholderTab(BuildContext context, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _taskRunLogPanel(BuildContext context, WorkerAppController controller) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Task run log', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            TextButton(
              onPressed: controller.clearTaskRunLogs,
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          controller.taskRunLogs.join('\n'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
        ),
      ],
    ),
  );
}

Widget _modelCard(
  BuildContext context,
  WorkerAppController controller, {
  required Future<void> Function() onDownload,
}) {
  final progressLabel = switch (controller.modelPhase) {
    ModelInstallPhase.idle => controller.usesDevMockInference
        ? 'Dev mock ready (x86)'
        : 'Not installed',
    ModelInstallPhase.downloading => 'Downloading ${(controller.modelProgress * 100).toStringAsFixed(0)}%',
    ModelInstallPhase.ready => controller.usesDevMockInference
        ? 'Dev mock ready (x86 emulator)'
        : 'Ready (qwen3-0.6b)',
    ModelInstallPhase.failed => controller.modelError ?? 'Install failed',
  };
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Qwen3 0.6B model', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(progressLabel),
          if (controller.modelPhase == ModelInstallPhase.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: controller.modelProgress),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: controller.canStartGemmaDownload && !controller.isGemmaReady ? onDownload : null,
              icon: Icon(controller.isGemmaReady ? Icons.check_circle : Icons.cloud_download),
              label: Text(controller.gemmaDownloadLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _readinessCard(BuildContext context, WorkerAppController controller) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device readiness', style: Theme.of(context).textTheme.titleMedium),
          _Status('Battery', controller.batteryLabel, Icons.battery_full),
          _Status('Temperature', controller.thermalLabel, Icons.thermostat),
          _Status('Backend', controller.backendOnline ? 'Online' : 'Offline', Icons.cloud),
          _Status('Storage', controller.storageLabel, Icons.storage),
          _Status(
            'Models',
            controller.modelPhase == ModelInstallPhase.ready ? 'Ready' : 'Pending',
            Icons.view_in_ar,
          ),
        ],
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ok = switch (value) {
      'Offline' || 'Pending' || 'Critical' || 'Throttled' => false,
      _ when value.contains('(emulator AC)') => true,
      _ => true,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value),
          const SizedBox(width: 8),
          Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? Colors.green : Colors.orange),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
