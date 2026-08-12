// lib/presentation/pages/production_manager/staging_warehouse_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/api_datasource.dart';
import '../../../data/models/inventory_summary_model.dart';
import '../../../data/models/voucher_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reference_data_provider.dart';
import '../worker/raw_material_receiving_page.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Providers
// ──────────────────────────────────────────────────────────────────────────────

final _stagingInventoryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'staging').toList();
});

final _stagingIncomingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'main_to_staging');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

final _stagingOutgoingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'staging_to_mixer');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

// ──────────────────────────────────────────────────────────────────────────────
// الصفحة الرئيسية - المخزن المرحلي
// ──────────────────────────────────────────────────────────────────────────────

class StagingWarehousePage extends ConsumerStatefulWidget {
  const StagingWarehousePage({super.key});

  @override
  ConsumerState<StagingWarehousePage> createState() => _StagingWarehousePageState();
}

class _StagingWarehousePageState extends ConsumerState<StagingWarehousePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_stagingInventoryProvider);
    ref.invalidate(_stagingIncomingProvider);
    ref.invalidate(_stagingOutgoingProvider);
    ref.invalidate(inventorySummaryProvider);
  }

  String get _operatorName {
    final auth = ref.read(authProvider);
    return auth.user?.name ?? auth.user?.email ?? 'مدير الإنتاج';
  }

  // دالة التنقل إلى شاشة استلام المواد الخام
  void _navigateToReceivingWarehouse(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RawMaterialReceivingPage(), // ✅ بدون const
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref
            .watch(_stagingIncomingProvider)
            .valueOrNull
            ?.where((v) => v.isPending)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        title: const Text('المخزن المرحلي'),
        actions: [
          // زر التنقل إلى شاشة استلام المواد الخام
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            onPressed: () => _navigateToReceivingWarehouse(context),
            tooltip: 'استلام المواد الخام',
          ),
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
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.arrow_downward),
              ),
              text: 'وارد من الرئيسي',
            ),
            const Tab(icon: Icon(Icons.arrow_upward), text: 'صادر للخلاط'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _InventoryTab(onRefresh: _refresh),
          _IncomingTab(operatorName: _operatorName, onRefresh: _refresh),
          _OutgoingTab(operatorName: _operatorName, onRefresh: _refresh),
        ],
      ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton.extended(
              backgroundColor: Colors.deepOrange,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('طلب من الرئيسي', style: TextStyle(color: Colors.white)),
              onPressed: () => _openVoucherDialog(context, 'main_to_staging'),
            )
          : _tabs.index == 2
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.deepOrange,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('إرسال للخلاط', style: TextStyle(color: Colors.white)),
                  onPressed: () => _openVoucherDialog(context, 'staging_to_mixer'),
                )
              : null,
    );
  }

  Future<void> _openVoucherDialog(BuildContext context, String transferType) async {
    await showDialog(
      context: context,
      builder: (_) => _StagingVoucherDialog(
        transferType: transferType,
        createdBy: _operatorName,
        onSaved: _refresh,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب المخزون
// ──────────────────────────────────────────────────────────────────────────────

class _InventoryTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _InventoryTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_stagingInventoryProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد في المخزن المرحلي', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('استخدم "وارد من الرئيسي" لطلب مواد',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        final total = items.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard('إجمالي المخزون المرحلي', total, Colors.deepOrange),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (ctx, i) => _buildMaterialCard(items[i], Colors.deepOrange),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب وارد من الرئيسي
// ──────────────────────────────────────────────────────────────────────────────

class _IncomingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  const _IncomingTab({required this.operatorName, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_stagingIncomingProvider);
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
                Text('لا توجد طلبات واردة من المخزن الرئيسي', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('اضغط + لإنشاء طلب تحويل من الرئيسي',
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

class _OutgoingTab extends ConsumerWidget {
  final String operatorName;
  final VoidCallback onRefresh;
  const _OutgoingTab({required this.operatorName, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_stagingOutgoingProvider);
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
            itemBuilder: (ctx, i) => _VoucherCard(
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
// بطاقة السند
// ──────────────────────────────────────────────────────────────────────────────

class _VoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final String operatorName;
  final VoidCallback onAction;
  final String role; // 'incoming' or 'outgoing'

  const _VoucherCard({
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
                  const Icon(Icons.arrow_downward, size: 16, color: Colors.blue),
                if (role == 'outgoing')
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.orange),
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
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepOrange.shade100),
                    ),
                    child: Text(name, style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade800)),
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
                  // Confirm receipt — incoming: main→staging
                  if (role == 'incoming' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد الاستلام للمرحلي'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () async {
                        final ok = await _confirm(context, 'تأكيد الاستلام',
                            'هل تأكد استلام المواد من المخزن الرئيسي؟\nسيتم نقل المواد للمخزن المرحلي.');
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم تأكيد الاستلام ونقل المواد للمخزن المرحلي'),
                                      backgroundColor: Colors.green));
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
                  // Confirm receipt — outgoing: staging→mixer
                  if (role == 'outgoing' && voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد استلام الخلاط'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد استلام مخزن الخلاط',
                          'هل تأكد استلام المواد من المخزن المرحلي؟\nسيتم نقل المواد لمخزن الخلطات.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم تأكيد الاستلام ونقل المواد لمخزن الخلطات'),
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
// حوار إنشاء السند
// ──────────────────────────────────────────────────────────────────────────────

class _StagingVoucherDialog extends ConsumerStatefulWidget {
  final String transferType; // main_to_staging | staging_to_mixer
  final String? createdBy;
  final VoidCallback onSaved;

  const _StagingVoucherDialog({
    required this.transferType,
    required this.onSaved,
    this.createdBy,
  });

  @override
  ConsumerState<_StagingVoucherDialog> createState() => _StagingVoucherDialogState();
}

class _StagingVoucherDialogState extends ConsumerState<_StagingVoucherDialog> {
  final _notesCtrl = TextEditingController();
  final List<_VItemEntry> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _fromWarehouse =>
      widget.transferType == 'main_to_staging' ? 'main' : 'staging';

  String get _title =>
      widget.transferType == 'main_to_staging'
          ? 'طلب تحويل من المخزن الرئيسي'
          : 'سند صادر للخلاط';

  String get _flowLabel =>
      widget.transferType == 'main_to_staging'
          ? 'المخزن الرئيسي ← المخزن المرحلي'
          : 'المخزن المرحلي ← مخزن الخلطات';

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
        'created_by': widget.createdBy ?? 'مدير الإنتاج',
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
                  color: Colors.deepOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.deepOrange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _flowLabel,
                        style: const TextStyle(color: Colors.deepOrange, fontSize: 13),
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
                  const Text('المواد', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    child: Text('اضغط "إضافة بند" لإضافة مادة',
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
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

Widget _buildSummaryCard(String title, double total, MaterialColor color) {
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
        Icon(Icons.warehouse, color: color),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange)),
              const Spacer(),
              InkWell(onTap: onRemove, child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20)),
            ],
          ),
          const SizedBox(height: 8),
          // Material dropdown
          materials.isEmpty
              ? TextField(
                  decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder()),
                  onChanged: (v) {
                    entry.name = v;
                    onChanged();
                  },
                )
              : DropdownButtonFormField<String>(
                  value: entry.name.isNotEmpty ? entry.name : null,
                  decoration: const InputDecoration(labelText: 'المادة', border: OutlineInputBorder()),
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
