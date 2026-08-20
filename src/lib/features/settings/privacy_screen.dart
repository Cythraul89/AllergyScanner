import 'package:flutter/material.dart';

/// In-app mirror of `PRIVACY.md`. When one changes, the other changes with it.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('No account, no telemetry', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'AllergyScanner has no accounts and no login. It contains no '
            'analytics, no crash reporting service, no advertising and no '
            'tracking identifiers.',
          ),
          const SizedBox(height: 24),

          Text('Stored on this device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Your allergy terms, the products you scanned, your scan history '
            '(the last 500 checks) and your settings, in a database inside the '
            "app's private storage. A diagnostic log file, viewable under "
            'Settings → App logs. If you configure sync, the WebDAV password '
            'in the platform key store — never in the database, the log or a '
            'backup archive.',
          ),
          const SizedBox(height: 24),

          Text('What leaves the device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '•  The barcode digits, sent to Open Food Facts — only for a '
            'product that is not already stored locally, and only while '
            '"Look up products online" is on.\n'
            '•  A backup archive, sent to your own Nextcloud/WebDAV server — '
            'only if you configured sync.\n'
            '•  Anything you explicitly share.\n\n'
            'Your allergy terms and your history are never sent to Open Food '
            'Facts or to any other third party.',
          ),
          const SizedBox(height: 24),

          Text('Camera and photos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Barcode detection and text recognition both run on this device. '
            'No image is uploaded. A photo taken for text recognition is '
            'written to a temporary file, processed, and deleted immediately '
            'afterwards; only the recognised text — which you can edit — is '
            'stored, as part of the scan history.',
          ),
          const SizedBox(height: 24),

          Text('Your control', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Delete a single check, clear the whole history, delete any term, '
            'export everything as a ZIP archive, switch online lookup off '
            'entirely, or uninstall the app to remove all of it.',
          ),
        ],
      ),
    );
  }
}
