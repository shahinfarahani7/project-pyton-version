import 'package:flutter/material.dart';

/// Confirms a large model download before starting (no Hugging Face token required).
Future<bool?> showGemmaDownloadDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Download Qwen3 0.6B'),
        content: const Text(
          'The Qwen3-0.6B model (~586 MB) will be downloaded from your EdgeMint worker backend and installed on this device. No Hugging Face token is required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download now'),
          ),
        ],
      );
    },
  );
}
