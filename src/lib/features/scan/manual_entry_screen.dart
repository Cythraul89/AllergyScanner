import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/scan_input.dart';
import '../../core/providers.dart';
import '../../core/utils/scan_capabilities.dart';
import '../../l10n/app_localizations.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanManualTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SegmentedButton<_ManualMode>(
            segments: <ButtonSegment<_ManualMode>>[
              ButtonSegment<_ManualMode>(
                value: _ManualMode.barcode,
                label: Text(l10n.manualBarcodeSegment),
              ),
              ButtonSegment<_ManualMode>(
                value: _ManualMode.text,
                label: Text(l10n.manualIngredientTextSegment),
              ),
            ],
            selected: <_ManualMode>{mode},
            onSelectionChanged: (Set<_ManualMode> selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 24),
          if (mode == _ManualMode.barcode)
            ..._barcodeFields(l10n)
          else
            ..._textHandoff(l10n),
        ],
      ),
    );
  }

  List<Widget> _barcodeFields(AppLocalizations l10n) {
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
        decoration: InputDecoration(
          labelText: l10n.manualBarcodeSegment,
          border: const OutlineInputBorder(),
          // The checksum is deliberately not validated: a user reading digits
          // off a damaged label should not be blocked by it.
          helperText: l10n.manualBarcodeHelper,
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
            : Text(l10n.manualLookUpAction),
      ),
    ];
  }

  List<Widget> _textHandoff(AppLocalizations l10n) {
    return <Widget>[
      Text(l10n.manualTextHandoffNote),
      const SizedBox(height: 24),
      FilledButton(
        // Reuses the review screen, so typed and recognised text take exactly
        // the same path into the pipeline.
        onPressed: () => context.go('/scan/review', extra: ''),
        child: Text(l10n.manualEnterIngredientTextAction),
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
