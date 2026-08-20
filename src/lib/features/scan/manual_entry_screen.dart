import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/scan_input.dart';
import '../../core/providers.dart';
import '../../core/utils/scan_capabilities.dart';
import 'scan_actions.dart';
import 'scan_providers.dart';

enum _ManualMode { barcode, text }

/// Always available, on every platform — this is how a damaged barcode, an
/// unlisted product or a failed recognition is handled.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  _ManualMode? _mode;
  bool _busy = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);
    // Where the camera exists, a manual entry is most often a barcode the
    // scanner could not read; otherwise text is the more likely intent.
    final _ManualMode mode =
        _mode ??
        (capabilities.canScanBarcode ? _ManualMode.barcode : _ManualMode.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Enter manually')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SegmentedButton<_ManualMode>(
            segments: const <ButtonSegment<_ManualMode>>[
              ButtonSegment<_ManualMode>(
                value: _ManualMode.barcode,
                label: Text('Barcode'),
              ),
              ButtonSegment<_ManualMode>(
                value: _ManualMode.text,
                label: Text('Ingredient text'),
              ),
            ],
            selected: <_ManualMode>{mode},
            onSelectionChanged: (Set<_ManualMode> selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 24),
          if (mode == _ManualMode.barcode)
            ..._barcodeFields()
          else
            ..._textHandoff(),
        ],
      ),
    );
  }

  List<Widget> _barcodeFields() {
    final String digits = _barcodeController.text.trim();
    final bool valid = digits.length >= 8 && digits.length <= 14;

    return <Widget>[
      TextField(
        controller: _barcodeController,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(14),
        ],
        decoration: const InputDecoration(
          labelText: 'Barcode',
          border: OutlineInputBorder(),
          // The checksum is deliberately not validated: a user reading digits
          // off a damaged label should not be blocked by it.
          helperText: 'Digits only, 8–14 characters',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: valid && !_busy ? _lookUpBarcode : null,
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Look up'),
      ),
    ];
  }

  List<Widget> _textHandoff() {
    return <Widget>[
      const Text(
        'Type or paste the ingredient list on the next screen, then check it.',
      ),
      const SizedBox(height: 24),
      FilledButton(
        // Reuses the review screen, so typed and recognised text take exactly
        // the same path into the pipeline.
        onPressed: () => context.go('/scan/review', extra: ''),
        child: const Text('Enter ingredient text'),
      ),
    ];
  }

  Future<void> _lookUpBarcode() async {
    setState(() => _busy = true);

    final ScanOutcome outcome = await ref.read(scanActionsProvider).evaluate(
      BarcodeInput(barcode: _barcodeController.text.trim(), fromCamera: false),
    );

    if (!mounted) return;
    context.go('/scan/result/${outcome.scanId}', extra: outcome.lookupProblem);
  }
}
