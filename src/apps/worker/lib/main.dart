import 'package:flutter/material.dart';

import 'ui/gemma_download_dialog.dart';
import 'worker_app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  Future<void> _startGemmaDownload() async {
    if (!_controller.canStartGemmaDownload || _controller.isGemmaReady) {
      return;
    }

    String? token;
    if (_controller.requiresHuggingFaceToken) {
      token = await showGemmaDownloadDialog(context, tokenRequired: true);
      if (!mounted || token == null || token.isEmpty) {
        return;
      }
    }

    await _controller.downloadGemmaModel(huggingFaceToken: token);
    if (!mounted || _controller.modelPhase != ModelInstallPhase.failed) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_controller.modelError ?? 'Gemma download failed')),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EdgeMint'),
        actions: [
          IconButton(
            onPressed: _controller.bootstrap,
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh',
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Missions'),
          NavigationDestination(icon: Icon(Icons.view_in_ar_outlined), label: 'Models'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
      body: SafeArea(
        child: ListView(
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
                    if (_controller.isGemmaDownloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _controller.modelProgress),
                      const SizedBox(height: 8),
                      Text(
                        _controller.gemmaDownloadLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ] else if (!_controller.isGemmaReady) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _controller.canStartGemmaDownload ? _startGemmaDownload : null,
                        icon: const Icon(Icons.download_for_offline),
                        label: Text(_controller.gemmaDownloadLabel),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      if (_controller.modelPhase == ModelInstallPhase.failed &&
                          _controller.modelError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _controller.modelError!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_controller.gemmaDownloadLabel)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _controller.isGemmaDownloading || !_controller.isGemmaReady
                          ? null
                          : _controller.pollAndRunTask,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Run task with Gemma'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _readinessCard(context, _controller),
            const SizedBox(height: 12),
            _modelCard(context, _controller, onDownload: _startGemmaDownload),
            if (_controller.executionStatus.detail != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Last inference'),
                  subtitle: Text(_controller.executionStatus.detail!),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Earnings summary', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Metric('Estimated', '€0.018'),
                        _Metric('Pending', '€2.40'),
                        _Metric('Verified', '€18.75'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Center(child: Text('Last sync ${_controller.lastSync}')),
          ],
        ),
      ),
    );
  }
}

Widget _modelCard(
  BuildContext context,
  WorkerAppController controller, {
  required Future<void> Function() onDownload,
}) {
  final progressLabel = switch (controller.modelPhase) {
    ModelInstallPhase.idle => 'Not installed',
    ModelInstallPhase.downloading => 'Downloading ${(controller.modelProgress * 100).toStringAsFixed(0)}%',
    ModelInstallPhase.ready => 'Ready (gemma-3n-e2b-int4)',
    ModelInstallPhase.failed => controller.modelError ?? 'Install failed',
  };
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gemma 3n model', style: Theme.of(context).textTheme.titleMedium),
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
          const _Status('Battery', '78%', Icons.battery_full),
          const _Status('Temperature', 'Normal', Icons.thermostat),
          _Status('Backend', controller.backendOnline ? 'Online' : 'Offline', Icons.cloud),
          const _Status('Storage', '12 GB free', Icons.storage),
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
    final ok = value == 'Offline' || value == 'Pending' ? false : true;
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
