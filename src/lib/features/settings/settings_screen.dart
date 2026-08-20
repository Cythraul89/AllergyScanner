import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_settings.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';

/// Ingredient languages offered for the Open Food Facts lookup. Kept short on
/// purpose — the generic `ingredients_text` is the fallback for everything else.
const Map<String, String> kIngredientLanguages = <String, String>{
  'en': 'English',
  'de': 'German',
  'fr': 'French',
  'it': 'Italian',
  'es': 'Spanish',
  'nl': 'Dutch',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(currentSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('APPEARANCE'),
          ListTile(
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              onChanged: (ThemeMode? mode) {
                if (mode != null) {
                  ref.read(settingsDaoProvider).setThemeMode(mode);
                }
              },
              items: const <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
          ),

          const _SectionHeader('SCANNING'),
          ListTile(
            title: const Text('Preferred ingredient language'),
            subtitle: const Text('Used when a product has several languages'),
            trailing: DropdownButton<String>(
              value: kIngredientLanguages.containsKey(
                    settings.preferredIngredientsLanguage,
                  )
                  ? settings.preferredIngredientsLanguage
                  : 'en',
              onChanged: (String? language) {
                if (language != null) {
                  ref.read(settingsDaoProvider).setPreferredLanguage(language);
                }
              },
              items: kIngredientLanguages.entries
                  .map(
                    (MapEntry<String, String> entry) =>
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                  )
                  .toList(growable: false),
            ),
          ),
          SwitchListTile(
            title: const Text('Look up products online'),
            subtitle: const Text(
              'Off = no network requests at all; only locally stored products '
              'are checked',
            ),
            value: settings.remoteLookupEnabled,
            // Targeted column write — never a whole cached settings object.
            onChanged: (bool value) =>
                ref.read(settingsDaoProvider).setRemoteLookupEnabled(value),
          ),

          const _SectionHeader('DATA'),
          ListTile(
            title: const Text('Local backup'),
            subtitle: const Text('Export or import a ZIP archive'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/backup'),
          ),
          ListTile(
            title: const Text('Nextcloud sync'),
            subtitle: Text(
              settings.isSyncConfigured
                  ? settings.lastSyncAt == null
                        ? 'Configured'
                        : 'Last sync ${Formatters.dateTime(settings.lastSyncAt!)}'
                  : 'Not set',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/sync'),
          ),

          const _SectionHeader('ABOUT'),
          ListTile(
            title: const Text('About AllergyScanner'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about'),
          ),
          ListTile(
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/privacy'),
          ),
          ListTile(
            title: const Text('App logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
