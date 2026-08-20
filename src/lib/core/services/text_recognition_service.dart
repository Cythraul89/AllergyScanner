import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'log_service.dart';

/// On-device text recognition.
///
/// An interface rather than a direct plugin call, so tests and unsupported
/// platforms get an implementation without any `Platform` check inside the
/// feature code (doc/ARCHITECTURE.md §5.8).
abstract interface class TextRecognitionService {
  /// Recognises the text in [imagePath] and returns it, or an empty string when
  /// nothing was found.
  ///
  /// The file is deleted before returning — no photo is ever kept (N10).
  Future<String> recognizeFile(String imagePath);

  Future<void> dispose();
}

/// Android and iOS. The bundled ML Kit model runs locally; no image leaves the
/// device.
class MlKitTextRecognitionService implements TextRecognitionService {
  MlKitTextRecognitionService({required LogService log}) : _log = log;

  final LogService _log;
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  Future<String> recognizeFile(String imagePath) async {
    try {
      final RecognizedText recognized = await _recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return recognized.text;
    } on Object catch (cause, stackTrace) {
      _log.error('Text recognition failed', cause, stackTrace);
      return '';
    } finally {
      await _deleteQuietly(imagePath);
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();

  Future<void> _deleteQuietly(String imagePath) async {
    try {
      final File file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (cause) {
      _log.warn('Could not delete the temporary photo: $cause');
    }
  }
}

/// macOS and anything else ML Kit does not cover. Nothing should reach it: the
/// OCR route is not registered where `ScanCapabilities.canRecognizeText` is
/// false, so being called at all is a bug worth failing loudly for.
class UnsupportedTextRecognitionService implements TextRecognitionService {
  const UnsupportedTextRecognitionService();

  @override
  Future<String> recognizeFile(String imagePath) {
    throw UnsupportedError(
      'Text recognition is not available on this platform. '
      'The OCR route must not be registered here.',
    );
  }

  @override
  Future<void> dispose() async {}
}
