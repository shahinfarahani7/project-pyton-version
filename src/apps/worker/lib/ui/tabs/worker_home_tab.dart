import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../runtime/execution_status.dart';
import '../../worker_app_controller.dart';
import '../worker_nav_index.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';
import 'worker_models_tab.dart';
class WorkerHomeTab extends StatefulWidget {
  const WorkerHomeTab({
    super.key,
    required this.controller,
    required this.onDownloadModel,
    required this.onNavigate,
  });

  final WorkerAppController controller;

  /// Shell contract. Model download also lives on the Profile tab.
  final VoidCallback onDownloadModel;

  /// Shell contract. Other tabs stay on the existing navigation bar.
  final ValueChanged<int> onNavigate;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ObjectFlagProperty.has('onDownloadModel', onDownloadModel))
      ..add(ObjectFlagProperty.has('onNavigate', onNavigate));
  }

  @override
  State<WorkerHomeTab> createState() => _WorkerHomeTabState();
}

class _WorkerHomeTabState extends State<WorkerHomeTab> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 24),
      children: [
        _WorkerCharacter(
          working: _hasActiveTask(controller.executionStatus.phase),
        ),
        const SizedBox(height: 16),
        _HomeStatRow(tasksCompleted: controller.tasksProcessed),
        const SizedBox(height: 16),
        _HomeModelSection(
          controller: controller,
          onDownloadModel: widget.onDownloadModel,
          onOpenProfile: () => widget.onNavigate(WorkerNavIndex.profile),
        ),
        const SizedBox(height: 16),
        const _EarningsChart(),
      ],
    );
  }
}

bool _hasActiveTask(ExecutionPhase phase) => switch (phase) {
  ExecutionPhase.preparing ||
  ExecutionPhase.running ||
  ExecutionPhase.checkpointing ||
  ExecutionPhase.submitting ||
  ExecutionPhase.cleaningUp => true,
  ExecutionPhase.idle ||
  ExecutionPhase.waitingForAssignment ||
  ExecutionPhase.paused ||
  ExecutionPhase.failed ||
  ExecutionPhase.completed => false,
};

class _WorkerCharacter extends StatelessWidget {
  const _WorkerCharacter({required this.working});

  final bool working;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Center(
        child: _CharacterLoop(
          key: ValueKey(working),
          folder: working ? 'working' : 'idle',
          semanticLabel: working
              ? 'Worker character running a task'
              : 'Worker character waiting for a task',
        ),
      ),
    );
  }
}

/// Frame loop cut from the 5-second seamless character video (40 frames).
class _CharacterLoop extends StatefulWidget {
  const _CharacterLoop({
    super.key,
    required this.folder,
    required this.semanticLabel,
  });

  static const frameCount = 40;
  static const loop = Duration(milliseconds: 5042);

  final String folder;
  final String semanticLabel;

  @override
  State<_CharacterLoop> createState() => _CharacterLoopState();
}

class _CharacterLoopState extends State<_CharacterLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: _CharacterLoop.loop,
  )..repeat();
  var _precached = false;

  String _frame(int i) =>
      'assets/character/${widget.folder}/${i.toString().padLeft(2, '0')}.png';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (var i = 0; i < _CharacterLoop.frameCount; i++) {
      precacheImage(AssetImage(_frame(i)), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final index =
            (_ticker.value * _CharacterLoop.frameCount).floor() %
            _CharacterLoop.frameCount;
        return Image.asset(
          _frame(index),
          height: 220,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: widget.semanticLabel,
        );
      },
    );
  }
}

class _HomeModelSection extends StatelessWidget {
  const _HomeModelSection({
    required this.controller,
    required this.onDownloadModel,
    required this.onOpenProfile,
  });

  final WorkerAppController controller;
  final VoidCallback onDownloadModel;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'AI model',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(onPressed: onOpenProfile, child: const Text('Profile')),
          ],
        ),
        const SizedBox(height: 8),
        WorkerModelCard(controller: controller, onDownload: onDownloadModel),
      ],
    );
  }
}

class _HomeStatRow extends StatelessWidget {
  const _HomeStatRow({required this.tasksCompleted});

  final int tasksCompleted;

  /// No payout balance is loaded on the worker. Integer cents stay at zero.
  static const _balanceCents = 0;

  @override
  Widget build(BuildContext context) {
    final dollars = _balanceCents ~/ 100;
    final cents = (_balanceCents % 100).abs().toString().padLeft(2, '0');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatCard(label: 'Tasks completed', value: '$tasksCompleted'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'Balance', value: '\$$dollars.$cents'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: WorkerColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsChart extends StatelessWidget {
  const _EarningsChart();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'No settled payout is loaded. Rewards are variable and are not guaranteed.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          const WorkerLineChart(
            values: [0, 0, 0, 0, 0, 0, 0],
            color: WorkerColors.primary,
          ),
        ],
      ),
    );
  }
}

