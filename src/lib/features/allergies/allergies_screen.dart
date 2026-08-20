import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/error_view.dart';
import 'allergies_providers.dart';

/// The user's allergy list: active entries first, then inactive.
class AllergiesScreen extends ConsumerStatefulWidget {
  const AllergiesScreen({super.key});

  @override
  ConsumerState<AllergiesScreen> createState() => _AllergiesScreenState();
}

class _AllergiesScreenState extends ConsumerState<AllergiesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AllergenTerm>> terms = ref.watch(
      allAllergenTermsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My allergy terms')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/allergies/add'),
        tooltip: 'Add a term',
        child: const Icon(Icons.add),
      ),
      body: terms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            ErrorView(message: 'Could not load your terms: $error'),
        data: (List<AllergenTerm> all) {
          if (all.isEmpty) {
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

          final List<AllergenTerm> visible = _filter(all);
          final List<AllergenTerm> active = visible
              .where((AllergenTerm term) => term.isActive)
              .toList(growable: false);
          final List<AllergenTerm> inactive = visible
              .where((AllergenTerm term) => !term.isActive)
              .toList(growable: false);

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
              if (active.isNotEmpty)
                _SectionHeader(label: 'ACTIVE (${active.length})'),
              ...active.map(_buildTile),
              if (inactive.isNotEmpty)
                _SectionHeader(label: 'INACTIVE (${inactive.length})'),
              ...inactive.map(_buildTile),
            ],
          );
        },
      ),
    );
  }

  List<AllergenTerm> _filter(List<AllergenTerm> all) {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return all;
    return all
        .where(
          (AllergenTerm term) => term.term.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  Widget _buildTile(AllergenTerm term) {
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
      onDismissed: (_) => _delete(term),
      child: ListTile(
        title: Text(term.term),
        subtitle: term.note == null ? null : Text(term.note!),
        trailing: Switch(
          value: term.isActive,
          onChanged: (bool value) => ref
              .read(allergenTermActionsProvider)
              .setActive(id: term.id, isActive: value),
        ),
        onTap: () => context.go('/allergies/${term.id}/edit'),
      ),
    );
  }

  Future<void> _delete(AllergenTerm term) async {
    await ref.read(allergenTermActionsProvider).delete(term.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${term.term}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(allergenTermActionsProvider).restore(term),
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
