import 'dart:async';

import 'package:flutter/material.dart';

import 'runtime/gemma_bootstrap.dart';
import 'runtime/worker_app_update.dart';
import 'ui/app_update_dialog.dart';
import 'ui/fibonai_splash.dart';
import 'ui/worker_login_screen.dart';
import 'ui/gemma_download_dialog.dart';
import 'ui/worker_offline_dialog.dart';
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
  bool _modelDownloadPromptDismissed = false;
  bool _appUpdateDialogOpen = false;
  bool _splashDone = false;

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
      unawaited(_maybeShowAppUpdateDialog());
      unawaited(_maybeShowModelUpdatePrompt());
    });
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowAppUpdateDialog());
      unawaited(_maybeShowModelUpdatePrompt());
    });
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

  Future<void> _maybeShowAppUpdateDialog() async {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !_splashDone ||
        _appUpdateDialogOpen ||
        controller.isDeviceOffline ||
        controller.needsEmailSignIn ||
        !controller.showsAppUpdateCard) {
      return;
    }
    final phase = controller.appUpdatePhase;
    if (phase != WorkerAppUpdatePhase.available &&
        phase != WorkerAppUpdatePhase.failed) {
      return;
    }
    _appUpdateDialogOpen = true;
    final result = await showAppUpdatePromptDialog(
      context,
      versionName: controller.appUpdateVersionName ?? '',
      notes: controller.appUpdateNotes,
      mandatory: controller.appUpdateMandatory,
    );
    _appUpdateDialogOpen = false;
    if (!mounted || result != AppUpdatePromptResult.update) {
      return;
    }
    await controller.installOfferedAppUpdate();
  }

  Future<void> _maybeShowModelUpdatePrompt() async {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !_splashDone ||
        controller.isDeviceOffline ||
        controller.needsEmailSignIn ||
        _modelUpdatePromptOpen ||
        _modelDownloadPromptDismissed) {
      return;
    }
    if (!shouldShowUnpublishedModelDownloadPrompt(
      applicationUpdateOffered: controller.showsAppUpdateCard,
      modelUpdateOffered: controller.showsModelUpdateCard,
      modelReady: controller.isGemmaReady,
      modelTransferActive:
          controller.isGemmaDownloading || controller.isGemmaDownloadPaused,
    )) {
      return;
    }

    _modelUpdatePromptOpen = true;
    final result = await showModelUpdatePromptDialog(context);
    _modelUpdatePromptOpen = false;
    _modelDownloadPromptDismissed = true;
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
        unawaited(_maybeShowAppUpdateDialog());
        unawaited(_maybeShowModelUpdatePrompt());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !_splashDone) {
      return FibonaiSplashScreen(
        key: const ValueKey('fibonai-splash'),
        onFinished: () {
          if (mounted) {
            setState(() => _splashDone = true);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_maybeShowAppUpdateDialog());
            unawaited(_maybeShowModelUpdatePrompt());
          });
        },
      );
    }

    final offline = controller.isDeviceOffline;
    if (controller.needsEmailSignIn) {
      return WorkerOfflineGate(
        offline: offline,
        child: WorkerLoginScreen(controller: controller),
      );
    }

    final updateRequired = controller.blocksAppUntilUpdate;
    return WorkerOfflineGate(
      offline: offline,
      child: WorkerShell(
        selectedIndex: updateRequired ? 0 : _selectedNavIndex,
        onNavChanged: updateRequired || offline ? (_) {} : _navigateTo,
        onRefresh: () {
          if (!offline) {
            unawaited(controller.bootstrap());
          }
        },
        available: controller.available,
        lockNavigation: updateRequired,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: switch (updateRequired ? 0 : _selectedNavIndex) {
              0 => WorkerHomeTab(
                key: const ValueKey('home'),
                controller: controller,
              ),
              1 => WorkerMissionsTab(
                key: const ValueKey('missions'),
                controller: controller,
                onNavigate: offline ? (_) {} : _navigateTo,
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
      ),
    );
  }
}
