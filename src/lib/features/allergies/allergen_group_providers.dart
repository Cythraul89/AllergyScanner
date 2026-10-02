import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/daos/allergen_group_dao.dart';
import '../../core/models/allergen_group.dart';
import '../../core/models/allergen_term.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/services/allergy_list_json_service.dart';
import '../../core/services/translation_service.dart';

/// Groups-with-terms used to live here, on the reasoning that only the
/// Allergies screens needed it. The scan preview and the result view now draw
/// allergen highlights in their group's colour too, so it moved to
/// `core/providers.dart` as `allergenGroupsWithTermsProvider` — `core/` must
/// not import `features/`.

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

  Future<String> create({
    required String label,
    Color? color,
    GroupCriticality? criticality,
  }) async {
    final String id = _uuid.v4();
    final DateTime timestamp = _now();
    await _dao.insertGroup(
      AllergenGroup(
        id: id,
        label: label.trim(),
        color: color,
        criticality: criticality,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    return id;
  }

  Future<void> rename({required String id, required String label}) =>
      _dao.updateLabel(id: id, label: label.trim(), updatedAt: _now());

  /// Always writes both fields — the one screen that edits them always
  /// submits the full appearance state, never a partial update.
  Future<void> setAppearance({
    required String id,
    Color? color,
    GroupCriticality? criticality,
  }) => _dao.setAppearance(
    id: id,
    color: Value(color),
    criticality: Value(criticality),
    updatedAt: _now(),
  );

  /// Member terms are kept, ungrouped — never deleted with the group.
  Future<void> delete(String id) => _dao.deleteById(id);
}

final Provider<AllergyListJsonService> allergyListJsonServiceProvider =
    Provider<AllergyListJsonService>(
      (ref) => AllergyListJsonService(
        database: ref.watch(appDatabaseProvider),
        log: ref.watch(logServiceProvider),
      ),
    );

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
