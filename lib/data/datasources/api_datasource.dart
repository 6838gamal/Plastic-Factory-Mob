// lib/data/datasources/api_datasource.dart

import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
//import 'dart:html' as html show window;

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import '../models/raw_material_model.dart';
import '../models/inventory_model.dart';
import '../models/inventory_summary_model.dart';
import '../models/batch_model.dart';
import '../models/machine_production_model.dart';
import '../models/alert_model.dart';
import '../models/audit_log_model.dart';
import '../models/reference_models.dart';
import '../local/local_data_service.dart';

class ApiDataSource {
  // Resolve the API base URL at runtime from the browser's current origin.
  // This ensures the app works on any domain (Replit dev, deployed, etc.)
  // without needing a rebuild.
  static String get _baseUrl {
  if (kIsWeb) {
    try {
      final origin = Uri.base.origin;

      if (origin.isNotEmpty && origin != 'null') {
        return origin;
      }
    } catch (_) {}
  }

  const injected = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://plastic-factory-api-backend-demo.onrender.com',
  );

  if (injected.isNotEmpty) {
    return injected;
  }

  return 'https://plastic-factory-api-backend-demo.onrender.com';
  }

  static String get baseUrl => _baseUrl;

  String? _token;

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _get(String path, {Map<String, String?>? query}) async {
    final filteredQuery = query?.entries
        .where((e) => e.value != null)
        .fold<Map<String, String>>({}, (m, e) => m..putIfAbsent(e.key, () => e.value!));
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: (filteredQuery?.isEmpty ?? true) ? null : filteredQuery,
    );
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
    return jsonDecode(res.body);
  }

  /// Extract a human-readable message from a FastAPI error response body.
  /// FastAPI wraps errors as {"detail": "string"} or {"detail": {"message":..., "error":...}}.
  String _extractError(dynamic body) {
    if (body is Map) {
      final detail = body['detail'];
      if (detail is Map) {
        return (detail['message'] ?? detail['error'] ?? 'Request failed').toString();
      } else if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      return (body['error'] ?? body['message'] ?? 'Request failed').toString();
    }
    return 'Request failed';
  }

  Future<dynamic> _post(String path, Map<String, dynamic> data) async {
    print('🔵 [_post] $path');
    print('🔵 [_post] data: $data');
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http.post(uri, headers: _headers, body: jsonEncode(data));
    print('🔵 [_post] status: ${res.statusCode}');
    print('🔵 [_post] body: ${res.body}');
    if (res.statusCode >= 400) {
      throw Exception(_extractError(jsonDecode(res.body)));
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http.put(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) {
      throw Exception(_extractError(jsonDecode(res.body)));
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _delete(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception(_extractError(jsonDecode(res.body)));
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // ==================== GENERIC RAW CALLS ====================
  Future<dynamic> getRaw(String path, {Map<String, String?>? query}) =>
      _get(path, query: query);
  Future<dynamic> postRaw(String path, Map<String, dynamic> data) =>
      _post(path, data);
  Future<dynamic> putRaw(String path, Map<String, dynamic> data) =>
      _put(path, data);

  // ==================== HEALTH ====================
  Future<void> checkHealth() async {
    final uri = Uri.parse('$_baseUrl/api/health');
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 400) throw Exception('Server error ${res.statusCode}');
  }

  // ==================== AUTH ====================
  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final res = await _post('/api/auth/signin', {'email': email, 'password': password});
    _token = res['token'] as String?;
    return res as Map<String, dynamic>;
  }

  Future<void> signOut() async {
    _token = null;
  }

  Future<Map<String, dynamic>> changePassword(
      String userId, String currentPassword, String newPassword) async {
    final res = await _put('/api/auth/change-password', {
      'user_id': userId,
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> changeEmail(
      String userId, String currentPassword, String newEmail) async {
    final res = await _put('/api/auth/change-email', {
      'user_id': userId,
      'current_password': currentPassword,
      'new_email': newEmail,
    });
    if (res['token'] != null) _token = res['token'] as String;
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWarehouseAccount() async {
    final res = await _get('/api/auth/warehouse-account');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upsertWarehouseAccount(
      String email, String password, {String? name}) async {
    final res = await _put('/api/auth/warehouse-account', {
      'email': email,
      'password': password,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProductionManagerAccount() async {
    final res = await _get('/api/auth/production-manager-account');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upsertProductionManagerAccount(
      String email, String password, {String? name}) async {
    final res = await _put('/api/auth/production-manager-account', {
      'email': email,
      'password': password,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return res as Map<String, dynamic>;
  }

  // ── Suppliers ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSuppliers({bool activeOnly = false}) async {
    final res = await _get('/api/suppliers?active_only=${activeOnly ? 'true' : 'false'}');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> body) async {
    final res = await _post('/api/suppliers', body);
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSupplier(
      String id, Map<String, dynamic> body) async {
    final res = await _put('/api/suppliers/$id', body);
    return res as Map<String, dynamic>;
  }

  Future<void> deleteSupplier(String id) async {
    await _delete('/api/suppliers/$id');
  }

  Future<Map<String, dynamic>> forgotPassword(
      String email, String newPassword) async {
    final res = await _post('/api/auth/forgot-password', {
      'email': email,
      'new_password': newPassword,
    });
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final res = await _post('/api/auth/send-otp', {'phone': phone});
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final res = await _post('/api/auth/verify-otp', {'phone': phone, 'code': code});
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resetPasswordWithToken(
      String resetToken, String newPassword) async {
    final res = await _post('/api/auth/reset-password-with-token', {
      'reset_token': resetToken,
      'new_password': newPassword,
    });
    return res as Map<String, dynamic>;
  }

  // ==================== RAW MATERIALS ====================
  Future<List<RawMaterialModel>> getRawMaterials() async {
    final res = await _get('/api/materials');
    return (res as List).map((e) => RawMaterialModel.fromJson(e)).toList();
  }

  Future<void> upsertRawMaterial(Map<String, dynamic> data) async {
    await _post('/api/materials/upsert', data);
  }

  Future<void> deleteRawMaterial(String id) async {
    await _delete('/api/materials/$id');
  }

  /// حذف كامل لمادة خام: يزيل جميع حركاتها وأرصدتها وصفوف مخزونها
  /// ثم يُعطّل المادة نفسها في raw_materials.
  Future<void> deleteInventoryMaterialFully(String materialId) async {
    await _delete('/api/inventory/material/$materialId');
  }

  // ==================== INVENTORY ====================
  Future<List<InventoryModel>> getInventory({String? warehouseType}) async {
    final res = await _get('/api/inventory', query: {'warehouse_type': warehouseType});
    return (res as List).map((e) => InventoryModel.fromJson(e)).toList();
  }

  Future<List<InventorySummaryModel>> getInventorySummary() async {
    final res = await _get('/api/inventory/summary');
    return (res as List).map((e) => InventorySummaryModel.fromJson(e)).toList();
  }

  Future<void> addOpeningBalance(Map<String, dynamic> data) async {
    await _post('/api/opening-balances', data);
  }

  Future<List<Map<String, dynamic>>> getOpeningBalances({
    String? materialId,
    String? warehouseType,
  }) async {
    final res = await _get('/api/opening-balances', query: {
      'material_id': materialId,
      'warehouse_type': warehouseType,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> updateOpeningBalance(String id, Map<String, dynamic> data) async {
    await _put('/api/opening-balances/$id', data);
  }

  Future<void> deleteOpeningBalance(String id) async {
    await _delete('/api/opening-balances/$id');
  }

  Future<Map<String, dynamic>> getSmsSettings() async {
    final res = await _get('/api/sms/settings');
    return res as Map<String, dynamic>;
  }

  Future<void> updateSmsSettings(Map<String, dynamic> data) async {
    await _put('/api/sms/settings', data);
  }

  Future<Map<String, dynamic>> sendTestSms(String message) async {
    final res = await _post('/api/sms/test', {'message': message});
    return res as Map<String, dynamic>;
  }

  Future<InventoryModel?> getMaterialInventory(String materialId, String warehouseType) async {
    final res = await _get(
      '/api/inventory/material/$materialId',
      query: {'warehouse_type': warehouseType},
    );
    if (res == null) return null;
    return InventoryModel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> updateInventoryBalance(
    String materialId,
    String warehouseType,
    double newBalance,
  ) async {
    await _post('/api/inventory/balance', {
      'material_id': materialId,
      'warehouse_type': warehouseType,
      'balance': newBalance,
    });
  }

  Future<void> resetMaterialFull(
    String materialId,
    String warehouseType, {
    String? reason,
    String? createdBy,
  }) async {
    await _post('/api/inventory/reset-material', {
      'material_id': materialId,
      'warehouse_type': warehouseType,
      'reason': reason,
      'created_by': createdBy,
    });
  }

  /// Transfers qty from one warehouse to another via the dedicated atomic
  /// transfer endpoint — deducts source, adds destination in one call.
  Future<Map<String, dynamic>> transferInventory({
    required String materialId,
    required double quantity,
    required String fromWarehouse,
    required String toWarehouse,
    String? notes,
    String? createdBy,
  }) async {
    final res = await _post('/api/inventory/transfer', {
      'material_id': materialId,
      'quantity': quantity,
      'from_warehouse': fromWarehouse,
      'to_warehouse': toWarehouse,
      'notes': notes,
      'created_by': createdBy,
    });
    return res as Map<String, dynamic>;
  }

  /// Atomically resets a material in BOTH main and mixer warehouses in one
  /// server-side transaction — guaranteed all-or-nothing.
  Future<void> resetMaterialBothWarehouses(
    String materialId, {
    String? reason,
    String? createdBy,
  }) async {
    await _post('/api/inventory/reset-material-both', {
      'material_id': materialId,
      'reason': reason,
      'created_by': createdBy,
    });
  }

  Future<void> addInventoryTransaction(InventoryTransactionModel tx) async {
    await _post('/api/inventory/transactions', tx.toJson());
  }

  Future<List<InventoryTransactionModel>> getInventoryTransactions({
    String? materialId,
    String? warehouseType,
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _get('/api/inventory/transactions', query: {
      'material_id': materialId,
      'warehouse_type': warehouseType,
      'from': from?.toIso8601String(),
      'to': to?.toIso8601String(),
    });
    return (res as List).map((e) => InventoryTransactionModel.fromJson(e)).toList();
  }

  Future<void> deleteInventoryTransaction(String id) async {
    await _delete('/api/inventory/transactions/$id');
  }

  // ==================== WORKERS (local only — seeded on first run) ====================
  Future<List<WorkerModel>> getWorkers() => LocalDataService.getWorkers();
  Future<void> upsertWorker(Map<String, dynamic> data) =>
      LocalDataService.upsertWorker(data);
  Future<void> deleteWorker(String id) => LocalDataService.deleteWorker(id);

  // ==================== PRODUCTS (local only) ====================
  Future<List<ProductModel>> getProducts() => LocalDataService.getProducts();
  Future<void> upsertProduct(Map<String, dynamic> data) =>
      LocalDataService.upsertProduct(data);

  // ==================== MACHINES (local only) ====================
  Future<List<MachineModel>> getMachines() => LocalDataService.getMachines();
  Future<void> upsertMachine(Map<String, dynamic> data) =>
      LocalDataService.upsertMachine(data);

  // ==================== MIXERS (local only) ====================
  Future<List<MixerModel>> getMixers() => LocalDataService.getMixers();
  Future<void> upsertMixer(Map<String, dynamic> data) =>
      LocalDataService.upsertMixer(data);

  // ==================== MIXTURE TYPES (local only) ====================
  Future<List<MixtureTypeModel>> getMixtureTypes() =>
      LocalDataService.getMixtureTypes();
  Future<void> upsertMixtureType(Map<String, dynamic> data) =>
      LocalDataService.upsertMixtureType(data);
  Future<void> deleteMixtureType(String id) =>
      LocalDataService.deleteMixtureType(id);

  // ==================== BATCH TYPES (local only) ====================
  Future<List<BatchTypeModel>> getBatchTypes() =>
      LocalDataService.getBatchTypes();
  Future<void> upsertBatchType(Map<String, dynamic> data) =>
      LocalDataService.upsertBatchType(data);
  Future<void> deleteBatchType(String id) =>
      LocalDataService.deleteBatchType(id);

  // ==================== RECIPES ====================
  Future<List<RecipeModel>> getRecipes() async {
    final res = await _get('/api/recipes');
    return (res as List).map((e) => RecipeModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RecipeModel?> getRecipeByMixtureType(String mixtureTypeId) async {
    final res = await _get('/api/recipes/by-mixture/$mixtureTypeId');
    if (res == null) return null;
    return RecipeModel.fromJson(res as Map<String, dynamic>);
  }

  Future<RecipeModel> upsertRecipe(Map<String, dynamic> data) async {
    final res = await _post('/api/recipes', data);
    return RecipeModel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteRecipe(String id) async {
    await _delete('/api/recipes/$id');
  }

  // ==================== BATCHES ====================
  Future<List<BatchModel>> getBatches({DateTime? from, DateTime? to, String? workerId}) async {
    final res = await _get('/api/batches', query: {
      'from': from?.toIso8601String().split('T').first,
      'to': to?.toIso8601String().split('T').first,
      'worker_id': workerId,
    });
    return (res as List).map((e) => BatchModel.fromJson(e)).toList();
  }

  Future<BatchModel> saveBatch(Map<String, dynamic> data) async {
    final res = await _post('/api/batches', data);
    return BatchModel.fromJson(res as Map<String, dynamic>);
  }

  Future<BatchModel> updateBatch(String id, Map<String, dynamic> data) async {
    final res = await _put('/api/batches/$id', data);
    return BatchModel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteBatch(String id) async {
    await _delete('/api/batches/$id');
  }

  Future<bool> checkTransactionExists(String transactionId) async {
    final res = await _get('/api/batches/check-transaction/$transactionId');
    return (res as Map<String, dynamic>)['exists'] as bool;
  }

  // ==================== MACHINE PRODUCTION ====================
  Future<List<MachineProductionModel>> getMachineProductions({
    DateTime? from,
    DateTime? to,
    String? machineId,
  }) async {
    final res = await _get('/api/machine-production', query: {
      'from': from?.toIso8601String(),
      'to': to?.toIso8601String(),
      'machine_id': machineId,
    });
    return (res as List).map((e) => MachineProductionModel.fromJson(e)).toList();
  }

  Future<MachineProductionModel> saveMachineProduction(Map<String, dynamic> data) async {
    final res = await _post('/api/machine-production', data);
    return MachineProductionModel.fromJson(res as Map<String, dynamic>);
  }

  Future<MachineProductionModel> updateMachineProduction(
      String id, Map<String, dynamic> data) async {
    final res = await _put('/api/machine-production/$id', data);
    return MachineProductionModel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteMachineProduction(String id) async {
    await _delete('/api/machine-production/$id');
  }

  // ==================== ALERTS ====================
  Future<List<AlertModel>> getAlerts({String? status, String? severity}) async {
    final res = await _get('/api/alerts', query: {
      'status': status,
      'severity': severity,
    });
    return (res as List).map((e) => AlertModel.fromJson(e)).toList();
  }

  Future<AlertModel> createAlert(Map<String, dynamic> data) async {
    final res = await _post('/api/alerts', data);
    return AlertModel.fromJson(res as Map<String, dynamic>);
  }

  Future<void> updateAlertStatus(String id, String status) async {
    await _put('/api/alerts/$id/status', {'status': status});
  }

  Future<void> deleteAlert(String id) async {
    await _delete('/api/alerts/$id');
  }

  Future<int> getPendingAlertsCount() async {
    final res = await _get('/api/alerts/pending-count');
    return (res as Map<String, dynamic>)['count'] as int;
  }

  // ==================== AUDIT LOG ====================
  Future<void> addAuditLog(Map<String, dynamic> data) async {
    await _post('/api/audit', data);
  }

  Future<List<AuditLogModel>> getAuditLogs({
    String? tableName,
    String? action,
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _get('/api/audit', query: {
      'table_name': tableName,
      'action': action,
      'from': from?.toIso8601String(),
      'to': to?.toIso8601String(),
    });
    return (res as List).map((e) => AuditLogModel.fromJson(e)).toList();
  }

  Future<int> deleteAuditLogs() async {
    final res = await _delete('/api/audit');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<void> deleteAuditLog(String id) async {
    await _delete('/api/audit/$id');
  }

  // ==================== DANGER ZONE (bulk clear) ====================
  Future<int> deleteAllAlerts() async {
    final res = await _delete('/api/alerts');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<int> deleteAllDailyReports() async {
    final res = await _delete('/api/reports/daily');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<int> deleteAllBatches() async {
    final res = await _delete('/api/batches');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<int> deleteAllProduction() async {
    final res = await _delete('/api/machine-production');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<int> deleteAllShiftHandovers() async {
    final res = await _delete('/api/shift-handover');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  Future<void> deleteShiftHandover(String id) async {
    await _delete('/api/shift-handover/$id');
  }

  Future<int> deleteAllInventoryTransactions() async {
    final res = await _delete('/api/inventory/transactions');
    return (res as Map<String, dynamic>)['deleted'] as int? ?? 0;
  }

  /// تنظيف شامل — يحذف جميع البيانات التشغيلية مع الاحتفاظ بالبيانات المرجعية.
  Future<int> fullReset() async {
    int total = 0;
    total += await deleteAllBatches();
    total += await deleteAllProduction();
    total += await deleteAllShiftHandovers();
    total += await deleteAllInventoryTransactions();
    total += await deleteAllAlerts();
    total += await deleteAllDailyReports();
    total += await deleteAuditLogs();
    return total;
  }

  // ==================== IMAGES ====================
  Future<String?> uploadImage(String bucket, String path, List<int> bytes) async {
    final uri = Uri.parse('$_baseUrl/api/upload/$bucket');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_token != null ? {'Authorization': 'Bearer $_token'} : {})
      ..files.add(http.MultipartFile.fromBytes('file', Uint8List.fromList(bytes), filename: path));
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    if (res.statusCode >= 400) return null;
    final body = jsonDecode(res.body);
    return body['url'] as String?;
  }

  // ==================== BATCH NUMBER AUTO-INCREMENT ====================
  Future<String> getNextBatchNumber() async {
    final res = await _get('/api/batches/next-number');
    return (res as Map<String, dynamic>)['next_number'] as String;
  }

  // ==================== RECENT BATCH NUMBERS (for autocomplete) ====================
  Future<List<String>> getRecentBatchNumbers() async {
    final res = await _get('/api/batches', query: {'limit': '60'});
    final list = res as List;
    return list
        .map((e) => (e as Map<String, dynamic>)['batch_number'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ==================== STOCK TAKE ====================
  Future<List<Map<String, dynamic>>> getStockTakeSessions() async {
    final res = await _get('/api/stock-take/sessions');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createStockTakeSession(Map<String, dynamic> data) async {
    final res = await _post('/api/stock-take/sessions', data);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> getStockTakeSession(String id) async {
    final res = await _get('/api/stock-take/sessions/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> updateStockTakeItem(
      String sessionId, String itemId, double actualQty) async {
    final uri = Uri.parse('$_baseUrl/api/stock-take/sessions/$sessionId/items/$itemId');
    final res = await http.patch(
      uri,
      headers: _headers,
      body: jsonEncode({'actual_qty': actualQty}),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> closeStockTakeSession(String id) async {
    final res = await _post('/api/stock-take/sessions/$id/close', {});
    return Map<String, dynamic>.from(res as Map);
  }

  // ==================== DASHBOARD ====================
  Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await _get('/api/dashboard/stats');
    return res as Map<String, dynamic>;
  }

  Future<void> resetDashboardCounter(String counter) async {
    await _post('/api/dashboard/reset/$counter', {});
  }

  // ==================== VOUCHERS ====================

  // Receipt vouchers
  Future<List<Map<String, dynamic>>> getReceiptVouchers({String? status}) async {
    final res = await _get('/api/vouchers/receipt',
        query: status != null ? {'status': status} : null);
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> getReceiptVoucher(String id) async {
    final res = await _get('/api/vouchers/receipt/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> createReceiptVoucher(Map<String, dynamic> data) async {
    final res = await _post('/api/vouchers/receipt', data);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> updateReceiptVoucher(String id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/api/vouchers/receipt/$id');
    final res = await http.patch(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) throw Exception(jsonDecode(res.body)['detail'] ?? 'Request failed');
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> postReceiptVoucher(String id, {String performedBy = 'keeper'}) async {
    final res = await _post('/api/vouchers/receipt/$id/post?performed_by=${Uri.encodeComponent(performedBy)}', {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> submitReceiptVoucher(String id, {String submittedBy = 'keeper'}) async {
    final res = await _post('/api/vouchers/receipt/$id/submit?submitted_by=${Uri.encodeComponent(submittedBy)}', {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> approveReceiptVoucher(String id, {String approvedBy = 'admin'}) async {
    final res = await _post('/api/vouchers/receipt/$id/approve?approved_by=${Uri.encodeComponent(approvedBy)}', {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> rejectReceiptVoucher(String id, {String rejectedBy = 'admin'}) async {
    final res = await _post('/api/vouchers/receipt/$id/reject?rejected_by=${Uri.encodeComponent(rejectedBy)}', {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> deleteReceiptVoucher(String id) async {
    final uri = Uri.parse('$_baseUrl/api/vouchers/receipt/$id');
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode >= 400) throw Exception(jsonDecode(res.body)['detail'] ?? 'Request failed');
  }

  Future<List<Map<String, dynamic>>> getPendingReceiptVouchers() async {
    final res = await _get('/api/vouchers/receipt', query: {'status': 'pending_approval'});
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  // Transfer vouchers
  Future<List<Map<String, dynamic>>> getTransferVouchers(
      {String? status, String? transferType}) async {
    final q = <String, String>{};
    if (status != null) q['status'] = status;
    if (transferType != null) q['transfer_type'] = transferType;
    final res = await _get('/api/vouchers/transfer', query: q.isEmpty ? null : q);
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<Map<String, dynamic>>> getPendingTransfers({String? transferType}) async {
    final q = transferType != null ? {'transfer_type': transferType} : null;
    final res = await _get('/api/vouchers/transfer/pending', query: q);
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> getTransferVoucher(String id) async {
    final res = await _get('/api/vouchers/transfer/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> createTransferVoucher(Map<String, dynamic> data) async {
    print('🔵 [createTransferVoucher] بدء إنشاء سند');
    print('🔵 [createTransferVoucher] data: $data');
    final res = await _post('/api/vouchers/transfer', data);
    print('✅ [createTransferVoucher] تم الإنشاء: $res');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> updateTransferVoucher(String id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/api/vouchers/transfer/$id');
    final res = await http.patch(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) throw Exception(jsonDecode(res.body)['detail'] ?? 'Request failed');
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> submitTransferVoucher(String id) async {
    print('🔵 [submitTransferVoucher] إرسال سند للمراجعة: $id');
    final res = await _post('/api/vouchers/transfer/$id/submit', {});
    print('✅ [submitTransferVoucher] تم الإرسال: $res');
    return Map<String, dynamic>.from(res as Map);
  }

  // ⭐ الدالة الأهم - المسؤولة عن نقل البيانات
  Future<Map<String, dynamic>> confirmTransferVoucher(String id, Map<String, dynamic> data) async {
    try {
      print('🔵 [confirmTransferVoucher] بدء تأكيد السند');
      print('🔵 [confirmTransferVoucher] ID: $id');
      print('🔵 [confirmTransferVoucher] Data: $data');
      
      final res = await _post('/api/vouchers/transfer/$id/confirm', data);
      
      print('✅ [confirmTransferVoucher] تم التأكيد بنجاح: $res');
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      print('❌ [confirmTransferVoucher] فشل التأكيد: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> cancelTransferVoucher(String id) async {
    print('🔵 [cancelTransferVoucher] إلغاء سند: $id');
    final res = await _post('/api/vouchers/transfer/$id/cancel', {});
    print('✅ [cancelTransferVoucher] تم الإلغاء: $res');
    return Map<String, dynamic>.from(res as Map);
  }

  // Return vouchers
  Future<List<Map<String, dynamic>>> getReturnVouchers() async {
    final res = await _get('/api/vouchers/return');
    return List<Map<String, dynamic>>.from((res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> createReturnVoucher(Map<String, dynamic> data) async {
    final res = await _post('/api/vouchers/return', data);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> postReturnVoucher(String id) async {
    final res = await _post('/api/vouchers/return/$id/post', {});
    return Map<String, dynamic>.from(res as Map);
  }

  // Withdrawal vouchers
  Future<List<Map<String, dynamic>>> getWithdrawalVouchers({String? status}) async {
    final res = await _get('/api/vouchers/withdrawal',
        query: status != null ? {'status': status} : null);
    return List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> getWithdrawalVoucher(String id) async {
    final res = await _get('/api/vouchers/withdrawal/$id');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> createWithdrawalVoucher(
      Map<String, dynamic> data) async {
    final res = await _post('/api/vouchers/withdrawal', data);
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> updateWithdrawalVoucher(
      String id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/api/vouchers/withdrawal/$id');
    final res =
        await http.patch(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Request failed');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> submitWithdrawalVoucher(String id,
      {String submittedBy = 'keeper'}) async {
    final res = await _post(
        '/api/vouchers/withdrawal/$id/submit?submitted_by=${Uri.encodeComponent(submittedBy)}',
        {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> approveWithdrawalVoucher(String id,
      {String approvedBy = 'admin'}) async {
    final res = await _post(
        '/api/vouchers/withdrawal/$id/approve?approved_by=${Uri.encodeComponent(approvedBy)}',
        {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> rejectWithdrawalVoucher(String id,
      {String rejectedBy = 'admin'}) async {
    final res = await _post(
        '/api/vouchers/withdrawal/$id/reject?rejected_by=${Uri.encodeComponent(rejectedBy)}',
        {});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> deleteWithdrawalVoucher(String id) async {
    final uri = Uri.parse('$_baseUrl/api/vouchers/withdrawal/$id');
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Request failed');
    }
  }

  // ==================== PRODUCTION STANDARDS ====================
  Future<List<Map<String, dynamic>>> getProductionStandards({bool activeOnly = false}) async {
    final res = await _get('/api/production-standards',
        query: {'active_only': activeOnly ? 'true' : 'false'});
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> getProductionStandardByProduct(String productName) async {
    try {
      final res = await _get('/api/production-standards/by-product',
          query: {'name': productName});
      if (res == null) return null;
      return res as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> createProductionStandard(Map<String, dynamic> data) async {
    final res = await _post('/api/production-standards', data);
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProductionStandard(
      String id, Map<String, dynamic> data) async {
    final res = await _put('/api/production-standards/$id', data);
    return res as Map<String, dynamic>;
  }

  Future<void> deleteProductionStandard(String id) async {
    await _delete('/api/production-standards/$id');
  }

  // ==================== WASTE MONITORING ====================
  Future<Map<String, dynamic>> getWasteMonitoringDashboard({
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _get('/api/waste-monitoring/dashboard', query: {
      'from': from?.toIso8601String().split('T').first,
      'to': to?.toIso8601String().split('T').first,
    });
    return res as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getWasteMonitoringTrend({int days = 7}) async {
    final res = await _get('/api/waste-monitoring/trend', query: {'days': '$days'});
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ==================== HEALTH ====================
  Future<bool> isHealthy() async {
    try {
      final res = await _get('/api/health');
      return (res as Map<String, dynamic>)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  static bool get isConfigured => true;
}
