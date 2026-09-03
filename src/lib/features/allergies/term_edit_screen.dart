import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/text_normalizer.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import 'allergies_providers.dart';

/// Edit one allergy term's text and note.
///
/// A new term is always created as (at least) a group of one, via
/// `GroupEditScreen` — there is no separate "add a standalone term" flow.
/// This screen is reached only for an existing term, grouped or not.
///
/// The note about exact-word matching is required copy, not decoration: it is
/// the user-facing form of the accepted matching limitation (REQUIREMENTS §5.4).
class TermEditScreen extends ConsumerStatefulWidget {
  const TermEditScreen({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<TermEditScreen> createState() => _TermEditScreenState();
}

class _TermEditScreenState extends ConsumerState<TermEditScreen> {
  final TextEditingController _termController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _termController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AllergenTerm? term = await ref
        .read(allergenTermDaoProvider)
        .findById(widget.termId);
    if (!mounted) return;
    setState(() {
      _termController.text = term?.term ?? '';
      _noteController.text = term?.note ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String normalized = TextNormalizer.normalize(_termController.text);
    final bool longEnough = TextNormalizer.isSearchable(normalized);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.termEditTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _termController,
                  decoration: InputDecoration(
                    labelText: l10n.termFieldLabel,
                    border: const OutlineInputBorder(),
                    helperText: l10n.termMinLengthHelper(
                      TextNormalizer.minimumTermLength,
                    ),
                    errorText: _errorMessage,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: l10n.termNoteLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.termExactWordNote,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: longEnough && !_saving ? _save : null,
                      child: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AllergenTermActions actions = ref.read(
      allergenTermActionsProvider,
    );
    final String? note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    final TermSaveResult result = await actions.edit(
      id: widget.termId,
      term: _termController.text,
      note: note,
    );

    if (!mounted) return;

    switch (result) {
      case TermSaved():
        context.pop();
      case TermTooShort(minimumLength: final int minimum):
        setState(() {
          _saving = false;
          _errorMessage = l10n.termTooShortError(minimum);
        });
      case TermDuplicate(existingTerm: final String existing):
        setState(() {
          _saving = false;
          _errorMessage = l10n.termDuplicateError(existing);
        });
    }
  }
}
