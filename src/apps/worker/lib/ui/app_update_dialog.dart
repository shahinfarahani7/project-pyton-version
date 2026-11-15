import 'package:flutter/material.dart';

enum AppUpdatePromptResult { update }

/// Modal shown when the worker server publishes a newer app build.
/// The Update button is the same install path as the home-screen card.
Future<AppUpdatePromptResult?> showAppUpdatePromptDialog(
  BuildContext context, {
  required String versionName,
  String? notes,
  required bool mandatory,
}) {
  final detail = (notes ?? '').trim();
  return showDialog<AppUpdatePromptResult>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (context) {
      return PopScope(
        canPop: !mandatory,
        child: AlertDialog(
          title: Text(mandatory ? 'Required app update' : 'App update'),
          content: Text(
            detail.isEmpty
                ? 'Version $versionName is ready. Install it on this phone to continue.'
                : 'Version $versionName\n\n$detail',
          ),
          actions: [
            if (!mandatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(AppUpdatePromptResult.update),
              child: const Text('Update app'),
            ),
          ],
        ),
      );
    },
  );
}
