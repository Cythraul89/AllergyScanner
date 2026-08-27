import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/daos/allergen_group_dao.dart';
import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/providers.dart';
import '../../core/services/translation_service.dart';

/// Here rather than in `core/`: only the Allergies feature's screens read
/// grouped-with-terms data — unlike `allAllergenTermsProvider`, which the
/// scan flow and result view also need.

final StreamProvider<List<AllergenGroupWithTerms>> allAllergenGroupsProvider =
    StreamProvider<List<AllergenGroupWithTerms>>(
      (ref) => ref.watch(allergenGroupDaoProvider).watchAllWithTerms(),
    );

final StreamProvider<List<AllergenTerm>> ungroupedAllergenTermsProvider =
    StreamProvider<List<AllergenTerm>>(
      (ref) => ref.watch(allergenTermDaoProvider).watchUngrouped(),
    );

final Provider<AllergenGroupActions> allergenGroupActionsProvider =
    Provider<AllergenGroupActions>(
      (ref) => AllergenGroupActions(dao: ref.watch(allergenGroupDaoProvider)),
    );

/// Write side of allergen groups.
class AllergenGroupActions {
  AllergenGroupActions({
    required AllergenGroupDao dao,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _dao = dao,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final AllergenGroupDao _dao;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<String> create({required String label}) async {
    final String id = _uuid.v4();
    final DateTime timestamp = _now();
    await _dao.insertGroup(
      AllergenGroup(
        id: id,
        label: label.trim(),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    return id;
  }

  Future<void> rename({required String id, required String label}) =>
      _dao.updateLabel(id: id, label: label.trim(), updatedAt: _now());

  /// Member terms are kept, ungrouped — never deleted with the group.
  Future<void> delete(String id) => _dao.deleteById(id);
}

final Provider<TranslationSuggestionService> translationSuggestionsProvider =
    Provider<TranslationSuggestionService>(
      (ref) => TranslationSuggestionService(
        service: ref.watch(translationServiceProvider),
      ),
    );

/// Fans one typed name out to the other supported languages in parallel; one
/// failing call must not blank the other suggestions.
class TranslationSuggestionService {
  TranslationSuggestionService({required TranslationService service})
    : _service = service;

  final TranslationService _service;

  Future<Map<String, TranslationResult>> suggest({
    required String text,
    required String sourceLanguage,
    required List<String> targetLanguages,
  }) async {
    final Iterable<String> targets = targetLanguages.where(
      (String language) => language != sourceLanguage,
    );
    final List<MapEntry<String, TranslationResult>> entries = await Future.wait(
      targets.map((String language) async {
        final TranslationResult result = await _service.translate(
          text: text,
          sourceLanguage: sourceLanguage,
          targetLanguage: language,
        );
        return MapEntry<String, TranslationResult>(language, result);
      }),
    );
    return Map<String, TranslationResult>.fromEntries(entries);
  }
}
