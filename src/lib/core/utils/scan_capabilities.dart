import 'dart:io' show Platform;

/// The only place that asks which platform this is (doc/ARCHITECTURE.md §5.8).
///
/// v0.1 targets Android and iOS, where both scanning features are available, so
/// every flag below is currently true in production. The indirection stays
/// anyway: it is what keeps "hide, never disable" (R3.1) enforceable when a
/// platform is added back, and it is how tests exercise the manual-only paths
/// without a platform override.
///
/// Verified on pub.dev 2026-08-20:
///   * `mobile_scanner` 7.4.0 — Android, iOS, macOS (and web, unused here),
///   * `google_mlkit_text_recognition` 0.17.1 — Android and iOS only.
class ScanCapabilities {
  const ScanCapabilities({
    required this.canScanBarcode,
    required this.canRecognizeText,
  });

  /// Everything unavailable — for tests and for widget previews.
  const ScanCapabilities.none()
    : canScanBarcode = false,
      canRecognizeText = false;

  factory ScanCapabilities.forCurrentPlatform() {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    return ScanCapabilities(
      // mobile_scanner also covers macOS, but macOS is not a target of v0.1.
      canScanBarcode: isMobile,
      // Photographing an ingredient list needs the camera and ML Kit.
      canRecognizeText: isMobile,
    );
  }

  final bool canScanBarcode;
  final bool canRecognizeText;

  /// True where the user has no camera path at all and must type everything.
  bool get isManualOnly => !canScanBarcode && !canRecognizeText;
}
