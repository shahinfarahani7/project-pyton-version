import 'package:flutter/material.dart';

import '../worker_theme.dart';
import '../worker_widgets.dart';

class WorkerPlaceholderTab extends StatelessWidget {
  const WorkerPlaceholderTab({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: workerPanelDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: WorkerColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: WorkerColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: WorkerColors.onSurfaceVariant, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkerProfileTab extends StatelessWidget {
  const WorkerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkerPlaceholderTab(
      title: 'Profile',
      message: 'Worker profile settings will appear here.',
      icon: Icons.person_outline,
    );
  }
}

class WorkerEarningsTab extends StatelessWidget {
  const WorkerEarningsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const WorkerPlaceholderTab(
      title: 'Earnings',
      message: 'Payout history will appear here.',
      icon: Icons.account_balance_wallet_outlined,
    );
  }
}
