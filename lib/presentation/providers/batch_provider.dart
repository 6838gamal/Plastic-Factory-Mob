import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/machine_production_model.dart';
import '../../data/models/alert_model.dart';
import '../../data/models/inventory_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/helpers.dart';
import 'auth_provider.dart';

// ── Typed filter keys (Map keys have no structural equality in Dart) ──────────

@immutable
class BatchFilters {
  final DateTime? from;
  final DateTime? to;
  final String? workerId;

  const BatchFilters({this.from, this.to, this.workerId});

  @override
  bool operator ==(Object other) =>
      other is BatchFilters &&
      other.from == from &&
      other.to == to &&
      other.workerId == workerId;

  @override
  int get hashCode => Object.hash(from, to, workerId);
}

@immutable
class ProductionFilters {
  final DateTime? from;
  final DateTime? to;
  final String? machineId;

  const ProductionFilters({this.from, this.to, this.machineId});

  @override
  bool operator ==(Object other) =>
      other is ProductionFilters &&
      other.from == from &&
      other.to == to &&
      other.machineId == machineId;

  @override
  int get hashCode => Object.hash(from, to, machineId);
}

@immutable
class AlertFilters {
  final String? status;
  final String? severity;

  const AlertFilters({this.status, this.severity});

  @override
  bool operator ==(Object other) =>
      other is AlertFilters &&
      other.status == status &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(status, severity);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final batchesProvider = FutureProvider.family<List<BatchModel>, BatchFilters>(
  (ref, filters) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getBatches(
      from: filters.from,
      to: filters.to,
      workerId: filters.workerId,
    );
  },
);

final machineProductionsProvider =
    FutureProvider.family<List<MachineProductionModel>, ProductionFilters>(
  (ref, filters) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getMachineProductions(
      from: filters.from,
      to: filters.to,
      machineId: filters.machineId,
    );
  },
);

final alertsProvider =
    FutureProvider.family<List<AlertModel>, AlertFilters>(
  (ref, filters) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getAlerts(
      status: filters.status,
      severity: filters.severity,
    );
  },
);

// ── Save result types ─────────────────────────────────────────────────────────

class BatchSaveResult {
  final bool success;
  final String? error;
  final BatchModel? batch;

  const BatchSaveResult({required this.success, this.error, this.batch});
}

class ProductionSaveResult {
  final bool success;
  final String? error;
  final MachineProductionModel? production;

  const ProductionSaveResult({required this.success, this.error, this.production});
}

// ── Batch operations notifier ─────────────────────────────────────────────────

class BatchOperationsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<BatchSaveResult> saveBatch(Map<String, dynamic> batchData) async {
    state = const AsyncValue.loading();
    final ds = ref.read(dataSourceProvider);
    final auth = ref.read(authProvider);
    final transactionId = Helpers.generateTransactionId();

