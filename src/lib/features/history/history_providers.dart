import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/scan_dao.dart';
import '../../core/models/enums.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../../core/services/scan_photo_service.dart';

/// `null` = show everything.
final StateProvider<ScanVerdict?> historyFilterProvider =
    StateProvider<ScanVerdict?>((ref) => null);

final StreamProvider<List<Scan>> scanHistoryProvider =
    StreamProvider<List<Scan>>((ref) {
      return ref
          .watch(scanDaoProvider)
          .watchHistory(verdict: ref.watch(historyFilterProvider));
    });

final Provider<HistoryActions> historyActionsProvider =
    Provider<HistoryActions>(
      (ref) => HistoryActions(
        scanDao: ref.watch(scanDaoProvider),
        scanPhotos: ref.watch(scanPhotoServiceProvider),
      ),
    );

class HistoryActions {
  HistoryActions({required ScanDao scanDao, required ScanPhotoService scanPhotos})
    : _scanDao = scanDao,
      _scanPhotos = scanPhotos;

  final ScanDao _scanDao;
  final ScanPhotoService _scanPhotos;

  Future<void> delete(String scanId) async {
    final Scan? deleted = await _scanDao.deleteById(scanId);
    final String? photoPath = deleted?.photoPath;
    if (photoPath != null) await _scanPhotos.delete(photoPath);
  }

  Future<void> clearAll() async {
    final List<Scan> deleted = await _scanDao.deleteAll();
    await _scanPhotos.deleteMany(
      deleted.map((Scan s) => s.photoPath).whereType<String>(),
    );
  }
}
