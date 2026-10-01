import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show Color;

import 'allergen_term.dart';
import 'enums.dart';

/// A label for a set of allergen terms meaning the same substance in
/// different languages/spellings (REQUIREMENTS §11 item 1).
class AllergenGroup extends Equatable {
  const AllergenGroup({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.criticality,
  });

  final String id;
  final String label;

  /// `null` when the user has not picked one. Purely visual — see
  /// `AllergenGroups.color`.
  final Color? color;

  /// `null` when the user has not tagged a severity (R7.16).
  final GroupCriticality? criticality;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    label,
    color,
    criticality,
    createdAt,
    updatedAt,
  ];
}

/// An [AllergenGroup] with its member terms attached. In-memory composite,
/// never persisted — same idea as `ScanResult` in `models/scan.dart`.
class AllergenGroupWithTerms extends Equatable {
  const AllergenGroupWithTerms({required this.group, required this.terms});

  final AllergenGroup group;
  final List<AllergenTerm> terms;

  /// A group is a single substance, so its names are toggled together —
  /// there is no "some members active, some not" state to represent.
  /// A group with no members yet reads as active (matches a new term's
  /// default).
  bool get isActive => terms.isEmpty || terms.every((t) => t.isActive);

  @override
  List<Object?> get props => [group, terms];
}
