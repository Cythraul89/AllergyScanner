import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/utils/app_version.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static final Uri _openFoodFactsUri = Uri.parse('https://openfoodfacts.org');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppVersion version = ref.watch(appVersionProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('AllergyScanner', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Version ${version.display}'),
          const SizedBox(height: 24),

          Text('Not a medical device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'This app matches text against the terms you enter. It does not '
            'decide whether a product is safe for you to eat. Product data is '
            'crowd-sourced and unverified, recognised text can be wrong, and '
            'only the exact words you list are found. Always read the '
            'packaging.',
          ),
          const SizedBox(height: 24),

          Text('Data source', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Product data comes from Open Food Facts and is licensed by them '
            'under the Open Database License (ODbL).',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => launchUrl(_openFoodFactsUri),
            child: const Text('openfoodfacts.org'),
          ),
          const SizedBox(height: 8),
          Text(
            'Requests identify this app as '
            'AllergyScanner/${version.version} ($kAppContactEmail).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          Text('Licence', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'AllergyScanner is free software under the GNU General Public '
            'License, version 3. It comes with absolutely no warranty.',
          ),
          const SizedBox(height: 24),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/privacy'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('App logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Open source licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'AllergyScanner',
              applicationVersion: version.display,
            ),
          ),
        ],
      ),
    );
  }
}
