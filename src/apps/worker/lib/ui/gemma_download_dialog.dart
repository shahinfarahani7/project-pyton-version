import 'package:flutter/material.dart';

/// Confirms a large model download before starting (no Hugging Face token required).
Future<bool?> showGemmaDownloadDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Download Qwen3 0.6B'),
        content: const Text(
          'The Qwen3-0.6B model (~586 MB) can be downloaded from your EdgeMint backend, '
          'or sideloaded from PC with tools/push_qwen_model_to_emulator.ps1 (no in-app download).',
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
