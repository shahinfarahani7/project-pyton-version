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
  WorkerAppController? _controller;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  Future<void> _initController() async {
    final controller = await WorkerAppController.create();
    controller.addListener(_onControllerChanged);
    await controller.bootstrap();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  WorkerAppController get _activeController {
    final controller = _controller;
    if (controller == null) {
      throw StateError('Worker controller is not ready');
    }
    return controller;
  }

  Future<void> _startGemmaDownload() async {
    final controller = _controller;
    if (controller == null ||
        !controller.canStartGemmaDownload ||
        controller.isGemmaReady) {
      return;
    }

    final confirmed = await showGemmaDownloadDialog(context);
    if (!mounted || confirmed != true) {
      return;
    }

    await controller.downloadGemmaModel();
    if (!mounted || controller.modelPhase != ModelInstallPhase.failed) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(controller.modelError ?? 'Model download failed')),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller?.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _setAvailability(bool value) {
    _activeController.setAvailable(value);
  }

  void _navigateTo(int index) {
    setState(() => _selectedNavIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WorkerShell(
      selectedIndex: _selectedNavIndex,
      onNavChanged: _navigateTo,
      onRefresh: controller.bootstrap,
      available: controller.available,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (_selectedNavIndex) {
            0 => WorkerHomeTab(
                key: const ValueKey('home'),
                controller: controller,
                onDownloadModel: _startGemmaDownload,
                onAvailabilityChanged: _setAvailability,
                onNavigate: _navigateTo,
              ),
            1 => WorkerMissionsTab(
                key: const ValueKey('missions'),
                controller: controller,
              ),
            2 => WorkerModelsTab(
                key: const ValueKey('models'),
                controller: controller,
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
