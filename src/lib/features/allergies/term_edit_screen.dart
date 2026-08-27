import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/text_normalizer.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Edit term')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _termController,
                  decoration: InputDecoration(
                    labelText: 'Term',
                    border: const OutlineInputBorder(),
                    helperText:
                        'At least ${TextNormalizer.minimumTermLength} characters',
                    errorText: _errorMessage,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
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
                            'Only this exact word is searched for. Add '
                            '"corylus avellana" or "E322" as separate terms if '
                            'you need them.',
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
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: longEnough && !_saving ? _save : null,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

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
          _errorMessage = 'Use at least $minimum characters.';
        });
      case TermDuplicate(existingTerm: final String existing):
        setState(() {
          _saving = false;
          _errorMessage = '"$existing" is already on your list.';
        });
    }
  }
}
