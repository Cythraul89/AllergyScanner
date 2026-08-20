import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/scan_input.dart';
import '../../core/providers.dart';
import '../../core/utils/scan_capabilities.dart';
import 'scan_actions.dart';
import 'scan_providers.dart';

/// Editable ingredient text before it is checked.
///
/// Recognition errors are fixed here rather than by re-scanning (R7.3).
class TextReviewScreen extends ConsumerStatefulWidget {
  const TextReviewScreen({required this.initialText, super.key});

  final String initialText;

  @override
  ConsumerState<TextReviewScreen> createState() => _TextReviewScreenState();
}

class _TextReviewScreenState extends ConsumerState<TextReviewScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);
    final bool wasRecognised = widget.initialText.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Check ingredient text')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            wasRecognised
                ? 'Recognised text — correct it if needed'
                : 'No text was recognised. Type or paste the ingredient list.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (capabilities.canRecognizeText)
            OutlinedButton.icon(
              onPressed: () => context.go('/scan/text'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Re-scan'),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _controller.text.trim().isEmpty || _busy ? null : _check,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Check'),
          ),
        ],
      ),
    );
  }

  Future<void> _check() async {
    setState(() => _busy = true);

    final ScanOutcome outcome = await ref.read(scanActionsProvider).evaluate(
      TextInput(
        text: _controller.text,
        // The mode records where the text came from, which the result view and
        // the history show as provenance.
        mode: widget.initialText.isEmpty
            ? ScanInputMode.manualText
            : ScanInputMode.ocr,
      ),
    );

    if (!mounted) return;
    context.go('/scan/result/${outcome.scanId}', extra: outcome.lookupProblem);
  }
}
