import 'dart:io';

import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';

/// File logger in the app documents directory. Everything in the app logs
/// through this; `print` is never used.
///
/// Writes are serialised through one future chain and every failure is
/// swallowed — a logger that throws would take the app down with it.
class LogService {
  LogService(this._logFile);

  static const String fileName = 'allergy_scanner.log';

  /// Older lines are dropped beyond this, so the file cannot grow unbounded.
  static const int maximumLines = 2000;
  static const int _trimEveryWrites = 50;

  final File _logFile;

  Future<void> _pendingWrite = Future<void>.value();
  int _writesSinceTrim = 0;

  static Future<LogService> open() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File file = File(path_helper.join(directory.path, fileName));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return LogService(file);
  }

  File get file => _logFile;

  void info(String message) => _append('INFO', message);

  void warn(String message) => _append('WARN', message);

  void error(String message, [Object? cause, StackTrace? stackTrace]) {
    final String suffix = cause == null ? '' : ' — $cause';
    _append('ERROR', '$message$suffix');
    if (stackTrace != null) {
      _append('ERROR', stackTrace.toString());
    }
  }

  Future<String> read() async {
    try {
      if (!await _logFile.exists()) return '';
      return await _logFile.readAsString();
    } on IOException {
      return '';
    }
  }

  Future<void> clear() async {
    _pendingWrite = _pendingWrite.then((_) async {
      await _logFile.writeAsString('');
    }).catchError((Object _) {});
    await _pendingWrite;
  }

  /// Waits until everything queued has hit the disk — used before sharing the
  /// log file so the shared copy is not missing the last lines.
  Future<void> flush() => _pendingWrite;

  void _append(String level, String message) {
    final String line =
        '${DateTime.now().toIso8601String()} [$level] $message\n';
    _pendingWrite = _pendingWrite
        .then((_) async {
          await _logFile.writeAsString(
            line,
            mode: FileMode.append,
            flush: false,
          );
          _writesSinceTrim++;
          if (_writesSinceTrim >= _trimEveryWrites) {
            _writesSinceTrim = 0;
            await _trim();
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _trim() async {
    final List<String> lines = await _logFile.readAsLines();
    if (lines.length <= maximumLines) return;
    final Iterable<String> kept = lines.skip(lines.length - maximumLines);
    await _logFile.writeAsString('${kept.join('\n')}\n');
  }
}