    try {
      final isDuplicate = await ds.checkTransactionExists(transactionId);
      if (isDuplicate) {
        state = const AsyncValue.data(null);
        return const BatchSaveResult(
          success: false,
          error: 'عملية مكررة، تم منع التنفيذ',
        );
      }

      final materials = batchData['materials'] as List<Map<String, dynamic>>? ?? [];
      // Only check inventory for materials that have an explicit material_id
      for (final mat in materials) {
        final materialId = mat['material_id'] as String?;
        if (materialId == null) continue;
        final required = (mat['quantity'] as num).toDouble();
        final inventory = await ds.getMaterialInventory(materialId, AppConstants.warehouseMixer);
        if (inventory != null && inventory.balance < required) {
          await ds.createAlert({
            'alert_type': 'insufficient_stock',
            'severity': AppConstants.severityCritical,
            'material_id': materialId,
            'material_name': inventory.materialName,
            'description':
                'الكمية المطلوبة من ${inventory.materialName} ($required كجم) أكبر من المتوفر (${inventory.balance} كجم)',
            'status': AppConstants.alertPending,
            'transaction_id': transactionId,
          });
          state = const AsyncValue.data(null);
          return BatchSaveResult(
            success: false,
            error:
                'الكمية المطلوبة من ${inventory.materialName} ($required ${inventory.unit}) أكبر من المتوفر (${inventory.balance} ${inventory.unit})',
          );
        }
      }

      final data = {
        ...batchData,
        'transaction_id': transactionId,
        'status': 'saved',
      };
      final batch = await ds.saveBatch(data);

      for (final mat in materials) {
        final materialId = mat['material_id'] as String?;
        if (materialId == null) continue;
        final quantity = (mat['quantity'] as num).toDouble();
        final inv = await ds.getMaterialInventory(materialId, AppConstants.warehouseMixer);
        if (inv != null) {
          final newBalance = inv.balance - quantity;
          await ds.updateInventoryBalance(materialId, AppConstants.warehouseMixer, newBalance);

          await ds.addInventoryTransaction(InventoryTransactionModel(
            id: '',
            materialId: materialId,
            warehouseType: AppConstants.warehouseMixer,
            transactionType: 'out',
            quantity: quantity,
            batchId: batch.id,
            transactionRef: transactionId,
            createdBy: auth.user?.email ?? 'worker',
            notes: 'خصم من طبخة ${batch.batchNumber}',
            createdAt: DateTime.now(),
          ));

          if (newBalance <= inv.minStock) {
            await ds.createAlert({
              'alert_type': 'low_stock',
              'severity': newBalance <= inv.minStock * 0.5
                  ? AppConstants.severityCritical
                  : AppConstants.severityHigh,
              'material_id': materialId,
              'material_name': inv.materialName,
              'batch_id': batch.id,
              'batch_number': batch.batchNumber,
              'description':
                  'مخزون ${inv.materialName} منخفض: ${newBalance.toStringAsFixed(2)} ${inv.unit}',
              'status': AppConstants.alertPending,
              'transaction_id': transactionId,
            });
          }
        }
      }

      await ds.addAuditLog({
        'action': AppConstants.auditCreate,
        'table_name': AppConstants.tbBatches,
        'record_id': batch.id,
        'new_values': data,
        'user_id': auth.user?.id ?? 'anonymous',
        'user_email': auth.user?.email,
        'transaction_id': transactionId,
        'description': 'إنشاء طبخة ${batch.batchNumber}',
      });

      state = const AsyncValue.data(null);
      return BatchSaveResult(success: true, batch: batch);
    } catch (e) {
      await ds.addAuditLog({
        'action': AppConstants.auditFailed,
        'table_name': AppConstants.tbBatches,
        'user_id': auth.user?.id ?? 'anonymous',
        'user_email': auth.user?.email,
        'transaction_id': transactionId,
        'description': 'فشل حفظ الطبخة: $e',
      });
      state = AsyncValue.error(e, StackTrace.current);
      return BatchSaveResult(success: false, error: 'فشل الحفظ: $e');
    }
  }

  Future<ProductionSaveResult> saveProduction(Map<String, dynamic> productionData) async {
    state = const AsyncValue.loading();
    final ds = ref.read(dataSourceProvider);
    final auth = ref.read(authProvider);
    final transactionId = Helpers.generateTransactionId();

    try {
      final data = {
        ...productionData,
        'transaction_id': transactionId,
        'status': 'saved',
        'worker_id': auth.user?.id ?? '',
      };
      final production = await ds.saveMachineProduction(data);

      final wasteQty = (productionData['waste_quantity'] as num?)?.toDouble() ?? 0;
      final producedQty = (productionData['produced_quantity'] as num?)?.toDouble() ?? 0;
      if (producedQty > 0) {
        final wastePercent = (wasteQty / producedQty) * 100;
        if (wastePercent > AppConstants.wasteHighThreshold) {
          await ds.createAlert({
            'alert_type': 'high_waste',
            'severity': AppConstants.severityHigh,
            'machine_id': productionData['machine_id'],
            'description':
                'هالك مرتفع: ${wastePercent.toStringAsFixed(2)}% في ماكينة ${productionData['machine_name']}',
            'status': AppConstants.alertPending,
            'transaction_id': transactionId,
          });
        }
      }

      final stopTime = (productionData['stop_time_minutes'] as num?)?.toDouble() ?? 0;
      if (stopTime > 0) {
        await ds.createAlert({
          'alert_type': 'machine_stop',
          'severity': stopTime > 60 ? AppConstants.severityHigh : AppConstants.severityMedium,
          'machine_id': productionData['machine_id'],
          'description': 'توقف ماكينة لمدة ${stopTime.toStringAsFixed(0)} دقيقة',
          'status': AppConstants.alertPending,
          'transaction_id': transactionId,
        });
      }

      await ds.addAuditLog({
        'action': AppConstants.auditCreate,
        'table_name': AppConstants.tbMachineProduction,
        'record_id': production.id,
        'new_values': data,
        'user_id': auth.user?.id ?? 'anonymous',
        'user_email': auth.user?.email,
        'transaction_id': transactionId,
        'description': 'تسجيل إنتاج ماكينة ${productionData['machine_name']}',
      });

      state = const AsyncValue.data(null);
      return ProductionSaveResult(success: true, production: production);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return ProductionSaveResult(success: false, error: 'فشل الحفظ: $e');
    }
  }
}

final batchOperationsProvider =
    NotifierProvider<BatchOperationsNotifier, AsyncValue<void>>(BatchOperationsNotifier.new);
