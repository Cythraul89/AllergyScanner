import 'enums.dart';

/// What the single scan pipeline accepts (doc/ARCHITECTURE.md §4.1).
///
/// Sealed so a new input path cannot be added without handling it in
/// `ScanActions.evaluate`.
sealed class ScanInput {
  const ScanInput();
}

class BarcodeInput extends ScanInput {
  const BarcodeInput({required this.barcode, required this.fromCamera});

  final String barcode;
  final bool fromCamera;

  ScanInputMode get mode =>
      fromCamera ? ScanInputMode.barcode : ScanInputMode.manualBarcode;
}

class TextInput extends ScanInput {
  const TextInput({required this.text, required this.mode});

  final String text;
  final ScanInputMode mode;
}
