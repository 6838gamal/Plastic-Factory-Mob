import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_config.dart';
import '../models/raw_material_model.dart';
import '../models/inventory_model.dart';
import '../models/batch_model.dart';
import '../models/machine_production_model.dart';
import '../models/alert_model.dart';
import '../models/audit_log_model.dart';
import '../models/reference_models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/helpers.dart';

class SupabaseDataSource {
  SupabaseClient get _client => SupabaseConfig.client;

  // ==================== AUTH ====================
  Future<AuthResponse> signIn(String email, String password) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async => await _client.auth.signOut();

  User? get currentUser {
    try {
      return _client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Stream<AuthState> get authStateStream => _client.auth.onAuthStateChange;

  // ==================== RAW MATERIALS ====================
  Future<List<RawMaterialModel>> getRawMaterials() async {
    final res = await _client
        .from(AppConstants.tbRawMaterials)
        .select()
        .eq('is_active', true)
        .order('category')
        .order('name');
    return (res as List).map((e) => RawMaterialModel.fromJson(e)).toList();
  }

  Future<void> upsertRawMaterial(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbRawMaterials).upsert(data);
  }

  Future<void> deleteRawMaterial(String id) async {
    await _client
        .from(AppConstants.tbRawMaterials)
        .update({'is_active': false}).eq('id', id);
  }

  // ==================== INVENTORY ====================
  Future<List<InventoryModel>> getInventory({String? warehouseType}) async {
    var query = _client
        .from(AppConstants.tbInventory)
        .select('*, raw_materials(name, unit, min_stock)');
    if (warehouseType != null) {
      query = query.eq('warehouse_type', warehouseType);
    }
    final res = await query.order('material_name');
    return (res as List).map((e) {
      final material = e['raw_materials'] as Map<String, dynamic>?;
      return InventoryModel.fromJson({
        ...e,
        'material_name': material?['name'] ?? '',
        'unit': material?['unit'] ?? 'كجم',
        'min_stock': material?['min_stock'] ?? 0,
      });
    }).toList();
  }

  Future<InventoryModel?> getMaterialInventory(String materialId, String warehouseType) async {
    final res = await _client
        .from(AppConstants.tbInventory)
        .select('*, raw_materials(name, unit, min_stock)')
        .eq('material_id', materialId)
        .eq('warehouse_type', warehouseType)
        .maybeSingle();
    if (res == null) return null;
    final material = res['raw_materials'] as Map<String, dynamic>?;
    return InventoryModel.fromJson({
      ...res,
      'material_name': material?['name'] ?? '',
      'unit': material?['unit'] ?? 'كجم',
      'min_stock': material?['min_stock'] ?? 0,
    });
  }

  Future<void> updateInventoryBalance(
    String materialId,
    String warehouseType,
    double newBalance,
  ) async {
    await _client
        .from(AppConstants.tbInventory)
        .upsert({
          'material_id': materialId,
          'warehouse_type': warehouseType,
          'balance': newBalance,
          'updated_at': DateTime.now().toIso8601String(),
        });
  }

  Future<void> addInventoryTransaction(InventoryTransactionModel tx) async {
    await _client.from(AppConstants.tbInventoryTransactions).insert(tx.toJson());
  }

  Future<List<InventoryTransactionModel>> getInventoryTransactions({
    String? materialId,
    String? warehouseType,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from(AppConstants.tbInventoryTransactions).select();
    if (materialId != null) query = query.eq('material_id', materialId);
    if (warehouseType != null) query = query.eq('warehouse_type', warehouseType);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());
    final res = await query.order('created_at', ascending: false).limit(100);
    return (res as List).map((e) => InventoryTransactionModel.fromJson(e)).toList();
  }

  // ==================== WORKERS ====================
  Future<List<WorkerModel>> getWorkers() async {
    final res = await _client
        .from(AppConstants.tbWorkers)
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((e) => WorkerModel.fromJson(e)).toList();
  }

  Future<void> upsertWorker(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbWorkers).upsert(data);
  }

  Future<void> deleteWorker(String id) async {
    await _client.from(AppConstants.tbWorkers).update({'is_active': false}).eq('id', id);
  }

  // ==================== PRODUCTS ====================
  Future<List<ProductModel>> getProducts() async {
    final res = await _client
        .from(AppConstants.tbProducts)
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((e) => ProductModel.fromJson(e)).toList();
  }

