import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reference_models.dart';
import 'seed_data.dart';

class LocalDataService {
  static const _wKey = 'lref_workers';
  static const _mKey = 'lref_machines';
  static const _xKey = 'lref_mixers';
  static const _pKey = 'lref_products';
  static const _tKey = 'lref_mixture_types';
  static const _seededKey = 'lref_seeded_v1';

  /// Seeds default data on first app run. Safe to call every startup.
  static Future<void> seedIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) == true) return;

    for (final w in SeedData.workers) {
      await _upsert(_wKey, Map<String, dynamic>.from(w));
    }
    for (final m in SeedData.machines) {
      await _upsert(_mKey, Map<String, dynamic>.from(m));
    }
    for (final x in SeedData.mixers) {
      await _upsert(_xKey, Map<String, dynamic>.from(x));
    }
    for (final p in SeedData.products) {
      await _upsert(_pKey, Map<String, dynamic>.from(p));
    }
    for (final t in SeedData.mixtureTypes) {
      await _upsert(_tKey, Map<String, dynamic>.from(t));
    }

    await prefs.setBool(_seededKey, true);
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static String _now() => DateTime.now().toIso8601String();

  static Future<List<Map<String, dynamic>>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  static Future<void> _save(
      String key, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(list));
  }

  static Future<void> _upsert(
      String key, Map<String, dynamic> data) async {
    final list = await _load(key);
    final id = data['id'] as String?;
    final isInactive = data['is_active'] == false;

    if (id != null) {
      final idx = list.indexWhere((e) => e['id'] == id);
      if (isInactive) {
        if (idx >= 0) list.removeAt(idx);
      } else if (idx >= 0) {
        list[idx] = {...list[idx], ...data};
      } else {
        list.add({...data, 'created_at': _now()});
      }
    } else if (!isInactive) {
      list.add({...data, 'id': _newId(), 'is_active': true, 'created_at': _now()});
    }
    await _save(key, list);
  }

  static Future<List<WorkerModel>> getWorkers() async {
    final list = await _load(_wKey);
    return list.map((e) => WorkerModel.fromJson(e)).toList();
  }

  static Future<void> upsertWorker(Map<String, dynamic> data) =>
      _upsert(_wKey, data);

  static Future<void> deleteWorker(String id) async {
    final list = await _load(_wKey);
    list.removeWhere((e) => e['id'] == id);
    await _save(_wKey, list);
  }

  static Future<List<MachineModel>> getMachines() async {
    final list = await _load(_mKey);
    return list.map((e) => MachineModel.fromJson(e)).toList();
  }

  static Future<void> upsertMachine(Map<String, dynamic> data) =>
      _upsert(_mKey, data);

  static Future<List<MixerModel>> getMixers() async {
    final list = await _load(_xKey);
    return list.map((e) => MixerModel.fromJson(e)).toList();
  }

  static Future<void> upsertMixer(Map<String, dynamic> data) =>
      _upsert(_xKey, data);

  static Future<List<ProductModel>> getProducts() async {
    final list = await _load(_pKey);
    return list.map((e) => ProductModel.fromJson(e)).toList();
  }

  static Future<void> upsertProduct(Map<String, dynamic> data) =>
      _upsert(_pKey, data);

  static Future<List<MixtureTypeModel>> getMixtureTypes() async {
    final list = await _load(_tKey);
    return list.map((e) => MixtureTypeModel.fromJson(e)).toList();
  }

  static Future<void> upsertMixtureType(Map<String, dynamic> data) =>
      _upsert(_tKey, data);
}
