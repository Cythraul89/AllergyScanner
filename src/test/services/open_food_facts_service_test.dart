import 'dart:convert';
import 'dart:io';

import 'package:allergy_scanner/core/models/product.dart';
import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/open_food_facts_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

/// Tested against a real loopback server rather than a mocked Dio: the point of
/// these tests is the mapping of real status codes and payloads to the sealed
/// result, including the difference between "not found" and "unreachable".
void main() {
  late HttpServer server;
  late OpenFoodFactsService service;
  late LogService log;

  int responseStatus = 200;
  String responseBody = '{}';
  String? lastQuery;

  setUp(() async {
    log = LogService(
      File(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_off_test.log',
        ),
      ),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      lastQuery = request.uri.query;
      request.response.statusCode = responseStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(responseBody);
      await request.response.close();
    });

    service = OpenFoodFactsService(
      dio: Dio(),
      log: log,
      baseUrl: 'http://127.0.0.1:${server.port}',
      minimumInterval: Duration.zero,
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  String productBody(Map<String, Object?> product) =>
      jsonEncode(<String, Object?>{
        'status': 'success',
        'product': product,
      });

  test('maps a product payload to the domain model', () async {
    responseStatus = 200;
    responseBody = productBody(<String, Object?>{
      'product_name': 'Choco Bar',
      'brands': 'Sweetco',
      'quantity': '200 g',
      'ingredients_text': 'sugar, hazelnuts, milk',
      'allergens_tags': <String>['en:nuts', 'en:milk'],
      'traces_tags': <String>['en:gluten'],
      'image_url': 'https://example.org/front.jpg',
    });

    final OffResult result = await service.fetchProduct(
      '4001234567890',
      preferredLanguage: 'en',
    );

    expect(result, isA<OffSuccess>());
    final Product product = (result as OffSuccess).product;
    expect(product.barcode, '4001234567890');
    expect(product.productName, 'Choco Bar');
    expect(product.ingredientsText, 'sugar, hazelnuts, milk');
    expect(product.allergensTags, <String>['en:nuts', 'en:milk']);
    expect(product.tracesTags, <String>['en:gluten']);
    expect(product.hasIngredients, isTrue);
    expect(product.hasManualOverride, isFalse);
    expect(product.fetchedAt, isNotNull);
  });

  test('requests only the fields the app stores', () async {
    responseBody = productBody(<String, Object?>{'product_name': 'X'});
    await service.fetchProduct('1', preferredLanguage: 'de');

    expect(lastQuery, contains('fields='));
    expect(Uri.decodeFull(lastQuery!), contains('ingredients_text_de'));
  });

  test('prefers the ingredient text in the requested language', () async {
    responseBody = productBody(<String, Object?>{
      'ingredients_text': 'sugar, hazelnuts',
      'ingredients_text_de': 'Zucker, Haselnüsse',
    });

    final OffResult result = await service.fetchProduct(
      '1',
      preferredLanguage: 'de',
    );

    final Product product = (result as OffSuccess).product;
    expect(product.ingredientsText, 'Zucker, Haselnüsse');
    expect(product.ingredientsLanguage, 'de');
  });

  test('falls back to the generic ingredient text', () async {
    responseBody = productBody(<String, Object?>{
      'ingredients_text': 'sugar, hazelnuts',
    });

    final Product product =
        (await service.fetchProduct('1', preferredLanguage: 'de')
                as OffSuccess)
            .product;
    expect(product.ingredientsText, 'sugar, hazelnuts');
    expect(product.ingredientsLanguage, isNull);
  });

  test('falls back to any other language the server included', () async {
    responseBody = productBody(<String, Object?>{
      'ingredients_text_fr': 'sucre, noisettes',
    });

    final Product product =
        (await service.fetchProduct('1', preferredLanguage: 'de')
                as OffSuccess)
            .product;
    expect(product.ingredientsText, 'sucre, noisettes');
    expect(product.ingredientsLanguage, 'fr');
  });

  test('a product without ingredients still succeeds, with no text', () async {
    responseBody = productBody(<String, Object?>{'product_name': 'Choco Bar'});

    final Product product =
        (await service.fetchProduct('1', preferredLanguage: 'en')
                as OffSuccess)
            .product;
    expect(product.hasIngredients, isFalse);
    expect(product.productName, 'Choco Bar');
  });

  test('an empty ingredient string counts as no ingredients', () async {
    responseBody = productBody(<String, Object?>{'ingredients_text': '   '});

    final Product product =
        (await service.fetchProduct('1', preferredLanguage: 'en')
                as OffSuccess)
            .product;
    expect(product.ingredientsText, isNull);
  });

  test('404 is not found, not a failure', () async {
    responseStatus = 404;
    responseBody = jsonEncode(<String, Object?>{
      'result': <String, Object?>{'id': 'product_not_found'},
    });

    expect(
      await service.fetchProduct('1', preferredLanguage: 'en'),
      isA<OffNotFound>(),
    );
  });

  test('a 200 body without a product but with a not-found marker', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{
      'result': <String, Object?>{'id': 'product_not_found'},
    });

    expect(
      await service.fetchProduct('1', preferredLanguage: 'en'),
      isA<OffNotFound>(),
    );
  });

  test('the v2-style status flag is still recognised', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{'status': 0});

    expect(
      await service.fetchProduct('1', preferredLanguage: 'en'),
      isA<OffNotFound>(),
    );
  });

  test('429 is transient, so the UI can offer a retry', () async {
    responseStatus = 429;
    responseBody = '{}';

    expect(
      await service.fetchProduct('1', preferredLanguage: 'en'),
      isA<OffTransient>(),
    );
  });

  test('500 is transient', () async {
    responseStatus = 500;
    responseBody = '{}';

    expect(
      await service.fetchProduct('1', preferredLanguage: 'en'),
      isA<OffTransient>(),
    );
  });

  test('an unexpected payload is a failure, never "not found"', () async {
    responseStatus = 200;
    responseBody = jsonEncode(<String, Object?>{'unexpected': true});

    final OffResult result = await service.fetchProduct(
      '1',
      preferredLanguage: 'en',
    );
    expect(result, isA<OffFailure>());
  });

  test('an unreachable server is transient, never "not found"', () async {
    await server.close(force: true);

    final OffResult result = await service.fetchProduct(
      '1',
      preferredLanguage: 'en',
    );
    // Collapsing this into OffNotFound would turn an outage into a statement
    // about the product (doc/ARCHITECTURE.md §5.7).
    expect(result, isA<OffTransient>());
  });

  test('requests are spaced by the minimum interval', () async {
    responseBody = productBody(<String, Object?>{'product_name': 'X'});
    final OpenFoodFactsService throttled = OpenFoodFactsService(
      dio: Dio(),
      log: log,
      baseUrl: 'http://127.0.0.1:${server.port}',
      minimumInterval: const Duration(milliseconds: 200),
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    await throttled.fetchProduct('1', preferredLanguage: 'en');
    await throttled.fetchProduct('2', preferredLanguage: 'en');
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(200));
  });
}