  Future<void> upsertProduct(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbProducts).upsert(data);
  }

  // ==================== MACHINES ====================
  Future<List<MachineModel>> getMachines() async {
    final res = await _client
        .from(AppConstants.tbMachines)
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((e) => MachineModel.fromJson(e)).toList();
  }

  Future<void> upsertMachine(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbMachines).upsert(data);
  }

  // ==================== MIXERS ====================
  Future<List<MixerModel>> getMixers() async {
    final res = await _client
        .from(AppConstants.tbMixers)
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((e) => MixerModel.fromJson(e)).toList();
  }

  Future<void> upsertMixer(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbMixers).upsert(data);
  }

  // ==================== MIXTURE TYPES ====================
  Future<List<MixtureTypeModel>> getMixtureTypes() async {
    final res = await _client
        .from(AppConstants.tbMixtureTypes)
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((e) => MixtureTypeModel.fromJson(e)).toList();
  }

  Future<void> upsertMixtureType(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbMixtureTypes).upsert(data);
  }

  // ==================== BATCHES ====================
  Future<List<BatchModel>> getBatches({DateTime? from, DateTime? to, String? workerId}) async {
    var query = _client.from(AppConstants.tbBatches).select();
    if (from != null) query = query.gte('date', from.toIso8601String().split('T').first);
    if (to != null) query = query.lte('date', to.toIso8601String().split('T').first);
    if (workerId != null) query = query.eq('worker_id', workerId);
    final res = await query.order('created_at', ascending: false);
    return (res as List).map((e) => BatchModel.fromJson(e)).toList();
  }

  Future<BatchModel> saveBatch(Map<String, dynamic> data) async {
    final res = await _client.from(AppConstants.tbBatches).insert(data).select().single();
    return BatchModel.fromJson(res);
  }

  Future<BatchModel> updateBatch(String id, Map<String, dynamic> data) async {
    final res = await _client
        .from(AppConstants.tbBatches)
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return BatchModel.fromJson(res);
  }

  Future<bool> checkTransactionExists(String transactionId) async {
    final res = await _client
        .from(AppConstants.tbBatches)
        .select('id')
        .eq('transaction_id', transactionId)
        .maybeSingle();
    return res != null;
  }

  // ==================== MACHINE PRODUCTION ====================
  Future<List<MachineProductionModel>> getMachineProductions({
    DateTime? from,
    DateTime? to,
    String? machineId,
  }) async {
    var query = _client.from(AppConstants.tbMachineProduction).select();
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());
    if (machineId != null) query = query.eq('machine_id', machineId);
    final res = await query.order('created_at', ascending: false);
    return (res as List).map((e) => MachineProductionModel.fromJson(e)).toList();
  }

  Future<MachineProductionModel> saveMachineProduction(Map<String, dynamic> data) async {
    final res = await _client
        .from(AppConstants.tbMachineProduction)
        .insert(data)
        .select()
        .single();
    return MachineProductionModel.fromJson(res);
  }

  // ==================== ALERTS ====================
  Future<List<AlertModel>> getAlerts({String? status, String? severity}) async {
    var query = _client.from(AppConstants.tbAlerts).select();
    if (status != null) query = query.eq('status', status);
    if (severity != null) query = query.eq('severity', severity);
    final res = await query.order('created_at', ascending: false);
    return (res as List).map((e) => AlertModel.fromJson(e)).toList();
  }

  Future<AlertModel> createAlert(Map<String, dynamic> data) async {
    final res = await _client.from(AppConstants.tbAlerts).insert(data).select().single();
    return AlertModel.fromJson(res);
  }

  Future<void> updateAlertStatus(String id, String status) async {
    await _client
        .from(AppConstants.tbAlerts)
        .update({'status': status, 'resolved_at': DateTime.now().toIso8601String()}).eq('id', id);
  }

  Future<int> getPendingAlertsCount() async {
    final res = await _client
        .from(AppConstants.tbAlerts)
        .select('id')
        .eq('status', 'pending');
    return (res as List).length;
  }

  // ==================== AUDIT LOG ====================
  Future<void> addAuditLog(Map<String, dynamic> data) async {
    await _client.from(AppConstants.tbAuditLog).insert(data);
  }

  Future<List<AuditLogModel>> getAuditLogs({
    String? tableName,
    String? action,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from(AppConstants.tbAuditLog).select();
    if (tableName != null) query = query.eq('table_name', tableName);
    if (action != null) query = query.eq('action', action);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());
    final res = await query.order('created_at', ascending: false).limit(200);
    return (res as List).map((e) => AuditLogModel.fromJson(e)).toList();
  }

  // ==================== IMAGES ====================
  Future<String?> uploadImage(String bucket, String path, List<int> bytes) async {
    final Uint8List uint8Bytes = Uint8List.fromList(bytes);
    await _client.storage.from(bucket).uploadBinary(path, uint8Bytes);
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  // ==================== REPORTS ====================
  Future<Map<String, dynamic>> getDashboardStats() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final batchesToday = await _client
        .from(AppConstants.tbBatches)
        .select('id, pvc_qty, dop_qty, scrap_qty, calcium_qty, wax_qty, stabilizer_qty, titanium_qty')
        .gte('created_at', startOfDay.toIso8601String());

    final productionToday = await _client
        .from(AppConstants.tbMachineProduction)
        .select('produced_quantity, scrap_quantity, waste_quantity, stop_time_minutes')
        .gte('created_at', startOfDay.toIso8601String());

    final pendingAlerts = await getPendingAlertsCount();

    final productions = productionToday as List;
    double totalProduced = 0;
    double totalScrap = 0;
    double totalWaste = 0;
    double totalStopTime = 0;
    for (final p in productions) {
      totalProduced += (p['produced_quantity'] as num?)?.toDouble() ?? 0;
      totalScrap += (p['scrap_quantity'] as num?)?.toDouble() ?? 0;
      totalWaste += (p['waste_quantity'] as num?)?.toDouble() ?? 0;
      totalStopTime += (p['stop_time_minutes'] as num?)?.toDouble() ?? 0;
    }

    return {
      'batches_today': (batchesToday as List).length,
      'production_today': totalProduced,
      'scrap_today': totalScrap,
      'waste_today': totalWaste,
      'stop_time_today': totalStopTime,
      'pending_alerts': pendingAlerts,
      'waste_percentage': totalProduced > 0 ? (totalWaste / totalProduced) * 100 : 0,
    };
  }
}
