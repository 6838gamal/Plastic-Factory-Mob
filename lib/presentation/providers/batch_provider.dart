import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/machine_production_model.dart';
import '../../data/models/alert_model.dart';
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

final batchesProvider = FutureProvider.autoDispose.family<List<BatchModel>, BatchFilters>(
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
    FutureProvider.autoDispose.family<List<MachineProductionModel>, ProductionFilters>(
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

      // ── حفظ الطبخة — الـ backend يتولى كل شيء: ──────────────────────────────
      // • التحقق من الرصيد الكافي (prevent_negative_stock)
      // • الخصم من مخزن الخلاط
      // • تسجيل inventory_transactions
      // • إنشاء تنبيهات مخزون منخفض / ناضب
      // • تسجيل audit_log
      // لا تُكرر هذه العمليات هنا وإلا سيحدث خصم مزدوج.
      final data = {
        ...batchData,
        'transaction_id': transactionId,
        'status': 'saved',
      };
      final batch = await ds.saveBatch(data);

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
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      return BatchSaveResult(success: false, error: errMsg);
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
      final msg = e.toString().replaceFirst('Exception: ', '');
      return ProductionSaveResult(success: false, error: msg);
    }
  }
}

final batchOperationsProvider =
    NotifierProvider<BatchOperationsNotifier, AsyncValue<void>>(BatchOperationsNotifier.new);
