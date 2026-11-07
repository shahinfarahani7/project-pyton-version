import 'package:flutter/material.dart';

import '../models/worker_model_catalog.dart';

enum ModelUpdatePromptResult { update, later }

/// Shown on Home when the on-device model is not installed yet.
Future<ModelUpdatePromptResult?> showModelUpdatePromptDialog(
  BuildContext context,
) {
  return showDialog<ModelUpdatePromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Download model'),
        content: Text(
          'Download the on-device model (${WorkerModelCatalog.approximateDownloadSize}) '
          'to run tasks on this device.',
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
