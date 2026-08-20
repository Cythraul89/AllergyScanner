import 'package:equatable/equatable.dart';

/// One entry of the user's allergy list.
///
/// [normalizedTerm] is derived from [term] by `TextNormalizer.normalize` and is
/// the only field the matcher reads. It is stored rather than computed, which
/// makes a change to the normalisation rules a database migration — see
/// doc/ARCHITECTURE.md §5.2.
class AllergenTerm extends Equatable {
  const AllergenTerm({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  final String id;
  final String term;
  final String normalizedTerm;
  final bool isActive;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  AllergenTerm copyWith({
    String? term,
    String? normalizedTerm,
    bool? isActive,
    String? note,
    DateTime? updatedAt,
  }) {
    return AllergenTerm(
      id: id,
      term: term ?? this.term,
      normalizedTerm: normalizedTerm ?? this.normalizedTerm,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    term,
    normalizedTerm,
    isActive,
    note,
    createdAt,
    updatedAt,
  ];
}
