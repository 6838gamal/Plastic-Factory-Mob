// lib/presentation/pages/worker/raw_material_receiving_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/api_datasource.dart';
import '../../../data/models/inventory_summary_model.dart';
import '../../../data/models/voucher_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reference_data_provider.dart';
import '../../../core/constants/app_constants.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Providers خاصة بشاشة استلام المواد الخام
// ──────────────────────────────────────────────────────────────────────────────

final _receivingInventoryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'receiving').toList();
});

final _receivingIncomingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'staging_to_receiving');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

final _receivingOutgoingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'receiving_to_mixer');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

// ──────────────────────────────────────────────────────────────────────────────
// شاشة استلام المواد الخام - معدلة لاستقبال البيانات من مخزن الخلاط
// ──────────────────────────────────────────────────────────────────────────────

class RawMaterialReceivingPage extends ConsumerStatefulWidget {
  // ── معاملات لاستقبال البيانات من مخزن الخلاط ──
  final List<InventorySummaryModel>? preSelectedMaterials;
  final String? sourceWarehouse;
  final String? title;

  const RawMaterialReceivingPage({
    super.key,
    this.preSelectedMaterials,
    this.sourceWarehouse,
    this.title,
  });

  @override
  ConsumerState<RawMaterialReceivingPage> createState() => _RawMaterialReceivingPageState();
}

