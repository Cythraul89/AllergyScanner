import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/calculators/text_normalizer.dart';
import '../../core/database/daos/allergen_term_dao.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';

/// Why a term could not be saved. Both cases are user errors with a specific
/// message, not exceptions.
sealed class TermSaveResult {
  const TermSaveResult();
}

final class TermSaved extends TermSaveResult {
  const TermSaved();
}

final class TermTooShort extends TermSaveResult {
  const TermTooShort(this.minimumLength);

  final int minimumLength;
}

final class TermDuplicate extends TermSaveResult {
  const TermDuplicate(this.existingTerm);

  final String existingTerm;
}

final Provider<AllergenTermActions> allergenTermActionsProvider =
    Provider<AllergenTermActions>((ref) {
      return AllergenTermActions(dao: ref.watch(allergenTermDaoProvider));
    });

/// Write side of the allergy list.
class AllergenTermActions {
  AllergenTermActions({
    required AllergenTermDao dao,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _dao = dao,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final AllergenTermDao _dao;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<TermSaveResult> add({required String term, String? note}) async {
    final String normalized = TextNormalizer.normalize(term);
    if (!TextNormalizer.isSearchable(normalized)) {
      return const TermTooShort(TextNormalizer.minimumTermLength);
    }

    final AllergenTerm? existing = await _dao.findByNormalizedTerm(normalized);
    if (existing != null) {
      return TermDuplicate(existing.term);
    }

    final DateTime timestamp = _now();
    await _dao.insertTerm(
      AllergenTerm(
        id: _uuid.v4(),
        term: term.trim(),
        normalizedTerm: normalized,
        isActive: true,
        note: note,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    return const TermSaved();
  }

  Future<TermSaveResult> edit({
    required String id,
    required String term,
    String? note,
  }) async {
    final String normalized = TextNormalizer.normalize(term);
    if (!TextNormalizer.isSearchable(normalized)) {
      return const TermTooShort(TextNormalizer.minimumTermLength);
    }

    final AllergenTerm? existing = await _dao.findByNormalizedTerm(normalized);
    if (existing != null && existing.id != id) {
      return TermDuplicate(existing.term);
    }

    // normalizedTerm is a stored column, so it is rewritten with the term
    // itself — never left behind (R4.3).
    await _dao.updateTerm(
      id: id,
      term: term.trim(),
      normalizedTerm: normalized,
      note: note,
      updatedAt: _now(),
    );
    return const TermSaved();
  }

  Future<void> setActive({required String id, required bool isActive}) =>
      _dao.setActive(id: id, isActive: isActive, updatedAt: _now());

  /// Deleting a term never touches history: past matches keep their snapshot
  /// and their foreign key is cleared (R7.9).
  Future<void> delete(String id) => _dao.deleteById(id);

  /// Used by the undo action after a swipe-to-delete.
  Future<void> restore(AllergenTerm term) => _dao.insertTerm(term);
}
