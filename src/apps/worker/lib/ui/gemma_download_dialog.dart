import 'package:flutter/material.dart';

import '../models/worker_model_catalog.dart';

/// Confirms a large model download before starting.
Future<bool?> showGemmaDownloadDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Download model'),
        content: Text(
          'The on-device model (${WorkerModelCatalog.approximateDownloadSize}) '
          'will download over the network. Keep this device on Wi‑Fi and plugged in if possible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download model'),
          ),
        ],
      );
    },
  );
}