class _RawMaterialReceivingPageState extends ConsumerState<RawMaterialReceivingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<InventorySummaryModel> _incomingMaterials = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
    
    // ── معالجة المواد المستلمة من مخزن الخلاط ──
    if (widget.preSelectedMaterials != null && widget.preSelectedMaterials!.isNotEmpty) {
      _incomingMaterials = widget.preSelectedMaterials!;
      // نقل المواد إلى مخزن الاستلام
      _transferMaterialsToReceiving();
    }
  }

  // ── نقل المواد من مخزن الخلاط إلى مخزن الاستلام ──
  Future<void> _transferMaterialsToReceiving() async {
    if (_incomingMaterials.isEmpty || _isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final ds = ref.read(dataSourceProvider);
      final authState = ref.read(authProvider);
      final operatorName = authState.user?.name ?? authState.user?.email ?? 'مدير الاستلام';
      
      int successCount = 0;
      int failCount = 0;
      
      for (final material in _incomingMaterials) {
        try {
          // نقل المادة من مخزن الخلاط إلى مخزن الاستلام
          await ds.transferInventory(
            materialId: material.materialId,
            quantity: material.currentBalance,
            fromWarehouse: widget.sourceWarehouse ?? AppConstants.warehouseMixer,
            toWarehouse: 'receiving',
            notes: 'نقل تلقائي من مخزن الخلاط إلى شاشة الاستلام',
            createdBy: operatorName,
          );
          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('خطأ في نقل المادة ${material.materialName}: $e');
        }
      }
      
      if (mounted) {
        // عرض رسالة بنتيجة العملية
        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم نقل $successCount مادة بنجاح إلى شاشة الاستلام${failCount > 0 ? '، وفشل نقل $failCount مادة' : ''}'),
              backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
            ),
          );
        } else if (failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل نقل المواد إلى شاشة الاستلام'),
              backgroundColor: Colors.red,
            ),
          );
        }
        
        // تحديث البيانات
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_receivingInventoryProvider);
    ref.invalidate(_receivingIncomingProvider);
    ref.invalidate(_receivingOutgoingProvider);
    ref.invalidate(inventorySummaryProvider);
    setState(() {});
  }

  String get _operatorName {
    final auth = ref.read(authProvider);
    return auth.user?.name ?? auth.user?.email ?? 'مدير الاستلام';
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref
            .watch(_receivingIncomingProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    // ── عرض إشعار بوجود مواد مستلمة من الخلاط ──
    final hasIncomingFromMixer = _incomingMaterials.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'استلام المواد الخام'),
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
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المخزون'),
            Tab(icon: Icon(Icons.arrow_downward), text: 'وارد من المرحلي'),
            Tab(icon: Icon(Icons.arrow_upward), text: 'صادر للخلاط'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── عرض إشعار المواد المستلمة من الخلاط ──
          if (hasIncomingFromMixer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.green.shade200),
                ),
              ),
              child: Row(
                children: [
                  if (_isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.green,
                      ),
                    )
                  else
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isProcessing
                          ? 'جاري نقل ${_incomingMaterials.length} مادة من مخزن الخلاط...'
                          : 'تم استلام ${_incomingMaterials.length} مادة من مخزن الخلاط',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!_isProcessing)
                    TextButton(
                      onPressed: () {
                        _showReceivedMaterialsDialog(context);
                      },
                      child: const Text('عرض التفاصيل'),
                    ),
                ],
              ),
            ),
          // ── تبويبات المحتوى ──
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ReceivingInventoryTab(
                  onRefresh: _refresh,
                  preLoadedMaterials: _incomingMaterials,
                ),
                _ReceivingIncomingTab(
                  operatorName: _operatorName,
                  onRefresh: _refresh,
                ),
                _ReceivingOutgoingTab(
                  operatorName: _operatorName,
                  onRefresh: _refresh,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabs.index == 2
          ? FloatingActionButton.extended(
              backgroundColor: Colors.deepPurple,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('إرسال للخلاط', style: TextStyle(color: Colors.white)),
              onPressed: () => _openReceivingVoucherDialog(context, 'receiving_to_mixer'),
            )
          : null,
    );
  }

  // ── عرض تفاصيل المواد المستلمة من الخلاط ──
  void _showReceivedMaterialsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('المواد المستلمة من مخزن الخلاط'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'إجمالي: ${_incomingMaterials.length} مادة',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LimitedBox(
                maxHeight: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _incomingMaterials.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade50,
                      child: Icon(
                        Icons.science_outlined,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                    title: Text(
                      _incomingMaterials[i].materialName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_incomingMaterials[i].currentBalance.toStringAsFixed(2)} ${_incomingMaterials[i].unit}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReceivingVoucherDialog(BuildContext context, String transferType) async {
    await showDialog(
      context: context,
      builder: (_) => _ReceivingVoucherDialog(
        transferType: transferType,
        createdBy: _operatorName,
        onSaved: _refresh,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب المخزون - معدل لاستقبال المواد المستلمة من الخلاط
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingInventoryTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  final List<InventorySummaryModel> preLoadedMaterials;

  const _ReceivingInventoryTab({
    required this.onRefresh,
    this.preLoadedMaterials = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingInventoryProvider);
    
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (items) {
        // ── دمج المواد المستلمة من الخلاط مع المواد الموجودة ──
        final allItems = [...items, ...preLoadedMaterials];
        // إزالة التكرارات بناءً على materialId
        final uniqueItems = allItems.fold<List<InventorySummaryModel>>([], (list, item) {
          if (!list.any((m) => m.materialId == item.materialId)) {
            list.add(item);
          }
          return list;
        });

        if (uniqueItems.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد خام في شاشة الاستلام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('المواد الخام تصل هنا من المخزن المرحلي أو من مخزن الخلاط',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        
        final total = uniqueItems.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard(
              'إجمالي المواد الخام المستلمة', 
              total, 
              Colors.deepPurple,
              preLoadedMaterials.isNotEmpty 
                ? '(${preLoadedMaterials.length} من الخلاط)' 
                : null,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: uniqueItems.length,
                itemBuilder: (ctx, i) => _buildMaterialCard(
                  uniqueItems[i], 
                  Colors.deepPurple,
                  isFromMixer: preLoadedMaterials.any((m) => m.materialId == uniqueItems[i].materialId),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب وارد من المرحلي
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingIncomingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  const _ReceivingIncomingTab({required this.operatorName, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingIncomingProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد طلبات واردة من المخزن المرحلي', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('سيتم استلام المواد الخام هنا من المخزن المرحلي',
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
            itemBuilder: (ctx, i) => _ReceivingVoucherCard(
              voucher: vouchers[i],
              operatorName: operatorName,
              onAction: onRefresh,
              role: 'incoming',
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب صادر للخلاط
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingOutgoingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  const _ReceivingOutgoingTab({required this.operatorName, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingOutgoingProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_upward, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد سندات صادرة للخلاط', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('اضغط + لإنشاء سند تحويل للخلاط',
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
            itemBuilder: (ctx, i) => _ReceivingVoucherCard(
              voucher: vouchers[i],
              operatorName: operatorName,
              onAction: onRefresh,
              role: 'outgoing',
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// بطاقة السند لشاشة استلام المواد الخام
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingVoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final String operatorName;
  final VoidCallback onAction;
  final String role;

  const _ReceivingVoucherCard({
    required this.voucher,
    required this.operatorName,
    required this.onAction,
    required this.role,
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
            // Header
            Row(
              children: [
                Chip(
                  label: Text(_statusLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: _statusColor,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                if (role == 'incoming')
                  const Icon(Icons.arrow_downward, size: 16, color: Colors.deepPurple),
                if (role == 'outgoing')
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.deepPurple),
                const SizedBox(width: 4),
                Text(
                  voucher.voucherNumber ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (voucher.createdAt != null)
                  Text(
                    voucher.createdAt!.split('T').first,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Items
            if (voucher.itemNames.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: voucher.itemNames.take(4).map((name) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepPurple.shade100),
                    ),
                    child: Text(name, style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade800)),
                  );
                }).toList(),
              ),
            if (voucher.itemNames.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${voucher.itemNames.length - 4} مواد أخرى',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ),
            if (voucher.notes?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('ملاحظات: ${voucher.notes}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            // Actions
            if (!voucher.isConfirmed && !voucher.isCancelled) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 16),
                    label: const Text('إلغاء', style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final ok = await _confirm(context, 'تأكيد الإلغاء',
                          'هل تريد إلغاء سند ${voucher.voucherNumber}؟');
                      if (ok) {
                        try {
                          await ds.cancelTransferVoucher(voucher.id!);
                          onAction();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  // Submit (if draft)
                  if (voucher.isDraft)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('إرسال للمراجعة'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      onPressed: () async {
                        try {
                          await ds.submitTransferVoucher(voucher.id!);
                          onAction();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                          }
                        }
                      },
                    ),
                  // Confirm receipt — incoming: staging→receiving
                  if (role == 'incoming' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد استلام المواد الخام'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد استلام المواد الخام',
                          'هل تأكد استلام المواد الخام من المخزن المرحلي؟\nسيتم نقل المواد لشاشة الاستلام.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم تأكيد استلام المواد الخام ونقلها لشاشة الاستلام'),
                                      backgroundColor: Colors.deepPurple));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                            }
                          }
                        }
                      },
                    ),
                  // Confirm receipt — outgoing: receiving→mixer
                  if (role == 'outgoing' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد استلام الخلاط'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد استلام مخزن الخلاط',
                          'هل تأكد استلام المواد الخام من شاشة الاستلام؟\nسيتم نقل المواد لمخزن الخلطات.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم تأكيد استلام المواد الخام ونقلها لمخزن الخلطات'),
                                      backgroundColor: Colors.teal));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                            }
                          }
                        }
                      },
                    ),
                ],
              ),
            ],
            // Confirmed info
            if (voucher.isConfirmed && voucher.confirmedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text('تم التنفيذ بواسطة: ${voucher.confirmedBy}',
                        style: const TextStyle(color: Colors.green, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، تأكيد')),
        ],
      ),
    );
    return res ?? false;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// حوار إنشاء سند لشاشة استلام المواد الخام
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingVoucherDialog extends ConsumerStatefulWidget {
  final String transferType; // receiving_to_mixer
  final String? createdBy;
  final VoidCallback onSaved;

  const _ReceivingVoucherDialog({
    required this.transferType,
    required this.onSaved,
    this.createdBy,
  });

  @override
  ConsumerState<_ReceivingVoucherDialog> createState() => _ReceivingVoucherDialogState();
}

class _ReceivingVoucherDialogState extends ConsumerState<_ReceivingVoucherDialog> {
  final _notesCtrl = TextEditingController();
  final List<_VItemEntry> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _fromWarehouse => 'receiving';
  String get _title => 'سند صادر للخلاط';
  String get _flowLabel => 'شاشة استلام المواد الخام ← مخزن الخلطات';

  void _addItem() => setState(() => _items.add(_VItemEntry()));
  void _removeItem(int i) => setState(() => _items.removeAt(i));

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف بنداً واحداً على الأقل'), backgroundColor: Colors.red),
      );
      return;
    }
    final incomplete = <int>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.isEmpty || _items[i].qty <= 0) i + 1,
    ];
    if (incomplete.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('أكمل بيانات البند رقم ${incomplete.join("، ")} قبل الحفظ'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.createTransferVoucher({
        'notes': _notesCtrl.text.trim(),
        'created_by': widget.createdBy ?? 'مدير الاستلام',
        'transfer_type': widget.transferType,
        'items': _items
            .map((e) => {
                  'material_name': e.name,
                  'unit': e.unit,
                  'requested_qty': e.qty,
                  if (e.materialId != null) 'material_id': e.materialId,
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
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

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flow indicator
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
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('المواد الخام', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('إضافة بند'),
                    onPressed: _addItem,
                  ),
                ],
              ),
              const Divider(),
              ..._items.asMap().entries.map((e) => _VItemRow(
                    index: e.key,
                    entry: e.value,
                    materials: materials,
                    onRemove: () => _removeItem(e.key),
                    onChanged: () => setState(() {}),
                  )),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text('اضغط "إضافة بند" لإضافة مادة خام',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('حفظ', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// مكونات مساعدة
// ──────────────────────────────────────────────────────────────────────────────

Widget _buildSummaryCard(String title, double total, MaterialColor color, [String? badge]) {
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
        Icon(Icons.assignment_outlined, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold)),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const Spacer(),
        Text(
          '${total.toStringAsFixed(1)} كجم',
          style: TextStyle(color: color.shade800, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  );
}

Widget _buildMaterialCard(InventorySummaryModel item, MaterialColor color, {bool isFromMixer = false}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Container(
      decoration: BoxDecoration(
        border: isFromMixer 
            ? Border.all(color: Colors.green.shade300, width: 2)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isFromMixer ? Colors.green.shade100 : color.shade50,
          child: Icon(
            isFromMixer ? Icons.check_circle : Icons.science_outlined,
            color: isFromMixer ? Colors.green.shade700 : color.shade700,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.materialName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isFromMixer) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'من الخلاط',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Text(
          '${item.currentBalance.toStringAsFixed(2)} ${item.unit}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: item.currentBalance <= 0 ? Colors.red : color.shade700,
          ),
        ),
      ),
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// مكونات إدخال البنود
// ──────────────────────────────────────────────────────────────────────────────

class _VItemEntry {
  String name = '';
  String unit = 'كجم';
  double qty = 0;
  String? materialId;
}

class _VItemRow extends StatelessWidget {
  final int index;
  final _VItemEntry entry;
  final List<InventorySummaryModel> materials;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _VItemRow({
    required this.index,
    required this.entry,
    required this.materials,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final itemNo = index + 1;
    final selected = entry.name.isNotEmpty
        ? materials
            .where((m) => (entry.materialId != null && entry.materialId!.isNotEmpty)
                ? m.materialId == entry.materialId
                : m.materialName == entry.name)
            .firstOrNull
        : null;
    final available = selected?.currentBalance ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('البند $itemNo',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
              const Spacer(),
              InkWell(onTap: onRemove, child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20)),
            ],
          ),
          const SizedBox(height: 8),
          // Material dropdown
          materials.isEmpty
              ? TextField(
                  decoration: const InputDecoration(labelText: 'اسم المادة الخام', border: OutlineInputBorder()),
                  onChanged: (v) {
                    entry.name = v;
                    onChanged();
                  },
                )
              : DropdownButtonFormField<String>(
                  value: entry.name.isNotEmpty ? entry.name : null,
                  decoration: const InputDecoration(labelText: 'المادة الخام', border: OutlineInputBorder()),
                  items: materials
                      .map((m) => DropdownMenuItem(
                            value: m.materialName,
                            child: Text(
                              '${m.materialName} (${m.currentBalance.toStringAsFixed(1)} ${m.unit})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    entry.name = v ?? '';
                    final mat = materials.firstWhere((m) => m.materialName == v,
                        orElse: () => materials.first);
                    entry.materialId = mat.materialId;
                    entry.unit = mat.unit;
                    onChanged();
                  },
                ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: entry.qty > 0 ? entry.qty.toString() : '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية',
                    border: const OutlineInputBorder(),
                    helperText: available > 0 ? 'متاح: ${available.toStringAsFixed(2)}' : null,
                    helperStyle: const TextStyle(color: Colors.grey),
                  ),
                  onChanged: (v) {
                    entry.qty = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<String>(
                  value: entry.unit,
                  decoration: const InputDecoration(labelText: 'الوحدة', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'كجم', child: Text('كجم')),
                    DropdownMenuItem(value: 'جرام', child: Text('جرام')),
                    DropdownMenuItem(value: 'لتر', child: Text('لتر')),
                  ],
                  onChanged: (v) {
                    entry.unit = v ?? 'كجم';
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
