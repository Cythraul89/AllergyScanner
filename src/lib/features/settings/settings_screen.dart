import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_settings.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final Map<String, String> ingredientLanguages = <String, String>{
      'en': l10n.languageEnglish,
      'de': l10n.languageGerman,
      'fr': l10n.languageFrench,
      'it': l10n.languageItalian,
      'es': l10n.languageSpanish,
      'nl': l10n.languageDutch,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: <Widget>[
          _SectionHeader(l10n.settingsSectionAppearance),
          ListTile(
            title: Text(l10n.settingsThemeLabel),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              onChanged: (ThemeMode? mode) {
                if (mode != null) {
                  ref.read(settingsDaoProvider).setThemeMode(mode);
                }
              },
              items: <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.system,
                  child: Text(l10n.commonSystem),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.light,
                  child: Text(l10n.settingsThemeLight),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.dark,
                  child: Text(l10n.settingsThemeDark),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(l10n.settingsAppLanguageTitle),
            subtitle: Text(l10n.settingsAppLanguageSubtitle),
            trailing: DropdownButton<String?>(
              value: settings.appLanguage,
              onChanged: (String? language) =>
                  ref.read(settingsDaoProvider).setAppLanguage(language),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  child: Text(l10n.commonSystem),
                ),
                DropdownMenuItem<String?>(
                  value: 'en',
                  child: Text(l10n.languageEnglish),
                ),
                DropdownMenuItem<String?>(
                  value: 'de',
                  child: Text(l10n.languageGerman),
                ),
              ],
            ),
          ),

          _SectionHeader(l10n.settingsSectionScanning),
          ListTile(
            title: Text(l10n.settingsIngredientLanguageLabel),
            subtitle: Text(l10n.settingsIngredientLanguageSubtitle),
            trailing: DropdownButton<String>(
              value: ingredientLanguages.containsKey(
                    settings.preferredIngredientsLanguage,
                  )
                  ? settings.preferredIngredientsLanguage
                  : 'en',
              onChanged: (String? language) {
                if (language != null) {
                  ref.read(settingsDaoProvider).setPreferredLanguage(language);
                }
              },
              items: ingredientLanguages.entries
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
            title: Text(l10n.settingsRemoteLookupTitle),
            subtitle: Text(l10n.settingsRemoteLookupSubtitle),
            value: settings.remoteLookupEnabled,
            // Targeted column write — never a whole cached settings object.
            onChanged: (bool value) =>
                ref.read(settingsDaoProvider).setRemoteLookupEnabled(value),
          ),

          _SectionHeader(l10n.settingsSectionData),
          ListTile(
            title: Text(l10n.settingsBackupTitle),
            subtitle: Text(l10n.settingsBackupSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/backup'),
          ),
          ListTile(
            title: Text(l10n.settingsSyncTitle),
            subtitle: Text(
              settings.isSyncConfigured
                  ? settings.lastSyncAt == null
                        ? l10n.settingsSyncConfigured
                        : l10n.settingsSyncLastSync(
                            Formatters.dateTime(settings.lastSyncAt!),
                          )
                  : l10n.settingsSyncNotSet,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/sync'),
          ),

          _SectionHeader(l10n.settingsSectionAbout),
          ListTile(
            title: Text(l10n.settingsAboutTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about'),
          ),
          ListTile(
            title: Text(l10n.settingsPrivacyTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/privacy'),
          ),
          ListTile(
            title: Text(l10n.settingsLogsTitle),
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
