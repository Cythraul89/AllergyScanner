import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/scan_dao.dart';
import '../../core/models/enums.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';

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
      (ref) => HistoryActions(scanDao: ref.watch(scanDaoProvider)),
    );

class HistoryActions {
  HistoryActions({required ScanDao scanDao}) : _scanDao = scanDao;

  final ScanDao _scanDao;

  Future<void> delete(String scanId) => _scanDao.deleteById(scanId);

  Future<void> clearAll() => _scanDao.deleteAll();
}
