import 'package:intl/intl.dart';

import '../models/enums.dart';

/// Date and label formatting.
///
/// The verdict wording lives here on purpose: it is the copy that must never
/// claim a product is safe (REQUIREMENTS §5.6), so it is auditable in one file
/// instead of being spread across screens.
class Formatters {
  const Formatters._();

  static final DateFormat _dateTime = DateFormat('d MMM y, HH:mm');
  static final DateFormat _date = DateFormat('d MMM y');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _dayHeader = DateFormat('d MMM y');
  static final DateFormat _fileTimestamp = DateFormat('yyyyMMdd_HHmmss');

  static String dateTime(DateTime value) => _dateTime.format(value.toLocal());

  static String date(DateTime value) => _date.format(value.toLocal());

  static String time(DateTime value) => _time.format(value.toLocal());

  static String dayHeader(DateTime value) => _dayHeader.format(value.toLocal());

  static String fileTimestamp(DateTime value) =>
      _fileTimestamp.format(value.toLocal());

  /// Headline of the result banner.
  static String verdictTitle(ScanVerdict verdict) {
    switch (verdict) {
      case ScanVerdict.hit:
        return 'Contains terms from your list';
      case ScanVerdict.noMatch:
        // Never "safe", never "free from".
        return 'No term from your list found';
      case ScanVerdict.unknown:
        return 'Could not be checked';
    }
  }

  /// Short label for a history row.
  static String verdictLabel(ScanVerdict verdict) {
    switch (verdict) {
      case ScanVerdict.hit:
        return 'Match';
      case ScanVerdict.noMatch:
        return 'No match';
      case ScanVerdict.unknown:
        return 'Unchecked';
    }
  }

  static String inputModeLabel(ScanInputMode mode) {
    switch (mode) {
      case ScanInputMode.barcode:
        return 'barcode';
      case ScanInputMode.ocr:
        return 'recognised text';
      case ScanInputMode.manualText:
        return 'typed text';
      case ScanInputMode.manualBarcode:
        return 'typed barcode';
    }
  }

  static String matchCountLabel(int count) =>
      count == 1 ? '1 match' : '$count matches';
}
