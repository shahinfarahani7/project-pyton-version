import 'package:flutter/material.dart';

import 'runtime/gemma_bootstrap.dart';
import 'ui/gemma_download_dialog.dart';
import 'ui/tabs/worker_home_tab.dart';
import 'ui/tabs/worker_missions_tab.dart';
import 'ui/tabs/worker_models_tab.dart';
import 'ui/tabs/worker_placeholder_tab.dart';
import 'ui/worker_shell.dart';
import 'ui/worker_theme.dart';
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
      theme: buildWorkerTheme(),
      home: const WorkerHomePage(),
    );
  }
}

class WorkerHomePage extends StatefulWidget {
  const WorkerHomePage({super.key});

  @override
  State<WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<WorkerHomePage> with WidgetsBindingObserver {
  late final WorkerAppController _controller;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _setAvailability(bool value) {
    _controller.setAvailable(value);
  }

  void _navigateTo(int index) {
    setState(() => _selectedNavIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return WorkerShell(
      selectedIndex: _selectedNavIndex,
      onNavChanged: _navigateTo,
      onRefresh: _controller.bootstrap,
      available: _controller.available,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (_selectedNavIndex) {
            0 => WorkerHomeTab(
                key: const ValueKey('home'),
                controller: _controller,
                onDownloadModel: _startGemmaDownload,
                onAvailabilityChanged: _setAvailability,
                onNavigate: _navigateTo,
              ),
            1 => WorkerMissionsTab(
                key: const ValueKey('missions'),
                controller: _controller,
              ),
            2 => WorkerModelsTab(
                key: const ValueKey('models'),
                controller: _controller,
                onDownload: _startGemmaDownload,
              ),
            3 => const WorkerEarningsTab(key: ValueKey('earnings')),
            _ => const WorkerProfileTab(key: ValueKey('profile')),
          },
        ),
      ),
    );
  }
}
