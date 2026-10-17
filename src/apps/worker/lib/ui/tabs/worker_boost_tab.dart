import 'package:flutter/material.dart';

import '../worker_theme.dart';

class WorkerBoostTab extends StatelessWidget {
  const WorkerBoostTab({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 24),
      children: [
        const _UptimeBoosterPanel(),
        const SizedBox(height: 16),
        const Text(
          'Uptime level progress is on Missions and Home. Booster purchases and '
          'token rewards are confirmed only when connected to FibonAI servers.',
          style: TextStyle(
            color: WorkerColors.onSurfaceVariant,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _UptimeBoosterPanel extends StatelessWidget {
  const _UptimeBoosterPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uptime Booster',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Speed up verified uptime level progress when purchase is enabled on the server.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.bolt_outlined, color: WorkerColors.dim, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Purchase',
                  style: TextStyle(color: WorkerColors.onSurface, fontSize: 13),
                ),
              ),
              FilledButton(onPressed: null, child: Text('Activate Booster')),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Booster purchase is not connected yet.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
