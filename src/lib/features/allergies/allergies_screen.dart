import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/services/allergy_list_json_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/error_view.dart';
import '../../l10n/app_localizations.dart';
import 'allergen_group_providers.dart';
import 'allergies_providers.dart';

enum _AllergyListMenuAction { exportJson, importJson }

/// The user's allergy list: one section per group, then ungrouped terms.
class AllergiesScreen extends ConsumerStatefulWidget {
  const AllergiesScreen({super.key});

  @override
  ConsumerState<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends ConsumerState<AllergiesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AllergenGroupWithTerms>> groups = ref.watch(
      allAllergenGroupsProvider,
    );
    final AsyncValue<List<AllergenTerm>> ungrouped = ref.watch(
      ungroupedAllergenTermsProvider,
    );

    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.allergiesTitle),
        actions: <Widget>[
          PopupMenuButton<_AllergyListMenuAction>(
            onSelected: (_AllergyListMenuAction action) {
              switch (action) {
                case _AllergyListMenuAction.exportJson:
                  _exportList(l10n);
                case _AllergyListMenuAction.importJson:
                  _importList(l10n);
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_AllergyListMenuAction>>[
                  PopupMenuItem<_AllergyListMenuAction>(
                    value: _AllergyListMenuAction.exportJson,
                    child: Text(l10n.allergiesExportAction),
                  ),
                  PopupMenuItem<_AllergyListMenuAction>(
                    value: _AllergyListMenuAction.importJson,
                    child: Text(l10n.allergiesImportAction),
                  ),
                ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/allergies/groups/add'),
        tooltip: l10n.allergiesAddGroupTooltip,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(groups, ungrouped, l10n),
    );
  }

  Widget _buildBody(
    AsyncValue<List<AllergenGroupWithTerms>> groups,
    AsyncValue<List<AllergenTerm>> ungrouped,
    AppLocalizations l10n,
  ) {
    if (groups.hasError) {
      return ErrorView(
        message: l10n.allergiesGroupsLoadError(groups.error.toString()),
      );
    }
    if (ungrouped.hasError) {
      return ErrorView(
        message: l10n.allergiesTermsLoadError(ungrouped.error.toString()),
      );
    }
    if (!groups.hasValue || !ungrouped.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<AllergenGroupWithTerms> allGroups = groups.value!;
    final List<AllergenTerm> allUngrouped = ungrouped.value!;

    if (allGroups.isEmpty && allUngrouped.isEmpty) {
      return EmptyView(
        icon: Icons.list_alt_outlined,
        title: l10n.allergiesEmptyTitle,
        message: l10n.allergiesEmptyMessage,
        actionLabel: l10n.allergiesEmptyActionLabel,
        onAction: () => context.go('/allergies/groups/add'),
      );
    }

    final String needle = _query.trim().toLowerCase();
    final List<AllergenGroupWithTerms> visibleGroups = needle.isEmpty
        ? allGroups
        : allGroups
              .where(
                (AllergenGroupWithTerms g) =>
                    g.group.label.toLowerCase().contains(needle) ||
                    g.terms.any(
                      (AllergenTerm t) =>
                          t.term.toLowerCase().contains(needle),
                    ),
              )
              .toList(growable: false);
    final List<AllergenTerm> visibleUngrouped = _filter(allUngrouped);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: l10n.commonSearch,
              border: const OutlineInputBorder(),
            ),
            onChanged: (String value) => setState(() => _query = value),
          ),
        ),
        for (final AllergenGroupWithTerms group in visibleGroups)
          _GroupSection(key: ValueKey<String>(group.group.id), group: group),
        if (visibleUngrouped.isNotEmpty) ...<Widget>[
          _SectionHeader(label: l10n.allergiesOtherTermsHeading),
          ...visibleUngrouped.map(
            (AllergenTerm term) => _TermTile(term: term),
          ),
        ],
      ],
    );
  }

  List<AllergenTerm> _filter(List<AllergenTerm> all) {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return all;
    return all
        .where((AllergenTerm term) => term.term.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  Future<void> _exportList(AppLocalizations l10n) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final File file = await ref
          .read(allergyListJsonServiceProvider)
          .exportToFile();
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path)]),
      );
    } on Object catch (cause) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.allergiesExportFailed(cause.toString()))),
      );
    }
  }

  Future<void> _importList(AppLocalizations l10n) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    final String? path = picked?.path;
    if (path == null || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final AllergyListImportOutcome outcome = await ref
          .read(allergyListJsonServiceProvider)
          .importFromFile(File(path));
      messenger.showSnackBar(
        SnackBar(content: Text(_describeOutcome(l10n, outcome))),
      );
    } on AllergyListFormatException catch (exception) {
      messenger.showSnackBar(
        SnackBar(content: Text(_describeProblem(l10n, exception.problem))),
      );
    } on Object catch (cause) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.allergiesImportFailed(cause.toString()))),
      );
    }
  }

  /// Three independent sentences rather than one combinatorial message:
  /// "already on your list" and "could not be read" are different facts, and
  /// reporting a dropped entry as a duplicate would tell the user an allergen
  /// is covered when it is not.
  static String _describeOutcome(
    AppLocalizations l10n,
    AllergyListImportOutcome outcome,
  ) {
    final StringBuffer buffer = StringBuffer(
      l10n.allergiesImportedCount(outcome.termsAdded, outcome.groupsCreated),
    );
    if (outcome.hasSkipped) {
      buffer.write(' ${l10n.allergiesImportSkipped(outcome.termsSkipped)}');
    }
    if (outcome.hasRejected) {
      buffer.write(
        ' ${l10n.allergiesImportRejected(outcome.termsRejected, outcome.groupsRejected)}',
      );
    }
    return buffer.toString();
  }

  static String _describeProblem(
    AppLocalizations l10n,
    AllergyListFormatProblem problem,
  ) {
    switch (problem) {
      case AllergyListContentInvalid():
        return l10n.allergiesImportProblemContentInvalid;
      case AllergyListFormatTooNew():
        return l10n.allergiesImportProblemFormatTooNew;
    }
  }
}

