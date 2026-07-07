import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/reference_models.dart';
import '../../data/models/production_standard_model.dart';
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

final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getDashboardStats();
});

final productionStandardsProvider =
    FutureProvider<List<ProductionStandardModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getProductionStandards(activeOnly: true);
  return raw.map(ProductionStandardModel.fromJson).toList();
});
