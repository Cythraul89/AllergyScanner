import 'package:equatable/equatable.dart';

import 'allergen_term.dart';

/// A label for a set of allergen terms meaning the same substance in
/// different languages/spellings (REQUIREMENTS §11 item 1).
class AllergenGroup extends Equatable {
  const AllergenGroup({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [id, label, createdAt, updatedAt];
}

/// An [AllergenGroup] with its member terms attached. In-memory composite,
/// never persisted — same idea as `ScanResult` in `models/scan.dart`.
class AllergenGroupWithTerms extends Equatable {
  const AllergenGroupWithTerms({required this.group, required this.terms});

  final AllergenGroup group;
  final List<AllergenTerm> terms;

  @override
  List<Object?> get props => [group, terms];
}
