import 'package:flutter/material.dart';

/// Collects an optional Hugging Face token before starting a gated model download.
Future<String?> showGemmaDownloadDialog(
  BuildContext context, {
  required bool tokenRequired,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Download Gemma 3n'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The full gemma-3n-e2b-int4 model (~1–2 GB) will be downloaded from Hugging Face and installed on this device.',
            ),
            if (tokenRequired) ...[
              const SizedBox(height: 16),
              const Text(
                'Accept the Gemma license on huggingface.co, then paste a Read token below.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Hugging Face token',
                  hintText: 'hf_…',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final token = controller.text.trim();
              if (tokenRequired && token.isEmpty) {
                return;
              }
              Navigator.of(context).pop(tokenRequired ? token : null);
            },
            child: const Text('Download now'),
          ),
        ],
      );
    },
  );
}
