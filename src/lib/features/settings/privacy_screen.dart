import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// In-app mirror of `PRIVACY.md`. When one changes, the other changes with it.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPrivacyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            l10n.privacyNoAccountHeading,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.privacyNoAccountText),
          const SizedBox(height: 24),

          Text(l10n.privacyStoredHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.privacyStoredText),
          const SizedBox(height: 24),

          Text(l10n.privacyLeavesHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.privacyLeavesText),
          const SizedBox(height: 24),

          Text(l10n.privacyCameraHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.privacyCameraText),
          const SizedBox(height: 24),

          Text(l10n.privacyControlHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.privacyControlText),
        ],
      ),
    );
  }
}
