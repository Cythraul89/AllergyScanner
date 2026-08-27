import 'dart:io';

import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

/// Local storage for a photo the user deliberately attaches to a history
/// entry (a separate, opt-in feature — not the OCR capture photo, which
/// `TextRecognitionService` deletes immediately and never persists; see N10 /
/// N10a). Mirrors `LogService`'s fixed-subdirectory pattern.
class ScanPhotoService {
  ScanPhotoService(this._directory, {required LogService log}) : _log = log;

  static const String subdirectoryName = 'scan_photos';

  final Directory _directory;
  final LogService _log;

  static Future<ScanPhotoService> open({required LogService log}) async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      path_helper.join(documents.path, subdirectoryName),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return ScanPhotoService(directory, log: log);
  }

  /// Copies [sourcePath] (e.g. an `image_picker` result) in as the photo for
  /// [scanId], replacing any file already there for that id, and returns the
  /// path to store in `scans.photoPath` — relative to the app documents
  /// directory, so it stays meaningful after a restore on a different
  /// device. Keeps the picked file's own extension rather than re-encoding.
  Future<String> attach({
    required String scanId,
    required String sourcePath,
  }) async {
    final String extension = path_helper.extension(sourcePath);
    final File target = File(
      path_helper.join(_directory.path, '$scanId$extension'),
    );
    await File(sourcePath).copy(target.path);
    return path_helper.join(subdirectoryName, '$scanId$extension');
  }

  /// Resolves a stored `scans.photoPath` (e.g. `scan_photos/<id>.jpg`) to
  /// the file on disk, by its basename within [_directory] — not by calling
  /// `getApplicationDocumentsDirectory()` again and not by assuming
  /// [_directory]'s own name, so this stays correct however the service was
  /// constructed, including a test's plain temp directory that never goes
  /// through [open] at all.
  Future<File> resolve(String photoPath) async {
    return File(
      path_helper.join(_directory.path, path_helper.basename(photoPath)),
    );
  }

  /// Writes [bytes] back to [photoPath] — used by backup import to restore a
  /// photo from an archive entry named after its own stored path.
  Future<void> restoreFromBytes({
    required String photoPath,
    required List<int> bytes,
  }) async {
    final File target = await resolve(photoPath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  /// Best-effort: a missing or already-deleted file must never block a DB
  /// delete that already committed (same philosophy as LogService's
  /// swallow-and-log writes).
  Future<void> delete(String photoPath) async {
    try {
      final File file = await resolve(photoPath);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (cause) {
      _log.warn('Could not delete scan photo $photoPath: $cause');
    }
  }

  Future<void> deleteMany(Iterable<String> photoPaths) async {
    for (final String photoPath in photoPaths) {
      await delete(photoPath);
    }
  }
}
