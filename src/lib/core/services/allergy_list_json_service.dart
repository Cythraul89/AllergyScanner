import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../calculators/text_normalizer.dart';
import '../database/app_database.dart';
import '../database/daos/allergen_group_dao.dart';
import '../database/daos/allergen_term_dao.dart';
import '../models/allergen_group.dart';
import '../models/allergen_term.dart';
import '../models/enums.dart';
import '../utils/formatters.dart';
import 'log_service.dart';

/// Raised when a file is not usable allergy-list JSON. Carries a structured
/// [problem] rather than a hardcoded message — same reasoning as
/// `BackupFormatException`: this service has no `BuildContext` to localise
/// text with, so the caller (which does) maps [problem] to a displayed
/// string.
class AllergyListFormatException implements Exception {
  const AllergyListFormatException(this.problem);

  final AllergyListFormatProblem problem;

  @override
  String toString() => problem.toString();
}

sealed class AllergyListFormatProblem {
  const AllergyListFormatProblem();
}

/// The text is not valid JSON, or not a JSON object.
final class AllergyListContentInvalid extends AllergyListFormatProblem {
  const AllergyListContentInvalid();
}

/// The file's `allergyListFormatVersion` is newer than this app's.
final class AllergyListFormatTooNew extends AllergyListFormatProblem {
  const AllergyListFormatTooNew({
    required this.fileFormatVersion,
    required this.appFormatVersion,
  });

  final int fileFormatVersion;
  final int appFormatVersion;
}

/// What a merge-import did. Never destructive: an existing group is matched
/// by its (trimmed, case-insensitive) label and reused rather than
/// duplicated, and an existing term is never overwritten.
///
/// [termsSkipped] and [termsRejected] are deliberately separate: "already on
/// your list" and "this entry could not be read" are different facts, and
/// reporting the second as the first would tell a user an allergen is covered
/// when it was actually dropped.
class AllergyListImportOutcome {
  const AllergyListImportOutcome({
    required this.groupsCreated,
    required this.termsAdded,
    required this.termsSkipped,
    this.termsRejected = 0,
    this.groupsRejected = 0,
  });

  final int groupsCreated;
  final int termsAdded;

  /// Already on the list, by normalised form (R4.1).
  final int termsSkipped;

  /// Missing/ill-typed `term`, or outside the 1–200 character column bound.
  final int termsRejected;

  /// Group entries whose own header was unusable. Their member terms are
  /// still imported, ungrouped — never dropped.
  final int groupsRejected;

  bool get hasSkipped => termsSkipped > 0;

  bool get hasRejected => termsRejected > 0 || groupsRejected > 0;
}

/// Why one term entry did not become a row — see [AllergyListImportOutcome].
enum _TermStatus { added, duplicate, rejected }

