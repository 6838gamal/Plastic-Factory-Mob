// lib/presentation/pages/worker/raw_material_receiving_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/api_datasource.dart';
import '../../../data/models/inventory_summary_model.dart';
import '../../../data/models/inventory_model.dart';
import '../../../data/models/voucher_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reference_data_provider.dart';
import '../../../core/constants/app_constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Providers
// ──────────────────────────────────────────────────────────────────────────────

final receivingInventoryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'receiving').toList();
});

final receivingIncomingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'mixer_to_receiving');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

final receivingOutgoingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'receiving_to_ready');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

final readyForUseProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'ready_for_use').toList();
});

// ──────────────────────────────────────────────────────────────────────────────
// شاشة استلام المواد الخام
// ──────────────────────────────────────────────────────────────────────────────

class RawMaterialReceivingPage extends ConsumerStatefulWidget {
  const RawMaterialReceivingPage({super.key});

  @override
  ConsumerState<RawMaterialReceivingPage> createState() => _RawMaterialReceivingPageState();
}

class _RawMaterialReceivingPageState extends ConsumerState<RawMaterialReceivingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(receivingInventoryProvider);
    ref.invalidate(receivingIncomingProvider);
    ref.invalidate(receivingOutgoingProvider);
    ref.invalidate(readyForUseProvider);
    ref.invalidate(inventorySummaryProvider);
  }

  String get _operatorName {
    final auth = ref.read(authProvider);
    return auth.user?.name ?? auth.user?.email ?? 'مدير الاستلام';
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openVoucherDialog(BuildContext context, String transferType) async {
    await showDialog(
      context: context,
      builder: (_) => _ReceivingVoucherDialog(
        transferType: transferType,
        createdBy: _operatorName,
        onSaved: _refresh,
        showError: _showErrorSnackBar,
        showSuccess: _showSuccessSnackBar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingIncoming = ref
            .watch(receivingIncomingProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    final pendingOutgoing = ref
            .watch(receivingOutgoingProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text('استلام المواد الخام'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المخزون'),
            Tab(
              icon: Badge(
                isLabelVisible: pendingIncoming > 0,
                label: Text('$pendingIncoming'),
                child: const Icon(Icons.arrow_downward),
              ),
              text: 'وارد من الخلاط',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: pendingOutgoing > 0,
                label: Text('$pendingOutgoing'),
                child: const Icon(Icons.arrow_upward),
              ),
              text: 'صادر للجاهز',
            ),
            const Tab(
              icon: Icon(Icons.check_circle_outline),
              text: 'جاهز للاستخدام',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _InventoryTab(
            onRefresh: _refresh,
            showError: _showErrorSnackBar,
            showSuccess: _showSuccessSnackBar,
          ),
          _IncomingTab(
            operatorName: _operatorName,
            onRefresh: _refresh,
            showError: _showErrorSnackBar,
            showSuccess: _showSuccessSnackBar,
          ),
          _OutgoingTab(
            operatorName: _operatorName,
            onRefresh: _refresh,
            showError: _showErrorSnackBar,
            showSuccess: _showSuccessSnackBar,
          ),
          _ReadyForUseTab(onRefresh: _refresh),
        ],
      ),
      floatingActionButton: _tabs.index == 1
          ? null
          : _tabs.index == 2
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.deepPurple,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('إرسال للجاهز', style: TextStyle(color: Colors.white)),
                  onPressed: () => _openVoucherDialog(context, 'receiving_to_ready'),
                )
              : null,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب المخزون
// ──────────────────────────────────────────────────────────────────────────────

class _InventoryTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;

  const _InventoryTab({
    required this.onRefresh,
    required this.showError,
    required this.showSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivingInventoryProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل المخزون', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Text(e.toString(), style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد في شاشة الاستلام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('انتظر وصول مواد من مخزن الخلاط',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        final total = items.fold(0.0, (s, m) => s + m.currentBalance);
        
        return Column(
          children: [
            _buildSummaryCard(
              title: 'إجمالي المخزون في شاشة الاستلام',
              total: total,
              color: Colors.deepPurple,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final m = items[i];
                  return _buildMaterialCard(m, Colors.deepPurple);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب وارد من الخلاط
// ──────────────────────────────────────────────────────────────────────────────

class _IncomingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;

  const _IncomingTab({
    required this.operatorName,
    required this.onRefresh,
    required this.showError,
    required this.showSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivingIncomingProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل الطلبات الواردة', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Text(e.toString(), style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد طلبات واردة من مخزن الخلاط', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('سيتم عرض الطلبات هنا بعد إنشائها من مخزن الخلاط',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vouchers.length,
            itemBuilder: (ctx, i) => _VoucherCard(
              key: ValueKey(vouchers[i].id),
              voucher: vouchers[i],
              operatorName: operatorName,
              onAction: onRefresh,
              role: 'incoming',
              showError: showError,
              showSuccess: showSuccess,
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب صادر للجاهز
// ──────────────────────────────────────────────────────────────────────────────

class _OutgoingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;

  const _OutgoingTab({
    required this.operatorName,
    required this.onRefresh,
    required this.showError,
    required this.showSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivingOutgoingProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل السندات الصادرة', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Text(e.toString(), style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_upward, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد سندات صادرة للجاهز للاستخدام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('اضغط + لإنشاء سند تحويل للجاهز للاستخدام',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vouchers.length,
            itemBuilder: (ctx, i) => _VoucherCard(
              key: ValueKey(vouchers[i].id),
              voucher: vouchers[i],
              operatorName: operatorName,
              onAction: onRefresh,
              role: 'outgoing',
              showError: showError,
              showSuccess: showSuccess,
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب جاهز للاستخدام
// ──────────────────────────────────────────────────────────────────────────────

class _ReadyForUseTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _ReadyForUseTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readyForUseProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('حدث خطأ أثناء تحميل المواد الجاهزة', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد جاهزة للاستخدام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('المواد تظهر هنا بعد تأكيد استلامها من شاشة الاستلام',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        final total = items.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard(
              title: 'إجمالي المواد الجاهزة للاستخدام',
              total: total,
              color: Colors.green,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final m = items[i];
                  return _buildMaterialCard(m, Colors.green);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// بطاقة السند الموحدة
// ──────────────────────────────────────────────────────────────────────────────

class _VoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final String operatorName;
  final VoidCallback onAction;
  final String role;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;

  const _VoucherCard({
    super.key,
    required this.voucher,
    required this.operatorName,
    required this.onAction,
    required this.role,
    required this.showError,
    required this.showSuccess,
  });

  Color get _statusColor {
    switch (voucher.status) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String get _statusLabel {
    switch (voucher.status) {
      case 'confirmed':
        return 'مُنفَّذ';
      case 'pending':
        return 'قيد الانتظار';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'مسودة';
    }
  }

  String get _transferLabel {
    return role == 'incoming' 
        ? 'مخزن الخلاط ← شاشة الاستلام'
        : 'شاشة الاستلام ← جاهز للاستخدام';
  }

  Color get _transferColor {
    return role == 'incoming' ? Colors.deepPurple : Colors.green;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.read(dataSourceProvider);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس البطاقة
            Row(
              children: [
                Chip(
                  label: Text(_statusLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _statusColor,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                Icon(
                  role == 'incoming' ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                  color: _transferColor,
                ),
                const SizedBox(width: 4),
                Text(
                  voucher.voucherNumber ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (voucher.createdAt != null)
                  Text(
                    _formatDate(voucher.createdAt!),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
            
            // نوع التحويل
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _transferLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: _transferColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // ── عرض المادة مع الكمية المحددة ──
            if (voucher.items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.shade100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      voucher.items.first.materialName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${voucher.items.first.requestedQty.toStringAsFixed(2)} ${voucher.items.first.unit}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            if (voucher.notes?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'ملاحظات: ${voucher.notes}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            
            // ─── الأزرار ──────────────────────────────────────────────────────
            if (!voucher.isConfirmed && !voucher.isCancelled) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // إلغاء
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 16),
                    label: const Text('إلغاء', style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final ok = await _confirmDialog(
                        context,
                        'تأكيد الإلغاء',
                        'هل تريد إلغاء سند ${voucher.voucherNumber}؟',
                      );
                      if (ok) {
                        try {
                          await ds.cancelTransferVoucher(voucher.id!);
                          showSuccess(context, '✅ تم إلغاء السند بنجاح');
                          onAction();
                        } catch (e) {
                          showError(context, '❌ فشل إلغاء السند: ${e.toString()}');
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  
                  // إرسال للمراجعة (إذا كان مسودة)
                  if (voucher.isDraft)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('إرسال للمراجعة'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      onPressed: () async {
                        try {
                          await ds.submitTransferVoucher(voucher.id!);
                          showSuccess(context, '✅ تم إرسال السند للمراجعة');
                          onAction();
                        } catch (e) {
                          showError(context, '❌ فشل إرسال السند: ${e.toString()}');
                        }
                      },
                    ),
                  
                  // تأكيد الاستلام (إذا كان في انتظار)
                  if (voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: Text(
                        role == 'incoming' 
                            ? 'تأكيد استلام للاستلام' 
                            : 'تأكيد للجاهز للاستخدام',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: role == 'incoming' ? Colors.deepPurple : Colors.green,
                      ),
                      onPressed: () async {
                        final confirmMsg = role == 'incoming'
                            ? 'هل تأكد استلام المواد من مخزن الخلاط؟\nسيتم نقل المواد لشاشة الاستلام.'
                            : 'هل تأكد استلام المواد من شاشة الاستلام؟\nسيتم نقل المواد للجاهز للاستخدام.';
                        
                        final ok = await _confirmDialog(
                          context,
                          'تأكيد الاستلام',
                          confirmMsg,
                        );
                        
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {
                              'confirmed_by': operatorName,
                            });
                            
                            final successMsg = role == 'incoming'
                                ? '✅ تم تأكيد الاستلام ونقل المواد لشاشة الاستلام'
                                : '✅ تم تأكيد الاستلام ونقل المواد للجاهز للاستخدام';
                            
                            showSuccess(context, successMsg);
                            onAction();
                          } catch (e) {
                            showError(context, '❌ فشل تأكيد الاستلام: ${e.toString()}');
                          }
                        }
                      },
                    ),
                ],
              ),
            ],
            
            // معلومات التأكيد
            if (voucher.isConfirmed && voucher.confirmedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'تم التنفيذ بواسطة: ${voucher.confirmedBy}',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDialog(BuildContext context, String title, String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، تأكيد'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr.split('T').first;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// حوار إنشاء السند (مادة واحدة فقط)
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingVoucherDialog extends ConsumerStatefulWidget {
  final String transferType;
  final String? createdBy;
  final VoidCallback onSaved;
  final void Function(BuildContext, String) showError;
  final void Function(BuildContext, String) showSuccess;

  const _ReceivingVoucherDialog({
    required this.transferType,
    required this.onSaved,
    this.createdBy,
    required this.showError,
    required this.showSuccess,
  });

  @override
  ConsumerState<_ReceivingVoucherDialog> createState() => _ReceivingVoucherDialogState();
}

class _ReceivingVoucherDialogState extends ConsumerState<_ReceivingVoucherDialog> {
  final _notesCtrl = TextEditingController();
  String _selectedMaterialId = '';
  String _selectedMaterialName = '';
  String _selectedUnit = 'كجم';
  double _quantity = 0;
  final TextEditingController _qtyController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  String get _fromWarehouse => 'receiving';
  String get _title => 'سند صادر للجاهز للاستخدام';
  String get _flowLabel => 'شاشة الاستلام ← جاهز للاستخدام';

  Future<void> _save() async {
    if (_selectedMaterialId.isEmpty) {
      widget.showError(context, '⚠️ اختر مادة أولاً');
      return;
    }

    if (_quantity <= 0) {
      widget.showError(context, '⚠️ أدخل كمية صحيحة');
      return;
    }

    setState(() => _loading = true);

    try {
      final ds = ref.read(dataSourceProvider);
      
      await ds.createTransferVoucher({
        'notes': _notesCtrl.text.trim(),
        'created_by': widget.createdBy ?? 'مدير الاستلام',
        'transfer_type': widget.transferType,
        'items': [
          {
            'material_name': _selectedMaterialName,
            'unit': _selectedUnit,
            'requested_qty': _quantity,
            'material_id': _selectedMaterialId,
          }
        ],
      });

      if (mounted) {
        Navigator.pop(context);
        widget.showSuccess(context, '✅ تم إنشاء السند بنجاح (قيد الانتظار)');
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        widget.showError(context, '❌ فشل إنشاء السند: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(inventorySummaryProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == _fromWarehouse)
            .toList() ??
        [];

    if (_selectedMaterialId.isEmpty && materials.isNotEmpty) {
      _selectedMaterialId = materials.first.materialId;
      _selectedMaterialName = materials.first.materialName;
      _selectedUnit = materials.first.unit;
    }

    final selectedMaterial = materials.firstWhere(
      (m) => m.materialId == _selectedMaterialId,
      orElse: () => materials.isNotEmpty ? materials.first : InventorySummaryModel.empty(),
    );

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مؤشر التدفق
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.deepPurple, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _flowLabel,
                        style: const TextStyle(color: Colors.deepPurple, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // اختيار المادة
              DropdownButtonFormField<String>(
                value: _selectedMaterialId.isNotEmpty ? _selectedMaterialId : null,
                decoration: const InputDecoration(
                  labelText: 'المادة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.science_outlined),
                ),
                items: materials
                    .map((m) => DropdownMenuItem(
                          value: m.materialId,
                          child: Text(
                            '${m.materialName} (${m.currentBalance.toStringAsFixed(1)} ${m.unit})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    final mat = materials.firstWhere((m) => m.materialId == v);
                    setState(() {
                      _selectedMaterialId = v;
                      _selectedMaterialName = mat.materialName;
                      _selectedUnit = mat.unit;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // الكمية
              TextFormField(
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الكمية (${selectedMaterial.unit})',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.scale_outlined),
                  helperText: selectedMaterial.id.isNotEmpty
                      ? 'المتاح: ${selectedMaterial.currentBalance.toStringAsFixed(2)} ${selectedMaterial.unit}'
                      : null,
                  helperStyle: const TextStyle(color: Colors.grey),
                ),
                onChanged: (v) {
                  _quantity = double.tryParse(v) ?? 0;
                },
              ),
              const SizedBox(height: 16),
              
              // ملاحظات
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_add_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
          ),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'حفظ',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// مكونات مساعدة
// ──────────────────────────────────────────────────────────────────────────────

Widget _buildSummaryCard({
  required String title,
  required double total,
  required MaterialColor color,
}) {
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      children: [
        Icon(Icons.inventory_2_outlined, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(
          '${total.toStringAsFixed(1)} كجم',
          style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  );
}

Widget _buildMaterialCard(InventorySummaryModel item, MaterialColor color) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: color.shade50,
        child: Icon(Icons.science_outlined, color: color.shade700),
      ),
      title: Text(item.materialName, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(
        '${item.currentBalance.toStringAsFixed(2)} ${item.unit}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: item.currentBalance <= 0 ? Colors.red : color.shade700,
        ),
      ),
    ),
  );
}
