import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/utils/app_version.dart';
import '../../l10n/app_localizations.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static final Uri _openFoodFactsUri = Uri.parse('https://openfoodfacts.org');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppVersion version = ref.watch(appVersionProvider);
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(l10n.appTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(l10n.aboutVersionLabel(version.display)),
          const SizedBox(height: 24),

          Text(
            l10n.aboutNotMedicalDeviceHeading,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.aboutMedicalDisclaimer),
          const SizedBox(height: 24),

          Text(l10n.aboutDataSourceHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.aboutDataSourceText),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => launchUrl(_openFoodFactsUri),
            child: const Text('openfoodfacts.org'),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.aboutUserAgentNote(version.version, kAppContactEmail),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          Text(l10n.aboutLicenceHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.aboutLicenceText),
          const SizedBox(height: 24),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsPrivacyTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/privacy'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsLogsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.aboutOpenSourceLicencesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: version.display,
            ),
          ),
        ],
      ),
    );
  }
}
