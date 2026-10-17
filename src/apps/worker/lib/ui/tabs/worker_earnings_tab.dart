import 'package:flutter/material.dart';

import '../../runtime/worker_payout_wallet_store.dart';
import '../../worker_app_controller.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';

class WorkerEarningsTab extends StatelessWidget {
  const WorkerEarningsTab({super.key, required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final horizontal = wide ? 24.0 : 16.0;

    final balance = const _BalancePanel();
    final wallets = _PayoutWalletsPanel(controller: controller, wide: wide);

    return ListView(
      padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
      children: [
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: balance),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: wallets),
              ],
            ),
          )
        else ...[
          balance,
          const SizedBox(height: 16),
          wallets,
        ],
        if (controller.payoutWalletNotice != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.payoutWalletNotice!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: controller.payoutWalletNoticeIsError
                  ? WorkerColors.error
                  : WorkerColors.success,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Available',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '€0.00',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: WorkerColors.primary,
                ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'No settled payout is loaded from the server.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Task rewards are variable in EUR and are not guaranteed.',
            style: TextStyle(
              color: WorkerColors.dim,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutWalletsPanel extends StatelessWidget {
  const _PayoutWalletsPanel({
    required this.controller,
    required this.wide,
  });

  final WorkerAppController controller;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final wallets = controller.payoutWallets;
    final loading = controller.payoutWalletsLoading;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _WalletsHeader()),
                const SizedBox(width: 12),
                _AddWalletButton(controller: controller),
              ],
            )
          else ...[
            const _WalletsHeader(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _AddWalletButton(controller: controller),
            ),
          ],
          const SizedBox(height: 20),
          if (loading && wallets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (wallets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: WorkerColors.surfaceDim,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WorkerColors.outlineVariant),
              ),
              child: const Text(
                'No payout wallet yet. Add one to prepare for rewards.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WorkerColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            )
          else
            ...wallets.map(
              (wallet) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WalletTile(
                  wallet: wallet,
                  onRemove: () => controller.removePayoutWallet(wallet.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WalletsHeader extends StatelessWidget {
  const _WalletsHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payout wallets',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Where EUR task rewards should be sent. Saved encrypted on this device '
          'until server registration is connected.',
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

class _AddWalletButton extends StatelessWidget {
  const _AddWalletButton({required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: controller.payoutWalletsLoading
          ? null
          : () => _openAddWalletSheet(context, controller),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add wallet'),
    );
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile({required this.wallet, required this.onRemove});

  final WorkerPayoutWalletRecord wallet;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WorkerColors.surfaceDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkerColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: WorkerColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: WorkerColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  wallet.kind.label,
                  style: const TextStyle(
                    color: WorkerColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  wallet.maskedDestination,
                  style: const TextStyle(
                    color: WorkerColors.brandLine,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                const WorkerStatusChip(label: 'Device only', active: false),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove wallet',
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline,
              color: WorkerColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openAddWalletSheet(
  BuildContext context,
  WorkerAppController controller,
) async {
  final labelController = TextEditingController();
  final destinationController = TextEditingController();
  var kind = WorkerPayoutWalletKind.cryptoUsdtTrc20;
  String? errorText;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WorkerColors.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add payout wallet',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<WorkerPayoutWalletKind>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Wallet type'),
                  items: WorkerPayoutWalletKind.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => kind = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'Main payout wallet',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: destinationController,
                  decoration: InputDecoration(
                    labelText: switch (kind) {
                      WorkerPayoutWalletKind.cryptoUsdtTrc20 => 'TRC20 address',
                      WorkerPayoutWalletKind.ibanEur => 'IBAN',
                      WorkerPayoutWalletKind.other => 'Payout destination',
                    },
                    hintText: switch (kind) {
                      WorkerPayoutWalletKind.cryptoUsdtTrc20 => 'T…',
                      WorkerPayoutWalletKind.ibanEur => 'DE…',
                      WorkerPayoutWalletKind.other => 'Account or address',
                    },
                  ),
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: WorkerColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final destination = destinationController.text.trim();
                    final label = labelController.text.trim();
                    final problem = await controller.addPayoutWallet(
                      kind: kind,
                      destination: destination,
                      label: label.isEmpty ? kind.label : label,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    if (problem != null) {
                      setSheetState(() => errorText = problem);
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Save on this device'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This does not register the wallet with FibonAI servers yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WorkerColors.dim, fontSize: 11),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  labelController.dispose();
  destinationController.dispose();
}
