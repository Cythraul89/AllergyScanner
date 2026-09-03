import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../models/enums.dart';

/// Date and label formatting.
///
/// The verdict wording lives here on purpose: it is the copy that must never
/// claim a product is safe (REQUIREMENTS §5.6), so it is auditable in one file
/// instead of being spread across screens. Every method that returns
/// user-facing text takes the caller's [AppLocalizations] rather than
/// hardcoding English — [dateTime]/[date]/[time]/[dayHeader] need no such
/// parameter since `intl`'s `DateFormat` already follows `Intl.defaultLocale`,
/// which `app.dart` keeps in sync with the resolved app locale.
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
  static String verdictTitle(AppLocalizations l10n, ScanVerdict verdict) {
    switch (verdict) {
      case ScanVerdict.hit:
        return l10n.verdictTitleHit;
      case ScanVerdict.noMatch:
        // Never "safe", never "free from".
        return l10n.verdictTitleNoMatch;
      case ScanVerdict.unknown:
        return l10n.verdictTitleUnknown;
    }
  }

  /// Short label for a history row.
  static String verdictLabel(AppLocalizations l10n, ScanVerdict verdict) {
    switch (verdict) {
      case ScanVerdict.hit:
        return l10n.verdictLabelHit;
      case ScanVerdict.noMatch:
        return l10n.verdictLabelNoMatch;
      case ScanVerdict.unknown:
        return l10n.verdictLabelUnknown;
    }
  }

  static String inputModeLabel(AppLocalizations l10n, ScanInputMode mode) {
    switch (mode) {
      case ScanInputMode.barcode:
        return l10n.inputModeBarcode;
      case ScanInputMode.ocr:
        return l10n.inputModeOcr;
      case ScanInputMode.manualText:
        return l10n.inputModeManualText;
      case ScanInputMode.manualBarcode:
        return l10n.inputModeManualBarcode;
    }
  }

  static String matchCountLabel(AppLocalizations l10n, int count) =>
      l10n.matchCount(count);
}
