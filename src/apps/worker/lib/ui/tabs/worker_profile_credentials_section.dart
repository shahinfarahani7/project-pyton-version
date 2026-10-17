import 'package:flutter/material.dart';

import '../../worker_app_controller.dart';
import '../worker_theme.dart';
import '../worker_widgets.dart';

class WorkerProfileCredentialsSection extends StatelessWidget {
  const WorkerProfileCredentialsSection({super.key, required this.controller});

  final WorkerAppController controller;

  Future<void> _openChangePasswordDialog(BuildContext context) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var obscure = true;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Passwords are never saved on this device. '
                      'Your account server must confirm the change.',
                      style: TextStyle(
                        color: WorkerColors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: currentController,
                      obscureText: obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Current password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newController,
                      obscureText: obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'New password (12+ characters)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    String? message;
    if (submitted == true) {
      message = await controller.requestPasswordChange(
        currentPassword: currentController.text,
        newPassword: newController.text,
        confirmPassword: confirmController.text,
      );
    }

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();

    if (!context.mounted || message == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: WorkerColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = controller.accountProfile;
    final username = profile?.username.trim();
    final email = profile?.email.trim();
    final usernameDisplay =
        username != null && username.isNotEmpty ? username : 'Not set';
    final emailDisplay = email != null && email.isNotEmpty
        ? profile!.maskedEmail
        : 'Not set';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: workerPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          _InfoRow(label: 'Username', value: usernameDisplay),
          _InfoRow(label: 'Email', value: emailDisplay),
          const Divider(height: 28),
          const Text(
            'Password',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Managed by the worker account server when connected. '
            'Passwords are never stored on this device.',
            style: TextStyle(
              color: WorkerColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _openChangePasswordDialog(context),
            child: const Text('Change password'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: WorkerColors.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
