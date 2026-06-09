import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/reference_models.dart';
import 'auth_provider.dart';

final recipesProvider = FutureProvider<List<RecipeModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getRecipes();
});

final recipeByMixtureTypeProvider =
    FutureProviderFamily<RecipeModel?, String>((ref, mixtureTypeId) async {
  if (mixtureTypeId.isEmpty) return null;
  final ds = ref.read(dataSourceProvider);
  return ds.getRecipeByMixtureType(mixtureTypeId);
});