/// Export/import of just the user's allergy list (groups + terms) as a
/// standalone JSON file — distinct from `BackupService`'s full-app ZIP
/// archive. Meant for sharing a list between devices or people (e.g. with a
/// caregiver or a school), so it carries no internal id, grouping is matched
/// by label rather than id, and import always merges: it never deletes or
/// overwrites anything already on the device (doc/ARCHITECTURE.md §5.18).
class AllergyListJsonService {
  AllergyListJsonService({
    required AppDatabase database,
    required LogService log,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _database = database,
       _log = log,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  /// Version of this JSON layout, independent of the database schema version
  /// and of `BackupService.backupFormatVersion`.
  static const int allergyListFormatVersion = 1;

  /// `allergen_terms.term` and `allergen_groups.label` are both
  /// `withLength(min: 1, max: 200)`, and drift enforces that in Dart — an
  /// over-long value from a file would throw `InvalidDataException` out of
  /// the insert rather than being reported as a skipped entry.
  static const int _maxTextLength = 200;

  /// Held only for [AppDatabase.transaction]; every read and write still goes
  /// through a DAO, so no drift row or companion type reaches this layer.
  final AppDatabase _database;
  final LogService _log;
  final Uuid _uuid;
  final DateTime Function() _now;

  AllergenGroupDao get _groupDao => _database.allergenGroupDao;
  AllergenTermDao get _termDao => _database.allergenTermDao;

  Future<String> exportToJson() async {
    final List<AllergenGroupWithTerms> groups = await _groupDao
        .getAllWithTerms();
    final List<AllergenTerm> ungrouped = await _termDao.watchUngrouped().first;

    final Map<String, Object?> payload = <String, Object?>{
      'app': 'AllergyScanner',
      'allergyListFormatVersion': allergyListFormatVersion,
      'exportedAt': _now().toUtc().toIso8601String(),
      'groups': groups
          .map(
            (AllergenGroupWithTerms g) => <String, Object?>{
              'label': g.group.label,
              'color': g.group.color?.toARGB32(),
              'criticality': g.group.criticality?.name,
              'terms': g.terms.map(_termJson).toList(growable: false),
            },
          )
          .toList(growable: false),
      'ungroupedTerms': ungrouped.map(_termJson).toList(growable: false),
    };

    _log.info(
      'Exported allergy list: ${groups.length} groups, '
      '${ungrouped.length} ungrouped terms',
    );
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes the export into the app documents directory and returns it.
  Future<File> exportToFile() async {
    final String json = await exportToJson();
    final Directory directory = await getApplicationDocumentsDirectory();
    final String name = fileName(_now());
    final File target = File(path_helper.join(directory.path, name));
    await target.writeAsString(json, flush: true);
    return target;
  }

  /// `allergy_list_YYYYMMDD_HHmmss.json` — matches `BackupService`'s naming
  /// style.
  static String fileName(DateTime at) =>
      'allergy_list_${Formatters.fileTimestamp(at)}.json';

  static Map<String, Object?> _termJson(AllergenTerm term) => <String, Object?>{
    'term': term.term,
    'note': term.note,
    'isActive': term.isActive,
  };

  Future<AllergyListImportOutcome> importFromFile(File file) async =>
      importFromJson(await file.readAsString());

  Future<AllergyListImportOutcome> importFromJson(String jsonText) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on Object catch (cause) {
      _log.warn('Allergy list import failed to parse: $cause');
      throw const AllergyListFormatException(AllergyListContentInvalid());
    }
    if (decoded is! Map) {
      throw const AllergyListFormatException(AllergyListContentInvalid());
    }
    final Map<String, Object?> payload = decoded.cast<String, Object?>();

    final int fileFormatVersion =
        _asInt(payload['allergyListFormatVersion']) ?? 1;
    if (fileFormatVersion > allergyListFormatVersion) {
      throw AllergyListFormatException(
        AllergyListFormatTooNew(
          fileFormatVersion: fileFormatVersion,
          appFormatVersion: allergyListFormatVersion,
        ),
      );
    }

    // A JSON object with neither list is not an allergy list at all — without
    // this, picking an arbitrary .json file "succeeds" with "Added 0 terms".
    if (payload['groups'] is! List && payload['ungroupedTerms'] is! List) {
      throw const AllergyListFormatException(AllergyListContentInvalid());
    }

    // One transaction, so a file that turns out to be malformed half-way
    // through cannot leave a half-merged list behind — same guarantee
    // BackupService._applyPayload gives.
    return _database.transaction(() => _merge(payload));
  }

  Future<AllergyListImportOutcome> _merge(Map<String, Object?> payload) async {
    int groupsCreated = 0;
    int groupsRejected = 0;
    int termsAdded = 0;
    int termsSkipped = 0;
    int termsRejected = 0;

    void tally(_TermStatus status) {
      switch (status) {
        case _TermStatus.added:
          termsAdded++;
        case _TermStatus.duplicate:
          termsSkipped++;
        case _TermStatus.rejected:
          termsRejected++;
      }
    }

    // Loaded once and kept in sync locally (hence the growable copy), so a
    // file that lists the same group label twice merges into one group
    // instead of creating two.
    final List<AllergenGroupWithTerms> existingGroups = List
        <AllergenGroupWithTerms>.of(await _groupDao.getAllWithTerms());

    for (final Object? entry in _asList(payload['groups'])) {
      final Map<String, Object?>? groupJson = _asMap(entry);
      final String? label = _asString(groupJson?['label'])?.trim();
      final List<Object?> termEntries = _asList(groupJson?['terms']);

      // An unusable group header must not take its members down with it:
      // import them ungrouped rather than silently dropping allergens.
      if (label == null || label.isEmpty || label.length > _maxTextLength) {
        groupsRejected++;
        for (final Object? termEntry in termEntries) {
          tally(await _importTerm(termEntry, groupId: null, isActive: null));
        }
        continue;
      }

      final String normalizedLabel = label.toLowerCase();
      AllergenGroupWithTerms? match;
      for (final AllergenGroupWithTerms g in existingGroups) {
        if (g.group.label.trim().toLowerCase() == normalizedLabel) {
          match = g;
          break;
        }
      }

      // A group is one substance, so its members share one active state
      // (AllergenGroupWithTerms.isActive). Merging into an existing group
      // adopts that group's current state; a brand-new group honours the
      // file only when every member in it is inactive. Taking isActive per
      // term would leave the group's switch disagreeing with what is
      // actually matched.
      final bool groupActive =
          match?.isActive ??
          !(termEntries.isNotEmpty &&
              termEntries.every(
                (Object? t) => _asBool(_asMap(t)?['isActive']) == false,
              ));

      String? groupId = match?.group.id;

      // Created lazily: a group whose members all turn out to be duplicates
      // would otherwise leave a permanently empty group behind. An entry that
      // genuinely carries no terms still round-trips as an empty group.
      Future<String> ensureGroup() async {
        final String? existing = groupId;
        if (existing != null) return existing;
        final DateTime timestamp = _now();
        final AllergenGroup created = AllergenGroup(
          id: _uuid.v4(),
          label: label,
          color: _asColor(groupJson?['color']),
          criticality: _asCriticality(groupJson?['criticality']),
          createdAt: timestamp,
          updatedAt: timestamp,
        );
        await _groupDao.insertGroup(created);
        existingGroups.add(
          AllergenGroupWithTerms(group: created, terms: const []),
        );
        groupsCreated++;
        groupId = created.id;
        return created.id;
      }

      if (termEntries.isEmpty) {
        await ensureGroup();
        continue;
      }

      for (final Object? termEntry in termEntries) {
        final _TermStatus status = await _importTerm(
          termEntry,
          groupId: null,
          isActive: groupActive,
          beforeInsert: ensureGroup,
        );
        tally(status);
      }
    }

    for (final Object? termEntry in _asList(payload['ungroupedTerms'])) {
      tally(await _importTerm(termEntry, groupId: null, isActive: null));
    }

    _log.info(
      'Imported allergy list: $groupsCreated groups created, '
      '$termsAdded terms added, $termsSkipped already present, '
      '$termsRejected unusable terms, $groupsRejected unusable groups',
    );
    return AllergyListImportOutcome(
      groupsCreated: groupsCreated,
      termsAdded: termsAdded,
      termsSkipped: termsSkipped,
      termsRejected: termsRejected,
      groupsRejected: groupsRejected,
    );
  }

  /// Re-implements `AllergenTermActions.add`'s validation and duplicate rule
  /// (R4.1) rather than calling it, since `core/` must not depend on the
  /// feature layer.
  ///
  /// [isActive] `null` means "take it from the file" (an ungrouped term, which
  /// the user toggles individually); a non-null value is the owning group's
  /// state and wins over the file. [beforeInsert] runs only once the entry is
  /// known to be insertable, and returns the group id to attach it to.
  Future<_TermStatus> _importTerm(
    Object? entry, {
    required String? groupId,
    required bool? isActive,
    Future<String> Function()? beforeInsert,
  }) async {
    final Map<String, Object?>? termJson = _asMap(entry);
    final String? rawTerm = _asString(termJson?['term']);
    if (rawTerm == null) return _TermStatus.rejected;

    final String term = rawTerm.trim();
    if (term.isEmpty || term.length > _maxTextLength) {
      return _TermStatus.rejected;
    }

    final String normalized = TextNormalizer.normalize(term);
    if (!TextNormalizer.isSearchable(normalized)) return _TermStatus.rejected;
    if (await _termDao.findByNormalizedTerm(normalized) != null) {
      return _TermStatus.duplicate;
    }

    final String? note = _asString(termJson?['note']);
    final DateTime timestamp = _now();
    await _termDao.insertTerm(
      AllergenTerm(
        id: _uuid.v4(),
        term: term,
        normalizedTerm: normalized,
        isActive: isActive ?? _asBool(termJson?['isActive']) ?? true,
        note: note != null && note.length > _maxTextLength ? null : note,
        groupId: beforeInsert == null ? groupId : await beforeInsert(),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    return _TermStatus.added;
  }

  // Every reader below returns null for a wrong type rather than throwing: a
  // hand-edited or third-party file must degrade into a counted "rejected"
  // entry, never a raw _TypeError surfacing as "Import failed: type 'int' is
  // not a subtype of type 'String?'".
  static List<Object?> _asList(Object? value) =>
      value is List ? value : const <Object?>[];

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static String? _asString(Object? value) => value is String ? value : null;

  static bool? _asBool(Object? value) => value is bool ? value : null;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Color? _asColor(Object? value) => value is int ? Color(value) : null;

  static GroupCriticality? _asCriticality(Object? value) {
    if (value is! String) return null;
    for (final GroupCriticality c in GroupCriticality.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}
