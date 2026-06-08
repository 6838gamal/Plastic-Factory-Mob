import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/supabase_datasource.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/reference_models.dart';
import 'auth_provider.dart';

final rawMaterialsProvider = FutureProvider<List<RawMaterialModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getRawMaterials();
});

final workersProvider = FutureProvider<List<WorkerModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getWorkers();
});

final machinesProvider = FutureProvider<List<MachineModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getMachines();
});

final mixersProvider = FutureProvider<List<MixerModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getMixers();
});

final productsProvider = FutureProvider<List<ProductModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getProducts();
});

final mixtureTypesProvider = FutureProvider<List<MixtureTypeModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getMixtureTypes();
});

// Dashboard stats
final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getDashboardStats();
});
