import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../constants.dart';
import 'log_service.dart';

/// Connection details for the user's own WebDAV server. The password is read
/// from `flutter_secure_storage` by the caller and never persisted elsewhere.
class WebdavCredentials {
  const WebdavCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.certificateFingerprint,
  });

  final String baseUrl;
  final String username;
  final String password;

  /// SHA-256 of the server certificate, lowercase hex without separators.
  /// When set, any other certificate is rejected.
  final String? certificateFingerprint;
}

sealed class WebdavOutcome {
  const WebdavOutcome();
}

final class WebdavSuccess<T> extends WebdavOutcome {
  const WebdavSuccess([this.value]);

  final T? value;
}

/// The server presented a certificate that is not trusted and does not match
/// the pinned fingerprint. [observedFingerprint] is what it actually presented,
/// so the UI can offer to pin it.
final class WebdavUntrustedCertificate extends WebdavOutcome {
  const WebdavUntrustedCertificate(this.observedFingerprint);

  final String observedFingerprint;
}

final class WebdavAuthenticationFailed extends WebdavOutcome {
  const WebdavAuthenticationFailed();
}

/// Unreachable, timed out, or a 5xx — retrying may help.
final class WebdavTransient extends WebdavOutcome {
  const WebdavTransient();
}

final class WebdavFailure extends WebdavOutcome {
  const WebdavFailure(this.message);

  final String message;
}

/// Builds the HTTP client for one WebDAV call. Injectable so tests can point at
/// a loopback server without a certificate.
typedef WebdavClientFactory =
    Dio Function({
      required WebdavCredentials credentials,
      required void Function(String fingerprint) onUntrustedCertificate,
    });

/// Optional Nextcloud/WebDAV sync of the backup archive.
///
/// Returns a sealed outcome and never shows UI. Only the archive is
/// transferred; nothing else about the user leaves the device.
class WebdavService {
  WebdavService({required LogService log, WebdavClientFactory? clientFactory})
    : _log = log,
      _clientFactory = clientFactory ?? _defaultClientFactory;

  static final RegExp _backupNamePattern = RegExp(
    '${RegExp.escape(kBackupFilePrefix)}\\d{8}_\\d{6}\\.zip',
  );

  final LogService _log;
  final WebdavClientFactory _clientFactory;

  /// PROPFIND with depth 0 — cheapest request that proves URL, credentials and
  /// certificate all work.
  Future<WebdavOutcome> testConnection(WebdavCredentials credentials) {
    return _run(credentials, (Dio client) async {
      await client.request<void>(
        '',
        options: _webdavOptions('PROPFIND', depth: '0'),
      );
      return const WebdavSuccess<void>();
    });
  }

  Future<WebdavOutcome> uploadBackup(
    WebdavCredentials credentials,
    File archive,
  ) {
    return _run(credentials, (Dio client) async {
      final List<int> bytes = await archive.readAsBytes();
      final String name = archive.uri.pathSegments.last;
      await client.put<void>(
        name,
        data: Stream<List<int>>.value(bytes),
        options: Options(
          headers: <String, Object>{
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: 'application/zip',
          },
        ),
      );
      _log.info('Uploaded $name to WebDAV');
      return const WebdavSuccess<void>();
    });
  }

  /// Newest backup file name on the server, or `null` when there is none.
  Future<WebdavOutcome> findLatestBackupName(WebdavCredentials credentials) {
    return _run(credentials, (Dio client) async {
      final Response<String> response = await client.request<String>(
        '',
        options: _webdavOptions('PROPFIND', depth: '1'),
      );
      final List<String> names = _parseBackupNames(response.data ?? '');
      if (names.isEmpty) return const WebdavSuccess<String>();
      // The timestamp in the name sorts lexicographically (R8.1).
      names.sort();
      return WebdavSuccess<String>(names.last);
    });
  }

  Future<WebdavOutcome> downloadBackup(
    WebdavCredentials credentials,
    String name,
  ) {
    return _run(credentials, (Dio client) async {
      final Response<List<int>> response = await client.get<List<int>>(
        name,
        options: Options(responseType: ResponseType.bytes),
      );
      final List<int>? bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return const WebdavFailure('The downloaded archive was empty.');
      }
      return WebdavSuccess<List<int>>(bytes);
    });
  }

  /// File names are extracted from the `<d:href>` elements with a regular
  /// expression rather than a full XML parse: the only thing needed from the
  /// PROPFIND response is which of our own archive names exist.
  List<String> _parseBackupNames(String responseBody) {
    return _backupNamePattern
        .allMatches(responseBody)
        .map((Match match) => match.group(0)!)
        .toSet()
        .toList(growable: true);
  }

  Options _webdavOptions(String method, {required String depth}) {
    return Options(
      method: method,
      headers: <String, Object>{'Depth': depth},
      responseType: ResponseType.plain,
      // 207 Multi-Status is the normal PROPFIND answer.
      validateStatus: (int? status) =>
          status != null && status >= 200 && status < 300 || status == 207,
    );
  }

  Future<WebdavOutcome> _run(
    WebdavCredentials credentials,
    Future<WebdavOutcome> Function(Dio client) action,
  ) async {
    String? untrustedFingerprint;
    final Dio client = _clientFactory(
      credentials: credentials,
      onUntrustedCertificate: (String fingerprint) {
        untrustedFingerprint = fingerprint;
      },
    );

    try {
      return await action(client);
    } on DioException catch (exception) {
      final String? observed = untrustedFingerprint;
      if (observed != null) {
        _log.warn('WebDAV certificate not trusted (sha256 $observed)');
        return WebdavUntrustedCertificate(observed);
      }

      final int? status = exception.response?.statusCode;
      if (status == 401 || status == 403) {
        return const WebdavAuthenticationFailed();
      }
      if (status != null && status >= 500) {
        return const WebdavTransient();
      }

      switch (exception.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
        case DioExceptionType.connectionError:
          return const WebdavTransient();
        case DioExceptionType.badCertificate:
          return const WebdavFailure('The server certificate was rejected.');
        case DioExceptionType.cancel:
          return const WebdavFailure('The transfer was cancelled.');
        case DioExceptionType.badResponse:
        case DioExceptionType.unknown:
          if (exception.error is SocketException) {
            return const WebdavTransient();
          }
          _log.error('WebDAV request failed', exception);
          return WebdavFailure(exception.message ?? 'WebDAV request failed.');
      }
    } on Object catch (cause, stackTrace) {
      _log.error('WebDAV request failed', cause, stackTrace);
      return WebdavFailure('WebDAV request failed: $cause');
    } finally {
      client.close(force: true);
    }
  }

  static Dio _defaultClientFactory({
    required WebdavCredentials credentials,
    required void Function(String fingerprint) onUntrustedCertificate,
  }) {
    final String base = credentials.baseUrl.endsWith('/')
        ? credentials.baseUrl
        : '${credentials.baseUrl}/';

    final Dio dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: <String, Object>{
          'Authorization':
              'Basic '
              '${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
        },
      ),
    );

    final String? pinned = credentials.certificateFingerprint?.toLowerCase();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient httpClient = HttpClient();
        httpClient.badCertificateCallback =
            (X509Certificate certificate, String host, int port) {
              final String observed = sha256
                  .convert(certificate.der)
                  .toString()
                  .toLowerCase();
              if (pinned != null && observed == pinned) return true;
              onUntrustedCertificate(observed);
              return false;
            };
        return httpClient;
      },
    );
    return dio;
  }
}
