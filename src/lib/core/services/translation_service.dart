import 'dart:io';

import 'package:dio/dio.dart';

import '../constants.dart';
import 'log_service.dart';

/// Result of a translation suggestion.
///
/// [TranslationNotFound] and [TranslationTransient] are separate on purpose —
/// same reasoning as `OffNotFound`/`OffTransient` (doc/ARCHITECTURE.md §5.7).
/// In practice a keyless MyMemory call rarely returns an explicit "not
/// found"; the daily quota running out is the transient case that matters.
sealed class TranslationResult {
  const TranslationResult();
}

final class TranslationSuccess extends TranslationResult {
  const TranslationSuccess(this.translatedText, {this.quality});

  final String translatedText;

  /// MyMemory's 0.0-1.0 match confidence, when present. Never gates
  /// acceptance — every suggestion is reviewed by the user before it becomes
  /// a real term.
  final double? quality;
}

final class TranslationNotFound extends TranslationResult {
  const TranslationNotFound();
}

final class TranslationTransient extends TranslationResult {
  const TranslationTransient();
}

final class TranslationFailure extends TranslationResult {
  const TranslationFailure(this.message);

  final String message;
}

/// Read-only MyMemory client, used only to *suggest* an allergen group name
/// translation. Never throws, never shows UI. Deliberately not throttled
/// like OpenFoodFactsService — that throttle exists because OFF is called on
/// every barcode scan; this is called rarely, on an explicit user tap.
class TranslationService {
  TranslationService({
    required Dio dio,
    required LogService log,
    this.baseUrl = kMyMemoryBaseUrl,
    this.contactEmail = kAppContactEmail,
  }) : _dio = dio,
       _log = log;

  final Dio _dio;
  final LogService _log;
  final String baseUrl;
  final String? contactEmail;

  /// [sourceLanguage]/[targetLanguage] are ISO 639-1 codes (`de`, `en`,
  /// `fr`, `it`).
  Future<TranslationResult> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio
          .get<Map<String, dynamic>>(
            '$baseUrl/get',
            queryParameters: <String, String>{
              'q': text,
              'langpair': '$sourceLanguage|$targetLanguage',
              if (contactEmail != null) 'de': contactEmail!,
            },
            options: Options(
              responseType: ResponseType.json,
              validateStatus: (int? _) => true,
            ),
          );

      final int status = response.statusCode ?? 0;
      if (status == 429 || status >= 500) {
        _log.warn('MyMemory returned $status ($sourceLanguage>$targetLanguage)');
        return const TranslationTransient();
      }
      if (status < 200 || status >= 300) {
        _log.warn('MyMemory returned $status ($sourceLanguage>$targetLanguage)');
        return TranslationFailure('Server returned status $status.');
      }

      final Map<String, dynamic>? body = response.data;
      if (body == null) {
        return const TranslationFailure('Empty response body.');
      }

      // MyMemory answers quota-exhausted requests with an HTTP 200 and this
      // flag set, not with an HTTP error status.
      if (body['quotaFinished'] == true) {
        _log.warn('MyMemory daily quota exhausted');
        return const TranslationTransient();
      }

      final Object? responseData = body['responseData'];
      if (responseData is! Map) {
        return const TranslationFailure('Unexpected response format.');
      }
      final Object? translated = responseData['translatedText'];
      if (translated is! String || translated.trim().isEmpty) {
        return const TranslationNotFound();
      }

      return TranslationSuccess(
        translated.trim(),
        quality: _asDouble(responseData['match']),
      );
    } on DioException catch (exception) {
      return _mapDioError('$sourceLanguage>$targetLanguage', exception);
    } on Object catch (cause, stackTrace) {
      _log.error(
        'MyMemory translation failed ($sourceLanguage>$targetLanguage)',
        cause,
        stackTrace,
      );
      return TranslationFailure('Translation failed: $cause');
    }
  }

  /// [pair] is the language pair, never the user's term: the log is
  /// shareable (Settings -> App logs), and an allergen name is exactly the
  /// kind of personal data PRIVACY.md promises stays on the device.
  TranslationResult _mapDioError(String pair, DioException exception) {
    final int? status = exception.response?.statusCode;
    if (status == 429 || (status != null && status >= 500)) {
      return const TranslationTransient();
    }

    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        _log.warn('MyMemory unreachable ($pair): ${exception.type}');
        return const TranslationTransient();
      case DioExceptionType.cancel:
        return const TranslationFailure('Translation cancelled.');
      case DioExceptionType.badCertificate:
        _log.error('MyMemory certificate rejected', exception);
        return const TranslationFailure('The server certificate was rejected.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        if (exception.error is SocketException) {
          return const TranslationTransient();
        }
        _log.error('MyMemory translation failed ($pair)', exception);
        return TranslationFailure(exception.message ?? 'Translation failed.');
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
