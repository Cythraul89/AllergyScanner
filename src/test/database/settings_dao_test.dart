import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/app_settings.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = openTestDatabase());
  tearDown(() => database.close());

  test('serves defaults while no row exists, and reading writes nothing',
      () async {
    final AppSettings settings = await database.settingsDao.get();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.remoteLookupEnabled, isTrue);
    expect(settings.disclaimerAcknowledged, isFalse);
    expect(settings.preferredIngredientsLanguage, 'en');

    // A read must not create the row — otherwise ensureDefaults could never
    // set the device language.
    expect(await database.select(database.settingsEntries).get(), isEmpty);
  });

  test('ensureDefaults sets the device language once', () async {
    await database.settingsDao.ensureDefaults(deviceLanguage: 'de');
    expect(
      (await database.settingsDao.get()).preferredIngredientsLanguage,
      'de',
    );

    // A second call must not overwrite a language the user chose meanwhile.
    await database.settingsDao.setPreferredLanguage('fr');
    await database.settingsDao.ensureDefaults(deviceLanguage: 'de');
    expect(
      (await database.settingsDao.get()).preferredIngredientsLanguage,
      'fr',
    );
  });

  test('a setter creates the row when it does not exist yet', () async {
    await database.settingsDao.setThemeMode(ThemeMode.dark);

    expect((await database.settingsDao.get()).themeMode, ThemeMode.dark);
    expect(await database.select(database.settingsEntries).get(), hasLength(1));
  });

  test('writes are column-scoped and do not clobber other fields', () async {
    await database.settingsDao.setThemeMode(ThemeMode.dark);
    await database.settingsDao.setPreferredLanguage('it');
    await database.settingsDao.setRemoteLookupEnabled(false);
    await database.settingsDao.setWebdav(
      baseUrl: 'https://cloud.example.org/dav/',
      username: 'me',
    );

    final AppSettings settings = await database.settingsDao.get();
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.preferredIngredientsLanguage, 'it');
    expect(settings.remoteLookupEnabled, isFalse);
    expect(settings.webdavBaseUrl, 'https://cloud.example.org/dav/');
    expect(settings.isSyncConfigured, isTrue);
  });

  test('acknowledging the disclaimer is persisted', () async {
    await database.settingsDao.acknowledgeDisclaimer(testTimestamp);
    final AppSettings settings = await database.settingsDao.get();
    expect(settings.disclaimerAcknowledged, isTrue);
    // Drift returns DateTimeColumn values in local time; DateTime.== also
    // compares the UTC/local flag, so normalise before comparing an instant.
    expect(settings.disclaimerAcknowledgedAt?.toUtc(), testTimestamp);
  });

  test('the settings row never holds a password field', () async {
    await database.settingsDao.setWebdav(
      baseUrl: 'https://cloud.example.org/dav/',
      username: 'me',
      certificateFingerprint: 'ab12',
    );

    final Map<String, Object?> row = (await database
            .select(database.settingsEntries)
            .get())
        .single
        .toJson();
    expect(
      row.keys.where(
        (String key) => key.toLowerCase().contains('password'),
      ),
      isEmpty,
    );
  });

  test('watch emits the current values', () async {
    await database.settingsDao.setThemeMode(ThemeMode.light);
    expect((await database.settingsDao.watch().first).themeMode,
        ThemeMode.light);
  });

  test('clearing the connection removes url, user and last sync', () async {
    await database.settingsDao.setWebdav(
      baseUrl: 'https://cloud.example.org/dav/',
      username: 'me',
    );
    await database.settingsDao.setLastSyncAt(testTimestamp);

    await database.settingsDao.setWebdav();
    await database.settingsDao.setLastSyncAt(null);

    final AppSettings settings = await database.settingsDao.get();
    expect(settings.webdavBaseUrl, isNull);
    expect(settings.webdavUsername, isNull);
    expect(settings.lastSyncAt, isNull);
    expect(settings.isSyncConfigured, isFalse);
  });
}
