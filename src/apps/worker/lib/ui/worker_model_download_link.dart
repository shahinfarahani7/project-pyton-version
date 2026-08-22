import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/worker_model_catalog.dart';
import 'worker_theme.dart';

/// Shows a tappable model download URL for mobile sideload / browser download.
class WorkerModelDownloadLink extends StatelessWidget {
  const WorkerModelDownloadLink({
    super.key,
    required this.url,
  });

  final String url;

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open download link')),
      );
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download link copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WorkerColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkerColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Direct download link',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: WorkerColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${WorkerModelCatalog.displayName} · ${WorkerModelCatalog.approximateDownloadSize}',
            style: const TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SelectableText(
            url,
            style: const TextStyle(
              color: WorkerColors.primary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _openInBrowser(context),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Open in browser'),
              ),
              TextButton.icon(
                onPressed: () => _copyLink(context),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy link'),
              ),
            ],
          ),
          const Text(
            'Save to Downloads, then open Models and tap Prepare — or sideload from PC.',
            style: TextStyle(color: WorkerColors.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
