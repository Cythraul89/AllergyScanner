import 'package:equatable/equatable.dart';

import '../constants.dart';
import 'enums.dart';

/// A product, either as retrieved from Open Food Facts or as corrected locally.
class Product extends Equatable {
  const Product({
    required this.barcode,
    required this.source,
    required this.updatedAt,
    this.productName,
    this.brands,
    this.quantity,
    this.ingredientsText,
    this.ingredientsLanguage,
    this.imageUrl,
    this.allergensTags = const [],
    this.tracesTags = const [],
    this.hasManualOverride = false,
    this.fetchedAt,
  });

  final String barcode;
  final String? productName;
  final String? brands;
  final String? quantity;
  final String? ingredientsText;
  final String? ingredientsLanguage;
  final String? imageUrl;

  /// Allergen and "may contain" declarations as Open Food Facts reports them.
  /// Displayed for information; the matcher does not read them (REQUIREMENTS §5.4).
  final List<String> allergensTags;
  final List<String> tracesTags;

  final ProductSource source;
  final bool hasManualOverride;
  final DateTime? fetchedAt;
  final DateTime updatedAt;

  bool get hasIngredients =>
      ingredientsText != null && ingredientsText!.trim().isNotEmpty;

  /// A locally corrected product is never stale: the user read the physical
  /// package, which beats anything the remote database can offer (R4.5).
  bool isStale(DateTime now) {
    if (hasManualOverride) return false;
    final fetched = fetchedAt;
    if (fetched == null) return true;
    return now.difference(fetched) > kProductCacheTtl;
  }

  /// Label for the result view's provenance line.
  String get displayName => productName ?? barcode;

  Product copyWith({
    String? productName,
    String? brands,
    String? quantity,
    String? ingredientsText,
    String? ingredientsLanguage,
    String? imageUrl,
    List<String>? allergensTags,
    List<String>? tracesTags,
    ProductSource? source,
    bool? hasManualOverride,
    DateTime? fetchedAt,
    DateTime? updatedAt,
  }) {
    return Product(
      barcode: barcode,
      productName: productName ?? this.productName,
      brands: brands ?? this.brands,
      quantity: quantity ?? this.quantity,
      ingredientsText: ingredientsText ?? this.ingredientsText,
      ingredientsLanguage: ingredientsLanguage ?? this.ingredientsLanguage,
      imageUrl: imageUrl ?? this.imageUrl,
      allergensTags: allergensTags ?? this.allergensTags,
      tracesTags: tracesTags ?? this.tracesTags,
      source: source ?? this.source,
      hasManualOverride: hasManualOverride ?? this.hasManualOverride,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    barcode,
    productName,
    brands,
    quantity,
    ingredientsText,
    ingredientsLanguage,
    imageUrl,
    allergensTags,
    tracesTags,
    source,
    hasManualOverride,
    fetchedAt,
    updatedAt,
  ];
}
