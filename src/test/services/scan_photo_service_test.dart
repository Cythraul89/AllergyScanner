import 'dart:io';

import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/scan_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

/// Real temp directories, no mocking framework — same style as
/// backup_service_test.dart.
void main() {
  late Directory photosDir;
  late Directory sourceDir;
  late ScanPhotoService service;
  late LogService log;

  setUp(() {
    photosDir = Directory.systemTemp.createTempSync(
      'allergy_scanner_photo_test_',
    );
    sourceDir = Directory.systemTemp.createTempSync(
      'allergy_scanner_photo_test_source_',
    );
    log = LogService(
      File(path_helper.join(Directory.systemTemp.path, 'photo_test.log')),
    );
    service = ScanPhotoService(photosDir, log: log);
  });

  tearDown(() {
    if (photosDir.existsSync()) photosDir.deleteSync(recursive: true);
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File sourceFile(String name, List<int> bytes) {
    final File file = File(path_helper.join(sourceDir.path, name))
      ..writeAsBytesSync(bytes);
    return file;
  }

  test('attach copies the source file in, preserving its extension', () async {
    final File source = sourceFile('photo.jpg', <int>[1, 2, 3]);

    final String photoPath = await service.attach(
      scanId: 's1',
      sourcePath: source.path,
    );

    expect(photoPath, 'scan_photos/s1.jpg');
    final File resolved = await service.resolve(photoPath);
    expect(await resolved.readAsBytes(), <int>[1, 2, 3]);
  });

  test('attach called twice for the same scan id replaces the file', () async {
    final File first = sourceFile('a.jpg', <int>[1]);
    final File second = sourceFile('b.jpg', <int>[2, 2]);

    await service.attach(scanId: 's1', sourcePath: first.path);
    final String photoPath = await service.attach(
      scanId: 's1',
      sourcePath: second.path,
    );

    final File resolved = await service.resolve(photoPath);
    expect(await resolved.readAsBytes(), <int>[2, 2]);
    // No leftover file from the first attach.
    expect(photosDir.listSync(), hasLength(1));
  });

  test('delete on a missing file does not throw', () async {
    await expectLater(
      service.delete('scan_photos/never-existed.jpg'),
      completes,
    );
  });

  test('delete removes an existing file', () async {
    final File source = sourceFile('photo.jpg', <int>[1]);
    final String photoPath = await service.attach(
      scanId: 's1',
      sourcePath: source.path,
    );

    await service.delete(photoPath);

    expect(await (await service.resolve(photoPath)).exists(), isFalse);
  });

  test('restoreFromBytes writes bytes back to the resolved path', () async {
    await service.restoreFromBytes(
      photoPath: 'scan_photos/s2.jpg',
      bytes: <int>[5, 6, 7],
    );

    final File resolved = await service.resolve('scan_photos/s2.jpg');
    expect(await resolved.readAsBytes(), <int>[5, 6, 7]);
  });

  test('resolve is keyed by basename, independent of directory naming', () {
    // The service's own directory need not be literally named
    // "scan_photos" for resolve/attach to agree — see the doc comment on
    // ScanPhotoService.resolve.
    final ScanPhotoService oddlyNamed = ScanPhotoService(
      Directory(path_helper.join(sourceDir.path, 'not_scan_photos')),
      log: log,
    );
    expect(
      oddlyNamed.resolve('scan_photos/xyz.jpg'),
      completion(
        predicate<File>(
          (File f) => f.path.endsWith(path_helper.join('not_scan_photos', 'xyz.jpg')),
        ),
      ),
    );
  });
}
