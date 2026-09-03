import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/scan_input.dart';
import '../../l10n/app_localizations.dart';
import 'scan_actions.dart';
import 'scan_providers.dart';

/// Camera barcode scanning. Registered only where
/// `ScanCapabilities.canScanBarcode` is true.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// The first detection wins; there is no continuous re-scan loop (R7.2).
  bool _handled = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanBarcodeTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: l10n.barcodeTorchTooltip,
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                MobileScanner(controller: _controller, onDetect: _onDetect),
                if (_busy) _BusyOverlay(message: l10n.barcodeLookingUpProduct),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Text(l10n.barcodePointAtBarcode),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/scan/manual'),
                  child: Text(l10n.scanManualTitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;

    final String? code = capture.barcodes
        .map((Barcode barcode) => barcode.rawValue)
        .firstWhere(
          (String? value) => value != null && value.trim().isNotEmpty,
          orElse: () => null,
        );
    if (code == null) return;

    _handled = true;
    await HapticFeedback.lightImpact();
    await _controller.stop();

    if (!mounted) return;
    setState(() => _busy = true);

    final ScanOutcome outcome = await ref
        .read(scanActionsProvider)
        .evaluate(BarcodeInput(barcode: code.trim(), fromCamera: true));

    if (!mounted) return;
    context.go('/scan/result/${outcome.scanId}', extra: outcome.lookupProblem);
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
