import 'dart:io';

import 'package:dio/dio.dart';

import '../constants.dart';
import '../models/enums.dart';
import '../models/product.dart';
import 'log_service.dart';

/// Result of a product lookup.
///
/// [OffNotFound] and [OffTransient] are separate on purpose: "the server says
/// there is no such barcode" and "we could not reach the server" must never
/// share a code path, or an outage reads as a statement about the product
/// (doc/ARCHITECTURE.md §5.7).
sealed class OffResult {
  const OffResult();
}

final class OffSuccess extends OffResult {
  const OffSuccess(this.product);

  final Product product;
}

final class OffNotFound extends OffResult {
  const OffNotFound();
}

final class OffTransient extends OffResult {
  const OffTransient();
}

final class OffFailure extends OffResult {
  const OffFailure(this.message);

  final String message;
}

/// Read-only Open Food Facts client. Never throws, never shows UI.
class OpenFoodFactsService {
  OpenFoodFactsService({
    required Dio dio,
    required LogService log,
    this.baseUrl = kOpenFoodFactsBaseUrl,
    this.minimumInterval = kOpenFoodFactsMinimumInterval,
    DateTime Function()? now,
  }) : _dio = dio,
       _log = log,
       _now = now ?? DateTime.now;

  final Dio _dio;
  final LogService _log;
  final DateTime Function() _now;

  final String baseUrl;

  /// Their documented limit is 15 read requests per minute per IP. Requests are
  /// spaced rather than rejected, so a second scan still works — it just waits.
  final Duration minimumInterval;

  DateTime? _lastRequestAt;

  Future<OffResult> fetchProduct(
    String barcode, {
    required String preferredLanguage,
  }) async {
    await _throttle();

    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            '$baseUrl/api/v3/product/$barcode.json',
            queryParameters: <String, String>{
              'fields': _requestedFields(preferredLanguage),
            },
            options: Options(
              responseType: ResponseType.json,
              // Status codes are interpreted below, not thrown.
              validateStatus: (int? _) => true,
            ),
          );

      final int status = response.statusCode ?? 0;
      if (status == 404) {
        return const OffNotFound();
      }
      if (status == 429 || status >= 500) {
        _log.warn('Open Food Facts returned $status for $barcode');
        return const OffTransient();
      }
      if (status < 200 || status >= 300) {
        _log.warn('Open Food Facts returned $status for $barcode');
        return OffFailure('Server returned status $status.');
      }

      final Map<String, dynamic>? body = response.data;
      if (body == null) {
        return const OffFailure('Empty response body.');
      }

      final Object? productField = body['product'];
      if (productField is! Map) {
        // v3 signals a missing product in `result`; v2 used `status: 0`. Both
        // shapes are accepted because the exact v3 envelope is unconfirmed
        // (doc/REQUIREMENTS.md §12 Q3).
        if (_looksLikeNotFound(body)) {
          return const OffNotFound();
        }
        _log.warn('Unexpected Open Food Facts payload for $barcode');
        return const OffFailure('Unexpected response format.');
      }

      return OffSuccess(
        _mapProduct(
          barcode: barcode,
          json: productField.cast<String, dynamic>(),
          preferredLanguage: preferredLanguage,
        ),
      );
    } on DioException catch (exception) {
      return _mapDioError(barcode, exception);
    } on Object catch (cause, stackTrace) {
      _log.error('Open Food Facts lookup failed for $barcode', cause, stackTrace);
      return OffFailure('Lookup failed: $cause');
    }
  }

  Future<void> _throttle() async {
    final DateTime? last = _lastRequestAt;
    final DateTime current = _now();
    if (last != null) {
      final Duration elapsed = current.difference(last);
      if (elapsed < minimumInterval) {
        await Future<void>.delayed(minimumInterval - elapsed);
      }
    }
    _lastRequestAt = _now();
  }

  String _requestedFields(String preferredLanguage) {
    return <String>[
      'product_name',
      'brands',
      'quantity',
      'ingredients_text',
      'ingredients_text_$preferredLanguage',
      'allergens_tags',
      'traces_tags',
      'image_url',
    ].join(',');
  }

  bool _looksLikeNotFound(Map<String, dynamic> body) {
    final Object? status = body['status'];
    if (status == 0 || status == 'failure') return true;

    final Object? result = body['result'];
    if (result is Map && result['id'] == 'product_not_found') return true;

    final Object? errors = body['errors'];
    if (errors is List &&
        errors.any(
          (Object? error) =>
              error is Map && '${error['impact']}'.contains('failure'),
        )) {
      return true;
    }
    return false;
  }

  OffResult _mapDioError(String barcode, DioException exception) {
    final int? status = exception.response?.statusCode;
    if (status == 404) return const OffNotFound();
    if (status == 429 || (status != null && status >= 500)) {
      return const OffTransient();
    }

    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        _log.warn('Open Food Facts unreachable for $barcode: ${exception.type}');
        return const OffTransient();
      case DioExceptionType.cancel:
        return const OffFailure('Lookup cancelled.');
      case DioExceptionType.badCertificate:
        _log.error('Open Food Facts certificate rejected', exception);
        return const OffFailure('The server certificate was rejected.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        if (exception.error is SocketException) {
          return const OffTransient();
        }
        _log.error('Open Food Facts lookup failed for $barcode', exception);
        return OffFailure(exception.message ?? 'Lookup failed.');
    }
  }

  Product _mapProduct({
    required String barcode,
    required Map<String, dynamic> json,
    required String preferredLanguage,
  }) {
    final (String? ingredients, String? language) = _pickIngredients(
      json,
      preferredLanguage,
    );
    final DateTime timestamp = _now();

    return Product(
      barcode: barcode,
      productName: _stringOrNull(json['product_name']),
      brands: _stringOrNull(json['brands']),
      quantity: _stringOrNull(json['quantity']),
      ingredientsText: ingredients,
      ingredientsLanguage: language,
      imageUrl: _stringOrNull(json['image_url']),
      allergensTags: _stringList(json['allergens_tags']),
      tracesTags: _stringList(json['traces_tags']),
      source: ProductSource.openFoodFacts,
      fetchedAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// Preferred language, then the generic field, then any other language the
  /// server happened to include (R6.7). The third tier only produces a value
  /// when the response carries extra `ingredients_text_*` keys.
  (String?, String?) _pickIngredients(
    Map<String, dynamic> json,
    String preferredLanguage,
  ) {
    final String? preferred = _stringOrNull(
      json['ingredients_text_$preferredLanguage'],
    );
    if (preferred != null) return (preferred, preferredLanguage);

    final String? generic = _stringOrNull(json['ingredients_text']);
    if (generic != null) return (generic, null);

    for (final String key in json.keys) {
      if (!key.startsWith('ingredients_text_')) continue;
      final String? value = _stringOrNull(json[key]);
      if (value != null) {
        return (value, key.substring('ingredients_text_'.length));
      }
    }
    return (null, null);
  }

  static String? _stringOrNull(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((Object? entry) => '$entry'.trim())
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
}
