import 'package:flutter/material.dart';

import '../models/worker_model_catalog.dart';

enum ModelUpdatePromptResult { update, later }

/// Shown when Gemma is missing, including while an app update card is up.
Future<ModelUpdatePromptResult?> showModelUpdatePromptDialog(
  BuildContext context,
) {
  final modelName = WorkerModelCatalog.displayName;
  return showDialog<ModelUpdatePromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Text('Download $modelName'),
        content: Text(
          '$modelName is not on this phone yet. '
          'Download it before this device can run tasks.',
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
            child: const Text('Download'),
          ),
        ],
      );
    },
  );
}
