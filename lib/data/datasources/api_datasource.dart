import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/raw_material_model.dart';
import '../models/inventory_model.dart';
import '../models/batch_model.dart';
import '../models/machine_production_model.dart';
import '../models/alert_model.dart';
import '../models/audit_log_model.dart';
import '../models/reference_models.dart';
import '../local/local_data_service.dart';

class ApiDataSource {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://plastic-factory-api.onrender.com',
  );

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
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (filteredQuery?.isEmpty ?? true) ? null : filteredQuery,
    );
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.post(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.put(uri, headers: _headers, body: jsonEncode(data));
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
    return jsonDecode(res.body);
  }

  Future<void> _delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
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

  // ==================== INVENTORY ====================
  Future<List<InventoryModel>> getInventory({String? warehouseType}) async {
    final res = await _get('/api/inventory', query: {'warehouse_type': warehouseType});
    return (res as List).map((e) => InventoryModel.fromJson(e)).toList();
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

  // ==================== WORKERS (local) ====================
  Future<List<WorkerModel>> getWorkers() => LocalDataService.getWorkers();

  Future<void> upsertWorker(Map<String, dynamic> data) =>
      LocalDataService.upsertWorker(data);

  Future<void> deleteWorker(String id) => LocalDataService.deleteWorker(id);

  // ==================== PRODUCTS (local) ====================
  Future<List<ProductModel>> getProducts() => LocalDataService.getProducts();

  Future<void> upsertProduct(Map<String, dynamic> data) =>
      LocalDataService.upsertProduct(data);

  // ==================== MACHINES (local) ====================
  Future<List<MachineModel>> getMachines() => LocalDataService.getMachines();

  Future<void> upsertMachine(Map<String, dynamic> data) =>
      LocalDataService.upsertMachine(data);

  // ==================== MIXERS (local) ====================
  Future<List<MixerModel>> getMixers() => LocalDataService.getMixers();

  Future<void> upsertMixer(Map<String, dynamic> data) =>
      LocalDataService.upsertMixer(data);

  // ==================== MIXTURE TYPES (local) ====================
  Future<List<MixtureTypeModel>> getMixtureTypes() =>
      LocalDataService.getMixtureTypes();

  Future<void> upsertMixtureType(Map<String, dynamic> data) =>
      LocalDataService.upsertMixtureType(data);

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

  // ==================== IMAGES ====================
  Future<String?> uploadImage(String bucket, String path, List<int> bytes) async {
    final uri = Uri.parse('$baseUrl/api/upload/$bucket');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_token != null ? {'Authorization': 'Bearer $_token'} : {})
      ..files.add(http.MultipartFile.fromBytes('file', Uint8List.fromList(bytes), filename: path));
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    if (res.statusCode >= 400) return null;
    final body = jsonDecode(res.body);
    return body['url'] as String?;
  }

  // ==================== DASHBOARD ====================
  Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await _get('/api/dashboard/stats');
    return res as Map<String, dynamic>;
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

  static bool get isConfigured => baseUrl.isNotEmpty;
}
