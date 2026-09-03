import 'dart:io';

import 'package:allergy_scanner/app.dart';
import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/providers.dart';
import 'package:allergy_scanner/core/services/backup_service.dart';
import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/open_food_facts_service.dart';
import 'package:allergy_scanner/core/services/scan_photo_service.dart';
import 'package:allergy_scanner/core/services/text_recognition_service.dart';
import 'package:allergy_scanner/core/services/translation_service.dart';
import 'package:allergy_scanner/core/services/webdav_service.dart';
import 'package:allergy_scanner/core/utils/app_version.dart';
import 'package:allergy_scanner/core/utils/formatters.dart';
import 'package:allergy_scanner/core/utils/scan_capabilities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

import 'database/test_database.dart';

/// Every provider that would otherwise open a socket, a file or a platform
/// channel is overridden — a missing override throws by design, which is what
/// makes this test meaningful.
List<Override> overridesFor(
  AppDatabase database,
  LogService log,
  ScanPhotoService scanPhotos,
) {
  final Dio dio = Dio();
  return <Override>[
    appDatabaseProvider.overrideWithValue(database),
    logServiceProvider.overrideWithValue(log),
    dioProvider.overrideWithValue(dio),
    appVersionProvider.overrideWithValue(const AppVersion.unknown()),
    // No camera in a widget test, so no camera route is registered either.
    scanCapabilitiesProvider.overrideWithValue(
      const ScanCapabilities.none(),
    ),
    openFoodFactsServiceProvider.overrideWithValue(
      OpenFoodFactsService(dio: dio, log: log),
    ),
    textRecognitionServiceProvider.overrideWithValue(
      const UnsupportedTextRecognitionService(),
    ),
    backupServiceProvider.overrideWithValue(
      BackupService(database: database, log: log, scanPhotos: scanPhotos),
    ),
    webdavServiceProvider.overrideWithValue(WebdavService(log: log)),
    translationServiceProvider.overrideWithValue(
      TranslationService(dio: dio, log: log),
    ),
    scanPhotoServiceProvider.overrideWithValue(scanPhotos),
    secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
  ];
}

void main() {
  late AppDatabase database;
  late LogService log;
  late ScanPhotoService scanPhotos;

  setUp(() {
    database = openTestDatabase();
    log = LogService(
      File(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_widget_test.log',
        ),
      ),
    );
    scanPhotos = ScanPhotoService(
      Directory(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_widget_test_photos',
        ),
      ),
      log: log,
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(database, log, scanPhotos),
        child: const AllergyScannerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Drift schedules an internal timer when a query stream's last listener
  // goes away; disposing the widget tree via the ordinary tearDown() runs
  // too late to catch it, so close explicitly before each test ends and
  // settle once more (per drift's own stream_queries.dart guidance).
  Future<void> closeAndSettle(WidgetTester tester) async {
    await database.close();
    await tester.pump();
  }

  testWidgets('the disclaimer gates the app until it is acknowledged', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('I understand'), findsOneWidget);
    expect(find.text('Enter manually'), findsNothing);
    await closeAndSettle(tester);
  });

  testWidgets('acknowledging the disclaimer reveals the scan screen', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('AllergyScanner'), findsWidgets);
    expect(find.text('Enter manually'), findsOneWidget);
    // Camera entries are hidden, not disabled, when unavailable (R3.1).
    expect(find.text('Scan barcode'), findsNothing);
    expect(find.text('Scan ingredient list'), findsNothing);
    await closeAndSettle(tester);
  });

  testWidgets('an empty allergy list is called out on the scan screen', (
    WidgetTester tester,
  ) async {
    await database.settingsDao.acknowledgeDisclaimer(testTimestamp);
    await pumpApp(tester);

    expect(find.text('No terms yet — add one first'), findsOneWidget);
    await closeAndSettle(tester);
  });

  testWidgets('the shell offers all four destinations', (
    WidgetTester tester,
  ) async {
    await database.settingsDao.acknowledgeDisclaimer(testTimestamp);
    await pumpApp(tester);

    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Allergies'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    await closeAndSettle(tester);
  });

  testWidgets(
    'setting appLanguage to German renders the shell in German',
    (WidgetTester tester) async {
      await database.settingsDao.acknowledgeDisclaimer(testTimestamp);
      await database.settingsDao.setAppLanguage('de');
      await pumpApp(tester);

      expect(find.text('Scannen'), findsWidgets);
      expect(find.text('Allergien'), findsWidgets);
      expect(find.text('Verlauf'), findsWidgets);
      expect(find.text('Einstellungen'), findsWidgets);
      // The English strings must not also be present — a stuck locale
      // resolution would otherwise pass by accident.
      expect(find.text('Scan'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      // app.dart's MaterialApp.builder keeps Intl.defaultLocale in sync with
      // the resolved locale, so German date symbols must already be loaded
      // (via GlobalMaterialLocalizations' delegate) — this throws
      // LocaleDataException if they are not.
      expect(
        () => Formatters.dateTime(DateTime.utc(2026, 1, 2, 3, 4)),
        returnsNormally,
      );
      await closeAndSettle(tester);
    },
  );

  testWidgets(
    'appLanguage left as null (system) keeps the default English locale',
    (WidgetTester tester) async {
      await database.settingsDao.acknowledgeDisclaimer(testTimestamp);
      await pumpApp(tester);

      // The Flutter test harness's platform locale defaults to en_US, so an
      // unset appLanguage must resolve to English, not fall back to German.
      expect(find.text('Scan'), findsWidgets);
      expect(find.text('Scannen'), findsNothing);
      await closeAndSettle(tester);
    },
  );
}
