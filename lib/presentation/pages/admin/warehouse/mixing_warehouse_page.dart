import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/voucher_models.dart';
import '../../../../core/utils/helpers.dart';
import '../../../providers/auth_provider.dart' show dataSourceProvider;
import '../../../providers/reference_data_provider.dart' show inventorySummaryProvider;
import 'warehouse_manager_page.dart'
    show TransferVoucherCard, StatusBadge, TransferTab, TransferVoucherDialog, transferVouchersProvider;

// ── Providers ────────────────────────────────────────────────────

final _pendingTransfersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getPendingTransfers();
});

final _allTransfersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getTransferVouchers(status: 'confirmed');
});

final _returnVouchersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getReturnVouchers();
});

// ── Page ─────────────────────────────────────────────────────────

class MixingWarehousePage extends ConsumerStatefulWidget {
  const MixingWarehousePage({super.key});

  @override
  ConsumerState<MixingWarehousePage> createState() => _MixingWarehousePageState();
}

class _MixingWarehousePageState extends ConsumerState<MixingWarehousePage>
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

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(_pendingTransfersProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox_outlined, size: 18),
                    const SizedBox(width: 6),
                    const Text('استلام وارد'),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(icon: Icon(Icons.swap_horiz_outlined), text: 'سندات التحويل'),
              const Tab(icon: Icon(Icons.assignment_return_outlined), text: 'سندات المرتجع'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _PendingTransfersTab(),
                TransferTab(),
                _ReturnVouchersTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: switch (_tabs.index) {
        1 => FloatingActionButton.extended(
            onPressed: () => _showCreateTransferDialog(context),
            icon: const Icon(Icons.swap_horiz_outlined),
            label: const Text('سند تحويل جديد'),
            backgroundColor: Colors.blue,
          ),
        2 => FloatingActionButton.extended(
            onPressed: () => _showCreateReturnDialog(context),
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('سند مرتجع جديد'),
            backgroundColor: Colors.deepOrange,
          ),
        _ => null,
      },
    );
  }

  void _showCreateTransferDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => TransferVoucherDialog(
        onSaved: () {
          ref.invalidate(transferVouchersProvider);
        },
      ),
    );
  }

  void _showCreateReturnDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => _ReturnVoucherDialog(
        onSaved: () {
          ref.invalidate(_returnVouchersProvider);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Pending Transfers Tab
// ══════════════════════════════════════════════════════════════════

class _PendingTransfersTab extends ConsumerWidget {
  const _PendingTransfersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(_pendingTransfersProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_pendingTransfersProvider);
        ref.invalidate(_allTransfersProvider);
      },
      child: pending.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Text('لا توجد سندات في انتظار التأكيد', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 6),
                  Text('جميع السندات مكتملة ✓', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            );
          }
          return Column(
            children: [
              // ── لافتة المصدر ──────────────────────────────────
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outlined, color: Colors.teal, size: 16),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مصدر الوارد: المخزن الرئيسي فقط',
                          style: TextStyle(color: Colors.teal, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'لا يُسمح باستلام وارد من أي طرف خارجي',
                          style: TextStyle(color: Colors.teal, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final v = TransferVoucherModel.fromJson(list[i]);
                    return TransferVoucherCard(
                      voucher: v,
                      onAction: () {
                        ref.invalidate(_pendingTransfersProvider);
                        ref.invalidate(_allTransfersProvider);
                      },
                      role: 'mixer',
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: ${Helpers.friendlyError(e)}')),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Return Vouchers Tab
// ══════════════════════════════════════════════════════════════════

class _ReturnVouchersTab extends ConsumerWidget {
  const _ReturnVouchersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(_returnVouchersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_returnVouchersProvider),
      child: returns.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_return_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سندات مرتجع', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final v = ReturnVoucherModel.fromJson(list[i]);
              return _ReturnVoucherCard(
                voucher: v,
                onAction: () => ref.invalidate(_returnVouchersProvider),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: ${Helpers.friendlyError(e)}')),
      ),
    );
  }
}

class _ReturnVoucherCard extends ConsumerWidget {
  final ReturnVoucherModel voucher;
  final VoidCallback onAction;
  const _ReturnVoucherCard({required this.voucher, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPosted = voucher.status == 'posted';
    final statusColor = isPosted ? Colors.green : Colors.orange;
    final statusText = isPosted ? 'مُرحَّل' : 'مسودة';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_return_outlined, color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    voucher.voucherNumber ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                StatusBadge(text: statusText, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            if (voucher.originalVoucherNumber != null)
              Row(children: [
                const Icon(Icons.link_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'استرداد من سند: ${voucher.originalVoucherNumber}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ]),
            if (voucher.itemNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: voucher.itemNames
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.deepOrange.shade200,
                                width: 0.8),
                          ),
                          child: Text(name,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.deepOrange.shade800)),
                        ))
                    .toList(),
              ),
            ],
            if (voucher.reason?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'السبب: ${voucher.reason}',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  voucher.createdAt?.substring(0, 10) ?? '',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const Spacer(),
                Text('${voucher.itemCount} صنف', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            if (!isPosted) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                    icon: const Icon(Icons.assignment_return, size: 16, color: Colors.white),
                    label: const Text('ترحيل المرتجع', style: TextStyle(color: Colors.white)),
                    onPressed: () => _postReturn(context, ref),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _postReturn(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد ترحيل المرتجع'),
        content: const Text(
          'سيتم:\n'
          '• خصم الكميات من مخزن الخلطات\n'
          '• إعادتها للمخزن الرئيسي\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ترحيل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.postReturnVoucher(voucher.id!);
      ref.invalidate(inventorySummaryProvider); // مرتجع من الخلاط إلى الرئيسي — حدّث الكروت
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم ترحيل المرتجع وتحديث المخزون'), backgroundColor: Colors.deepOrange),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Return Voucher Dialog
// ══════════════════════════════════════════════════════════════════

class _ReturnVoucherDialog extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  const _ReturnVoucherDialog({required this.onSaved});

  @override
  ConsumerState<_ReturnVoucherDialog> createState() => _ReturnVoucherDialogState();
}

class _ReturnVoucherDialogState extends ConsumerState<_ReturnVoucherDialog> {
  final _reasonCtrl = TextEditingController();
  String? _selectedVoucherId;
  String? _selectedVoucherNumber;
  final _items = <_ReturnItemEntry>[];
  List<Map<String, dynamic>> _confirmedVouchers = [];
  List<VoucherItemModel> _originalItems = [];
  bool _loading = false;
  bool _loadingVouchers = true;

  @override
  void initState() {
    super.initState();
    _loadConfirmedVouchers();
  }

  Future<void> _loadConfirmedVouchers() async {
    try {
      final ds = ref.read(dataSourceProvider);
      final data = await ds.getTransferVouchers(status: 'confirmed');
      if (mounted) setState(() {
        _confirmedVouchers = data;
        _loadingVouchers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingVouchers = false);
    }
  }

  Future<void> _loadVoucherItems(String voucherId) async {
    try {
      final ds = ref.read(dataSourceProvider);
      final data = await ds.getTransferVoucher(voucherId);
      final v = TransferVoucherModel.fromJson(data);
      if (mounted) setState(() {
        _originalItems = v.items;
        _items.clear();
        for (final item in v.items) {
          _items.add(_ReturnItemEntry(
            materialId: item.materialId,
            materialName: item.materialName,
            unit: item.unit,
            maxQty: item.confirmedQty ?? item.requestedQty,
          ));
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedVoucherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر السند الأصلي'), backgroundColor: Colors.red),
      );
      return;
    }
    final activeItems = _items.where((e) => e.qty > 0).toList();
    if (activeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل كمية مرتجعة لمادة واحدة على الأقل'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.createReturnVoucher({
        'original_voucher_id': _selectedVoucherId,
        'reason': _reasonCtrl.text.trim(),
        'created_by': 'مشرف الخلطات',
        'items': activeItems
            .map((e) => {
                  if (e.materialId != null) 'material_id': e.materialId,
                  'material_name': e.materialName,
                  'unit': e.unit,
                  'requested_qty': e.qty,
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سند مرتجع جديد'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سند المرتجع يُعيد المواد من مخزن الخلطات للمخزن الرئيسي',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loadingVouchers)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<String>(
                  value: _selectedVoucherId,
                  decoration: const InputDecoration(
                    labelText: 'السند الأصلي المُؤكَّد',
                    prefixIcon: Icon(Icons.swap_horiz_outlined),
                  ),
                  items: _confirmedVouchers
                      .map((v) => DropdownMenuItem<String>(
                            value: v['id'] as String,
                            child: Text(v['voucher_number'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() => _selectedVoucherId = id);
                    _loadVoucherItems(id);
                  },
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              if (_items.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('الكميات المرتجعة', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(item.materialName, style: const TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'الكمية',
                                isDense: true,
                                suffixText: item.unit,
                                helperText: 'الحد: ${item.maxQty.toStringAsFixed(1)}',
                              ),
                              onChanged: (v) => item.qty = double.tryParse(v) ?? 0,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              if (_selectedVoucherId != null && _items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
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
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _ReturnItemEntry {
  final String? materialId;
  final String materialName;
  final String unit;
  final double maxQty;
  double qty = 0;

  _ReturnItemEntry({
    this.materialId,
    required this.materialName,
    required this.unit,
    required this.maxQty,
  });
}
