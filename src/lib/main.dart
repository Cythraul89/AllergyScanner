import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/database/app_database.dart';
import 'core/providers.dart';
import 'core/services/backup_service.dart';
import 'core/services/log_service.dart';
import 'core/services/open_food_facts_service.dart';
import 'core/services/text_recognition_service.dart';
import 'core/services/webdav_service.dart';
import 'core/utils/app_version.dart';
import 'core/utils/scan_capabilities.dart';

const String _gplNotice =
    'AllergyScanner is free software: you can redistribute it and/or modify it '
    'under the terms of the GNU General Public License as published by the '
    'Free Software Foundation, either version 3 of the License, or (at your '
    'option) any later version. It is distributed WITHOUT ANY WARRANTY.';

void main() {
  runZonedGuarded(_startUp, (Object error, StackTrace stackTrace) {
    // Last resort: the zone handler runs for errors that escape everything
    // else, including failures before the first frame.
    debugPrint('Unhandled error: $error\n$stackTrace');
  });
}

Future<void> _startUp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final LogService log = await LogService.open();

  // Everything printed anywhere ends up in the log file the user can share.
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) log.info(message);
  };

  final FlutterExceptionHandler? previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    // Call the original handler first; never presentError here — it recurses.
    previousOnError?.call(details);
    log.error(
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(<String>['allergy_scanner'], _gplNotice);
  });

  final AppDatabase database = AppDatabase();
  final AppVersion version = await _loadVersion(log);

  // The ingredient language starts at the device locale; existing rows are not
  // touched (R6.7).
  await database.settingsDao.ensureDefaults(
    deviceLanguage: PlatformDispatcher.instance.locale.languageCode,
  );

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: <String, Object>{
        // Mandatory for Open Food Facts — they block generic user agents.
        'User-Agent':
            'AllergyScanner/${version.version} ($kOpenFoodFactsContact)',
      },
    ),
  );

  final ScanCapabilities capabilities = ScanCapabilities.forCurrentPlatform();

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        logServiceProvider.overrideWithValue(log),
        dioProvider.overrideWithValue(dio),
        appVersionProvider.overrideWithValue(version),
        scanCapabilitiesProvider.overrideWithValue(capabilities),
        openFoodFactsServiceProvider.overrideWithValue(
          OpenFoodFactsService(dio: dio, log: log),
        ),
        textRecognitionServiceProvider.overrideWithValue(
          capabilities.canRecognizeText
              ? MlKitTextRecognitionService(log: log)
              : const UnsupportedTextRecognitionService(),
        ),
        backupServiceProvider.overrideWithValue(
          BackupService(database: database, log: log),
        ),
        webdavServiceProvider.overrideWithValue(WebdavService(log: log)),
        secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      ],
      child: const AllergyScannerApp(),
    ),
  );

  log.info('Started AllergyScanner ${version.display}');
}

/// A missing platform channel must not stop the app from starting.
Future<AppVersion> _loadVersion(LogService log) async {
  try {
    return await AppVersion.load();
  } on Object catch (cause) {
    log.warn('Could not read the package version: $cause');
    return const AppVersion.unknown();
  }
}
