import 'package:flutter/material.dart';

enum ModelUpdatePromptResult { update, later }

/// Shown on Home when work cannot start until the required download finishes.
Future<ModelUpdatePromptResult?> showModelUpdatePromptDialog(
  BuildContext context,
) {
  return showDialog<ModelUpdatePromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Update required'),
        content: const Text(
          'An update is required before this device can run tasks.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(ModelUpdatePromptResult.later),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(ModelUpdatePromptResult.update),
            child: const Text('Update'),
          ),
        ],
      );
    },
  );
}
