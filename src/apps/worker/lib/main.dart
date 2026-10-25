import 'dart:async';

import 'package:flutter/material.dart';

import 'runtime/gemma_bootstrap.dart';
import 'ui/gemma_download_dialog.dart';
import 'ui/tabs/worker_home_tab.dart';
import 'ui/tabs/worker_missions_tab.dart';
import 'ui/tabs/worker_earnings_tab.dart';
import 'ui/tabs/worker_profile_tab.dart';
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
      title: 'FibonAI Worker',
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

class _WorkerHomePageState extends State<WorkerHomePage>
    with WidgetsBindingObserver {
  WorkerAppController? _controller;
  int _selectedNavIndex = 0;
  bool _modelUpdatePromptOpen = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowModelUpdatePrompt());
    });
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

  Future<void> _runGemmaDownload() async {
    final controller = _controller;
    if (controller == null ||
        !controller.canStartGemmaDownload ||
        controller.isGemmaReady) {
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

  Future<void> _maybeShowModelUpdatePrompt() async {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        _selectedNavIndex != 0 ||
        _modelUpdatePromptOpen) {
      return;
    }
    if (controller.isGemmaReady ||
        controller.isGemmaDownloading ||
        controller.isGemmaDownloadPaused) {
      return;
    }

    _modelUpdatePromptOpen = true;
    final result = await showModelUpdatePromptDialog(context);
    _modelUpdatePromptOpen = false;
    if (!mounted) {
      return;
    }
    if (result == ModelUpdatePromptResult.update) {
      await _runGemmaDownload();
    }
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

  void _navigateTo(int index) {
    setState(() => _selectedNavIndex = index);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowModelUpdatePrompt());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            ),
            1 => WorkerMissionsTab(
              key: const ValueKey('missions'),
              controller: controller,
              onNavigate: _navigateTo,
            ),
            2 => WorkerEarningsTab(
              key: const ValueKey('earnings'),
              controller: controller,
            ),
            _ => WorkerProfileTab(
              key: const ValueKey('profile'),
              controller: controller,
            ),
          },
        ),
      ),
    );
  }
}
