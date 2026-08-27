import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'product.dart';

/// A stored check. Self-contained on purpose: [evaluatedText] and
/// [productNameSnapshot] freeze what the user was told, so deleting a term or
/// correcting a product cannot rewrite history (doc/ARCHITECTURE.md §5.5).
class Scan extends Equatable {
  const Scan({
    required this.id,
    required this.scannedAt,
    required this.inputMode,
    required this.evaluatedText,
    required this.verdict,
    required this.matchCount,
    this.barcode,
    this.productNameSnapshot,
    this.name,
    this.shop,
    this.photoPath,
  });

  final String id;
  final DateTime scannedAt;
  final ScanInputMode inputMode;
  final String? barcode;
  final String? productNameSnapshot;
  final String evaluatedText;
  final ScanVerdict verdict;
  final int matchCount;

  /// User-entered custom label, set after the fact via "Edit details" —
  /// distinct from [productNameSnapshot], frozen at scan time from product
  /// data.
  final String? name;

  /// Free text; history groups scans that share the same value (§7.4).
  final String? shop;

  /// Relative path under the app documents dir to a user-attached photo.
  /// Unrelated to the OCR capture photo, which is never persisted (N10/N10a).
  final String? photoPath;

  bool get isBarcodeScan =>
      inputMode == ScanInputMode.barcode ||
      inputMode == ScanInputMode.manualBarcode;

  @override
  List<Object?> get props => [
    id,
    scannedAt,
    inputMode,
    barcode,
    productNameSnapshot,
    evaluatedText,
    verdict,
    matchCount,
    name,
    shop,
    photoPath,
  ];
}

/// One hit inside a scan. [termSnapshot] survives deletion of the term.
class ScanMatch extends Equatable {
  const ScanMatch({
    required this.id,
    required this.scanId,
    required this.termSnapshot,
    required this.matchedText,
    required this.startOffset,
    required this.endOffset,
    this.allergenTermId,
  });

  final String id;
  final String scanId;
  final String? allergenTermId;
  final String termSnapshot;
  final String matchedText;
  final int startOffset;
  final int endOffset;

  @override
  List<Object?> get props => [
    id,
    scanId,
    allergenTermId,
    termSnapshot,
    matchedText,
    startOffset,
    endOffset,
  ];
}

/// What the result view binds to.
class ScanResult extends Equatable {
  const ScanResult({
    required this.scan,
    required this.matches,
    this.product,
  });

  final Scan scan;
  final List<ScanMatch> matches;

  /// `null` for text scans and for barcodes whose product is unknown.
  final Product? product;

  @override
  List<Object?> get props => [scan, matches, product];
}
