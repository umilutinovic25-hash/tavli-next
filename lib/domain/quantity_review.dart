import 'recipe.dart';

/// Oznake stvarnog podatka, ne ocena pouzdanosti prepoznavanja.
enum QuantityReviewIssue {
  unknown('Količina nije prepoznata — proveri original.'),
  invalid('Neispravna količina — proveri original.');

  const QuantityReviewIssue(this.label);
  final String label;
}

QuantityReviewIssue? quantityReviewIssue(Ingredient ingredient) {
  final q = ingredient.quantity;
  if (q == null) return QuantityReviewIssue.unknown;
  if (!q.isFinite || q <= 0) return QuantityReviewIssue.invalid;
  return null;
}
