import 'dart:convert';
import 'dart:io';

import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/translation_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

/// Tested against a real loopback server, same reasoning and pattern as
/// open_food_facts_service_test.dart: the point is the mapping of real
/// status codes and payloads to the sealed result.
void main() {
  late HttpServer server;
  late TranslationService service;
  late LogService log;

  int responseStatus = 200;
  String responseBody = '{}';

  setUp(() async {
    log = LogService(
      File(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_translation_test.log',
        ),
      ),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      request.response.statusCode = responseStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(responseBody);
      await request.response.close();
    });

    service = TranslationService(
      dio: Dio(),
      log: log,
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<TranslationResult> translate() => service.translate(
    text: 'hazelnut',
    sourceLanguage: 'en',
    targetLanguage: 'de',
  );

  test('maps a successful response to a suggestion', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{
      'responseData': <String, Object?>{
        'translatedText': 'Haselnuss',
        'match': 1,
      },
      'quotaFinished': false,
      'responseStatus': 200,
    });

    final TranslationResult result = await translate();

    expect(result, isA<TranslationSuccess>());
    final TranslationSuccess success = result as TranslationSuccess;
    expect(success.translatedText, 'Haselnuss');
    expect(success.quality, 1.0);
  });

  test('an exhausted quota is transient, not a failure', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{
      'responseData': <String, Object?>{'translatedText': 'PLEASE...'},
      'quotaFinished': true,
    });

    expect(await translate(), isA<TranslationTransient>());
  });

  test('an empty translated text is treated as not found', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{
      'responseData': <String, Object?>{'translatedText': ''},
      'quotaFinished': false,
    });

    expect(await translate(), isA<TranslationNotFound>());
  });

  test('429 is transient', () async {
    responseStatus = 429;
    responseBody = '{}';
    expect(await translate(), isA<TranslationTransient>());
  });

  test('500 is transient', () async {
    responseStatus = 500;
    responseBody = '{}';
    expect(await translate(), isA<TranslationTransient>());
  });

  test('an unexpected payload is a failure', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{'unexpected': true});
    expect(await translate(), isA<TranslationFailure>());
  });

  test('an unreachable server is transient', () async {
    await server.close(force: true);
    expect(await translate(), isA<TranslationTransient>());
  });
}
