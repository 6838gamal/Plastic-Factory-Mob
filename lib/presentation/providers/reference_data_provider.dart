import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/reference_models.dart';
import '../../data/models/production_standard_model.dart';
import '../../data/models/inventory_summary_model.dart';
import 'auth_provider.dart';

export '../../data/models/raw_material_model.dart' show RawMaterialModel;

// autoDispose: تُعاد قراءة القائمة من الخادم عند كل دخول للشاشة بدل الاحتفاظ
// بنسخة قديمة في الذاكرة طوال عمر التطبيق (كانت هذه هي "الكاش القديمة" التي
// تسببت في إرسال معرّف مادة محذوفة/معطّلة من شاشة إدخال الطبخات).
final rawMaterialsProvider =
    FutureProvider.autoDispose<List<RawMaterialModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getRawMaterials();
});

// ── ملخص المخزون (المخزن الرئيسي + مخزن الخلاط) — مصدر واحد مشترك ─────────
//
// كل الشاشات التي تعرض كروت أرصدة المواد (المخزون، مخزن الخلطات، شاشة
// إدخال الطبخات) يجب أن تعتمد على هذا المزوّد نفسه بدلاً من نسخ محلية خاصة
// بكل شاشة؛ وإلا فإن أي عملية تُغيّر المخزون (ترحيل سند، تحويل بين مخازن،
// حفظ طبخة...) في شاشة ما لن تُحدّث الكروت المعروضة في شاشة أخرى.
//
// بعد أي عملية تُغيّر المخزون استدعِ: ref.invalidate(inventorySummaryProvider)
final inventorySummaryProvider =
    FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getInventorySummary();
});

// ── كل المواد الخام النشطة بصيغة InventorySummaryModel (لكلا المخزنين) ────────
//
// يُستخدم في قوائم سندات الاستلام حتى تظهر المواد المضافة حديثاً حتى قبل أن
// يُسجَّل لها رصيد مخزون. يدمج rawMaterialsProvider مع inventorySummaryProvider:
// - المواد الموجودة في المخزون → تُعرض ببياناتها الفعلية (رصيد حقيقي)
// - المواد الجديدة غير المستلمة بعد → تُعرض برصيد صفر
//
// بعد أي إضافة/تعديل/حذف لمادة خام استدعِ: ref.invalidate(rawMaterialsProvider)
//   وهذا سيُعيد بناء هذا المزوّد تلقائياً.
final allRawMaterialsAsSummaryProvider =
    FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final rawMats = await ref.watch(rawMaterialsProvider.future);
  final summary = await ref.watch(inventorySummaryProvider.future);

  // فهرسة ملخص المخزون: materialId_warehouseType → بيانات المخزون
  final summaryMap = <String, InventorySummaryModel>{};
  for (final s in summary) {
    summaryMap['${s.materialId}_${s.warehouseType}'] = s;
  }

  final result = <InventorySummaryModel>[];
  for (final rm in rawMats) {
    if (!rm.isActive) continue;
    for (final wh in ['main', 'mixer']) {
      final key = '${rm.id}_$wh';
      result.add(
        summaryMap[key] ??
            InventorySummaryModel(
              materialId: rm.id,
              materialName: rm.name,
              code: rm.code,
              unit: rm.unit,
              minStock: rm.minStock,
              openingBalance: 0,
              currentBalance: 0,
              totalIn: 0,
              totalOut: 0,
              totalTransfers: 0,
              totalAdjustmentsPos: 0,
              totalAdjustmentsNeg: 0,
              stockStatus: 'out_of_stock',
              warehouseType: wh,
            ),
      );
    }
  }
  // ترتيب أبجدي بالاسم
  result.sort((a, b) => a.materialName.compareTo(b.materialName));
  return result;
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

final batchTypesProvider = FutureProvider<List<BatchTypeModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getBatchTypes();
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
