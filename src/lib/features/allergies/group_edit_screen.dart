import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculators/text_normalizer.dart';
import '../../core/constants.dart';
import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
import '../../core/services/translation_service.dart';
import 'allergen_group_providers.dart';
import 'allergies_providers.dart';

/// A name typed or suggested while adding a brand-new group, held only in
/// widget state until Save — a new group is not written to the database a
/// row at a time, so cancelling never leaves an orphaned group behind.
typedef _DraftMember = ({String term, String language});

/// Whether every member of the group named [groupId] shares one
/// active/inactive state — the source of truth for the cascading toggle
/// (a group represents one substance, so it is never partially active).
bool _groupIsActive(List<AllergenGroupWithTerms> all, String groupId) {
  final Iterable<AllergenGroupWithTerms> matches = all.where(
    (AllergenGroupWithTerms g) => g.group.id == groupId,
  );
  return matches.isEmpty || matches.first.isActive;
}

/// Add or edit an allergen group: a label plus its member terms (different
/// names/translations for the same substance). The same full editing
/// experience — members, attaching existing terms, translation suggestions —
/// is available whether the group already exists or is still being created.
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

  /// Only populated while adding a brand-new group (§ typedef above).
  final List<_DraftMember> _draftMembers = <_DraftMember>[];

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

  /// The state new/re-assigned members must adopt — a group's names are
  /// always toggled together, never individually.
  bool _currentGroupIsActive() {
    final String? id = widget.groupId;
    if (id == null) return true;
    final List<AllergenGroupWithTerms> all =
        ref.read(allAllergenGroupsProvider).valueOrNull ?? const [];
    return _groupIsActive(all, id);
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
          const SizedBox(height: 24),
          Text('Names in this group', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _isEditing ? _MemberList(groupId: widget.groupId!) : _buildDraftMembers(),
          if (_isEditing) ...<Widget>[
            const SizedBox(height: 8),
            _AttachExistingTerm(groupId: widget.groupId!),
          ],
          const SizedBox(height: 24),
          Text('Add a new name', style: Theme.of(context).textTheme.titleSmall),
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

  Widget _buildDraftMembers() {
    if (_draftMembers.isEmpty) {
      return const Text('No names yet.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _draftMembers
          .map(
            (_DraftMember member) => InputChip(
              label: Text(member.term),
              onDeleted: () => setState(() => _draftMembers.remove(member)),
            ),
          )
          .toList(growable: false),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
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
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _addingTerm ? null : _addAllSuggestions,
            child: Text('Add all (${successes.length})'),
          ),
        ],
      ),
    );
  }

  Future<void> _addTerm() async {
    final String text = _newTermController.text;
    if (text.trim().isEmpty) return;

    if (!_isEditing) {
      _addDraft(term: text, language: _newTermLanguage);
      return;
    }

    setState(() => _addingTerm = true);
    final TermSaveResult result = await ref
        .read(allergenTermActionsProvider)
        .add(
          term: text,
          groupId: widget.groupId,
          isActive: _currentGroupIsActive(),
        );
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

  /// Add-mode only: validates and appends to the local draft list, with no
  /// database write yet — duplicates against *other, already-saved* groups
  /// or terms only surface at Save time (§_save).
  void _addDraft({required String term, required String language}) {
    final String normalized = TextNormalizer.normalize(term);
    if (!TextNormalizer.isSearchable(normalized)) {
      setState(
        () => _newTermError =
            'Use at least ${TextNormalizer.minimumTermLength} characters.',
      );
      return;
    }
    final bool duplicate = _draftMembers.any(
      (_DraftMember m) => TextNormalizer.normalize(m.term) == normalized,
    );
    if (duplicate) {
      setState(() => _newTermError = 'Already added.');
      return;
    }
    setState(() {
      _draftMembers.add((term: term.trim(), language: language));
      _newTermController.clear();
      _suggestions = null;
    });
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

  Future<void> _addAllSuggestions() async {
    final Map<String, TranslationResult> suggestions = _suggestions ?? {};
    final List<MapEntry<String, TranslationSuccess>> successes = suggestions
        .entries
        .where((entry) => entry.value is TranslationSuccess)
        .map(
          (entry) =>
              MapEntry(entry.key, entry.value as TranslationSuccess),
        )
        .toList(growable: false);
    if (successes.isEmpty) return;

    setState(() => _addingTerm = true);
    int added = 0;
    int skipped = 0;

    if (_isEditing) {
      final bool groupActive = _currentGroupIsActive();
      for (final MapEntry<String, TranslationSuccess> entry in successes) {
        final TermSaveResult result = await ref
            .read(allergenTermActionsProvider)
            .add(
              term: entry.value.translatedText,
              groupId: widget.groupId,
              isActive: groupActive,
            );
        if (result is TermSaved) {
          added++;
        } else {
          skipped++;
        }
      }
    } else {
      for (final MapEntry<String, TranslationSuccess> entry in successes) {
        final String normalized = TextNormalizer.normalize(
          entry.value.translatedText,
        );
        final bool duplicate =
            !TextNormalizer.isSearchable(normalized) ||
            _draftMembers.any(
              (_DraftMember m) =>
                  TextNormalizer.normalize(m.term) == normalized,
            );
        if (duplicate) {
          skipped++;
        } else {
          _draftMembers.add(
            (term: entry.value.translatedText, language: entry.key),
          );
          added++;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _suggestions = null;
      _addingTerm = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0
              ? 'Added $added name(s).'
              : 'Added $added name(s), skipped $skipped already on your list.',
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _labelError = 'Enter a group name.');
      return;
    }
    setState(() => _saving = true);

    final AllergenGroupActions groupActions = ref.read(
      allergenGroupActionsProvider,
    );
    if (_isEditing) {
      await groupActions.rename(id: widget.groupId!, label: label);
      if (!mounted) return;
      context.pop();
      return;
    }

    final String newGroupId = await groupActions.create(label: label);
    int skipped = 0;
    final AllergenTermActions termActions = ref.read(
      allergenTermActionsProvider,
    );
    for (final _DraftMember member in _draftMembers) {
      final TermSaveResult result = await termActions.add(
        term: member.term,
        groupId: newGroupId,
        isActive: true,
      );
      if (result is! TermSaved) skipped++;
    }
    if (!mounted) return;
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$skipped name(s) were already on your list and were not added.',
          ),
        ),
      );
    }
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
          onChanged: (String? termId) async {
            if (termId == null) return;
            // Read the group's current state before the attach so the
            // cascade reflects its pre-existing members, not the just-moved
            // term's own (possibly different) prior state.
            final List<AllergenGroupWithTerms> all =
                ref.read(allAllergenGroupsProvider).valueOrNull ?? const [];
            final bool groupActive = _groupIsActive(all, groupId);
            final AllergenTermActions actions = ref.read(
              allergenTermActionsProvider,
            );
            await actions.setGroup(id: termId, groupId: groupId);
            await actions.setActiveForGroup(
              groupId: groupId,
              isActive: groupActive,
            );
          },
        );
      },
    );
  }
}
