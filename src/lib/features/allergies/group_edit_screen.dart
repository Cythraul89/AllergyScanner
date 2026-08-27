import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
import '../../core/services/translation_service.dart';
import 'allergen_group_providers.dart';
import 'allergies_providers.dart';

/// Add or edit an allergen group: a label plus its member terms (different
/// names/translations for the same substance).
class GroupEditScreen extends ConsumerStatefulWidget {
  const GroupEditScreen({this.groupId, super.key});

  /// `null` when adding.
  final String? groupId;

  @override
  ConsumerState<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends ConsumerState<GroupEditScreen> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _newTermController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _addingTerm = false;
  bool _suggesting = false;
  String? _labelError;
  String? _newTermError;
  String _newTermLanguage = 'en';
  Map<String, TranslationResult>? _suggestions;

  bool get _isEditing => widget.groupId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _newTermController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _newTermLanguage = ref
        .read(currentSettingsProvider)
        .preferredIngredientsLanguage;
    final String? id = widget.groupId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    final AllergenGroup? group = await ref
        .read(allergenGroupDaoProvider)
        .findById(id);
    if (!mounted) return;
    setState(() {
      _labelController.text = group?.label ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Edit group' : 'Add a group')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool remoteLookupEnabled = ref.watch(
      currentSettingsProvider.select((s) => s.remoteLookupEnabled),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit group' : 'Add a group'),
        actions: <Widget>[
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete group',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _labelController,
            autofocus: !_isEditing,
            decoration: InputDecoration(
              labelText: 'Group name',
              border: const OutlineInputBorder(),
              helperText: 'e.g. "Hazelnut" — shown as the group header',
              errorText: _labelError,
            ),
            onChanged: (_) => setState(() => _labelError = null),
          ),
          if (_isEditing) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              'Names in this group',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _MemberList(groupId: widget.groupId!),
            const SizedBox(height: 8),
            _AttachExistingTerm(groupId: widget.groupId!),
            const SizedBox(height: 24),
            Text(
              'Add a new name',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildAddTermRow(remoteLookupEnabled),
            if (!remoteLookupEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Translation suggestions need remote lookup, which is '
                  'turned off in Settings.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            if (_suggestions != null) _buildSuggestions(),
          ],
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
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddTermRow(bool remoteLookupEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _newTermController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: const OutlineInputBorder(),
                  errorText: _newTermError,
                ),
                onChanged: (_) => setState(() => _newTermError = null),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _newTermLanguage,
              items: kSupportedAllergenLanguages
                  .map(
                    (String language) => DropdownMenuItem<String>(
                      value: language,
                      child: Text(language.toUpperCase()),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                if (value != null) setState(() => _newTermLanguage = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: _addingTerm ? null : _addTerm,
              child: const Text('Add'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: remoteLookupEnabled && !_suggesting
                  ? _suggestTranslations
                  : null,
              icon: const Icon(Icons.translate),
              label: Text(_suggesting ? 'Suggesting…' : 'Suggest translations'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    final Map<String, TranslationResult> suggestions = _suggestions!;
    final List<MapEntry<String, TranslationSuccess>> successes = suggestions
        .entries
        .where((entry) => entry.value is TranslationSuccess)
        .map(
          (entry) =>
              MapEntry(entry.key, entry.value as TranslationSuccess),
        )
        .toList(growable: false);
    if (successes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('No translation suggestions right now.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: successes
            .map(
              (entry) => ActionChip(
                label: Text(
                  '${entry.key.toUpperCase()}: ${entry.value.translatedText}',
                ),
                onPressed: () => setState(() {
                  _newTermController.text = entry.value.translatedText;
                  _newTermLanguage = entry.key;
                  _suggestions = null;
                }),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _addTerm() async {
    if (_newTermController.text.trim().isEmpty) return;
    setState(() => _addingTerm = true);
    final TermSaveResult result = await ref
        .read(allergenTermActionsProvider)
        .add(term: _newTermController.text, groupId: widget.groupId);
    if (!mounted) return;
    switch (result) {
      case TermSaved():
        setState(() {
          _newTermController.clear();
          _suggestions = null;
          _addingTerm = false;
        });
      case TermTooShort(minimumLength: final int minimum):
        setState(() {
          _newTermError = 'Use at least $minimum characters.';
          _addingTerm = false;
        });
      case TermDuplicate(existingTerm: final String existing):
        setState(() {
          _newTermError = '"$existing" is already on your list.';
          _addingTerm = false;
        });
    }
  }

  Future<void> _suggestTranslations() async {
    final String text = _newTermController.text.trim();
    if (text.isEmpty) return;
    setState(() => _suggesting = true);
    final Map<String, TranslationResult> suggestions = await ref
        .read(translationSuggestionsProvider)
        .suggest(
          text: text,
          sourceLanguage: _newTermLanguage,
          targetLanguages: kSupportedAllergenLanguages,
        );
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _suggesting = false;
    });
  }

  Future<void> _save() async {
    final String label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _labelError = 'Enter a group name.');
      return;
    }
    setState(() => _saving = true);

    final AllergenGroupActions actions = ref.read(
      allergenGroupActionsProvider,
    );
    if (_isEditing) {
      await actions.rename(id: widget.groupId!, label: label);
    } else {
      await actions.create(label: label);
    }
    if (!mounted) return;
    context.pop();
  }

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete group?'),
        content: const Text(
          'The names in this group are kept on your allergy list, just no '
          'longer grouped together.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(allergenGroupActionsProvider).delete(widget.groupId!);
    if (!mounted) return;
    context.pop();
  }
}

class _MemberList extends ConsumerWidget {
  const _MemberList({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AllergenGroupWithTerms>> groups = ref.watch(
      allAllergenGroupsProvider,
    );
    return groups.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => Text('Could not load: $error'),
      data: (List<AllergenGroupWithTerms> all) {
        final Iterable<AllergenGroupWithTerms> matches = all.where(
          (AllergenGroupWithTerms g) => g.group.id == groupId,
        );
        final List<AllergenTerm> terms = matches.isEmpty
            ? const []
            : matches.first.terms;
        if (terms.isEmpty) {
          return const Text('No names yet.');
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: terms
              .map(
                (AllergenTerm term) => InputChip(
                  label: Text(term.term),
                  onDeleted: () => ref
                      .read(allergenTermActionsProvider)
                      .setGroup(id: term.id, groupId: null),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _AttachExistingTerm extends ConsumerWidget {
  const _AttachExistingTerm({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AllergenTerm>> ungrouped = ref.watch(
      ungroupedAllergenTermsProvider,
    );
    return ungrouped.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace _) => const SizedBox.shrink(),
      data: (List<AllergenTerm> terms) {
        if (terms.isEmpty) return const SizedBox.shrink();
        return DropdownButton<String>(
          hint: const Text('Attach an existing term'),
          items: terms
              .map(
                (AllergenTerm term) => DropdownMenuItem<String>(
                  value: term.id,
                  child: Text(term.term),
                ),
              )
              .toList(growable: false),
          onChanged: (String? termId) {
            if (termId == null) return;
            ref
                .read(allergenTermActionsProvider)
                .setGroup(id: termId, groupId: groupId);
          },
        );
      },
    );
  }
}
