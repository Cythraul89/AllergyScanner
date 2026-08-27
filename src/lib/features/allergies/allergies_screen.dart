import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/error_view.dart';
import 'allergen_group_providers.dart';
import 'allergies_providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My allergy terms'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New group',
            onPressed: () => context.go('/allergies/groups/add'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/allergies/add'),
        tooltip: 'Add a term',
        child: const Icon(Icons.add),
      ),
      body: _buildBody(groups, ungrouped),
    );
  }

  Widget _buildBody(
    AsyncValue<List<AllergenGroupWithTerms>> groups,
    AsyncValue<List<AllergenTerm>> ungrouped,
  ) {
    if (groups.hasError) {
      return ErrorView(message: 'Could not load your groups: ${groups.error}');
    }
    if (ungrouped.hasError) {
      return ErrorView(message: 'Could not load your terms: ${ungrouped.error}');
    }
    if (!groups.hasValue || !ungrouped.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<AllergenGroupWithTerms> allGroups = groups.value!;
    final List<AllergenTerm> allUngrouped = ungrouped.value!;

    if (allGroups.isEmpty && allUngrouped.isEmpty) {
      return EmptyView(
        icon: Icons.list_alt_outlined,
        title: 'No terms yet',
        message:
            'Add the substances you need to avoid. Only the exact words '
            'you list are searched for, so add each spelling you expect '
            'to see on a pack.',
        actionLabel: 'Add your first term',
        onAction: () => context.go('/allergies/add'),
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
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search',
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) => setState(() => _query = value),
          ),
        ),
        for (final AllergenGroupWithTerms group in visibleGroups)
          _GroupSection(group: group),
        if (visibleUngrouped.isNotEmpty) ...<Widget>[
          const _SectionHeader(label: 'OTHER TERMS'),
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
}

class _GroupSection extends ConsumerWidget {
  const _GroupSection({required this.group});

  final AllergenGroupWithTerms group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          title: Text(
            group.group.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text('${group.terms.length} name(s)'),
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
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => context.go('/allergies/groups/${group.group.id}/edit'),
        ),
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
    await ref.read(allergenTermActionsProvider).delete(term.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${term.term}"'),
        action: SnackBarAction(
          label: 'Undo',
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