class _GroupSection extends ConsumerStatefulWidget {
  const _GroupSection({super.key, required this.group});

  final AllergenGroupWithTerms group;

  @override
  ConsumerState<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends ConsumerState<_GroupSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final AllergenGroupWithTerms group = widget.group;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          leading: group.group.color == null
              ? null
              : CircleAvatar(radius: 10, backgroundColor: group.group.color),
          title: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  group.group.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (group.group.criticality != null) ...<Widget>[
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    Formatters.criticalityLabel(l10n, group.group.criticality!),
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          subtitle: Text(l10n.allergiesGroupNameCount(group.terms.length)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // A group is one substance — its names are toggled together,
              // never individually (see AllergenGroupWithTerms.isActive).
              Switch(
                value: group.isActive,
                onChanged: (bool value) => ref
                    .read(allergenTermActionsProvider)
                    .setActiveForGroup(groupId: group.group.id, isActive: value),
              ),
              IconButton(
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                tooltip: _expanded
                    ? l10n.allergiesCollapseTooltip
                    : l10n.allergiesExpandTooltip,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          onTap: () => context.go('/allergies/groups/${group.group.id}/edit'),
        ),
        if (_expanded)
          ...group.terms.map(
            (AllergenTerm term) => _TermTile(term: term, showActiveSwitch: false),
          ),
      ],
    );
  }
}

class _TermTile extends ConsumerWidget {
  const _TermTile({required this.term, this.showActiveSwitch = true});

  final AllergenTerm term;

  /// `false` for a term shown inside a group section — only the group as a
  /// whole is toggled there.
  final bool showActiveSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey<String>(term.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.delete_outline),
          ),
        ),
      ),
      onDismissed: (_) => _delete(context, ref),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        title: Text(term.term),
        subtitle: term.note == null ? null : Text(term.note!),
        trailing: showActiveSwitch
            ? Switch(
                value: term.isActive,
                onChanged: (bool value) => ref
                    .read(allergenTermActionsProvider)
                    .setActive(id: term.id, isActive: value),
              )
            : null,
        onTap: () => context.go('/allergies/${term.id}/edit'),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    await ref.read(allergenTermActionsProvider).delete(term.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.allergiesDeletedSnackbar(term.term)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => ref.read(allergenTermActionsProvider).restore(term),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
