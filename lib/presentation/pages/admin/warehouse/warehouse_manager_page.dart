import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/voucher_models.dart';
import '../../../../data/models/inventory_summary_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../core/constants/app_constants.dart';

// ── Providers ────────────────────────────────────────────────────

final _receiptVouchersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getReceiptVouchers();
});

final _transferVouchersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getTransferVouchers();
});

final _summaryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getInventorySummary();
});

// ── Page ─────────────────────────────────────────────────────────

class WarehouseManagerPage extends ConsumerStatefulWidget {
  final String? keeperName;
  const WarehouseManagerPage({super.key, this.keeperName});

  @override
  ConsumerState<WarehouseManagerPage> createState() => _WarehouseManagerPageState();
}

class _WarehouseManagerPageState extends ConsumerState<WarehouseManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.download_outlined), text: 'سندات الاستلام'),
              Tab(icon: Icon(Icons.swap_horiz_outlined), text: 'سندات التحويل'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _ReceiptTab(),
                _TransferTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tabs.index == 0
            ? _showCreateReceiptDialog(context)
            : _showCreateTransferDialog(context),
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'سند استلام جديد' : 'سند تحويل جديد'),
      ),
    );
  }

  void _showCreateReceiptDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ReceiptVoucherDialog(
        keeperName: widget.keeperName,
        onSaved: () {
          ref.invalidate(_receiptVouchersProvider);
        },
      ),
    );
  }

  void _showCreateTransferDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => _TransferVoucherDialog(
        keeperName: widget.keeperName,
        onSaved: () {
          ref.invalidate(_transferVouchersProvider);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Receipt Tab
// ══════════════════════════════════════════════════════════════════

class _ReceiptTab extends ConsumerWidget {
  const _ReceiptTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(_receiptVouchersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_receiptVouchersProvider),
      child: vouchers.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سندات استلام', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) => _ReceiptVoucherCard(
              voucher: ReceiptVoucherModel.fromJson(list[i]),
              onAction: () => ref.invalidate(_receiptVouchersProvider),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: ${Helpers.friendlyError(e)}')),
      ),
    );
  }
}

class _ReceiptVoucherCard extends ConsumerWidget {
  final ReceiptVoucherModel voucher;
  final VoidCallback onAction;
  const _ReceiptVoucherCard({required this.voucher, required this.onAction});

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
                Icon(Icons.receipt_long_outlined, color: statusColor, size: 20),
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
            if (voucher.supplierName?.isNotEmpty == true)
              Row(children: [
                const Icon(Icons.business_outlined, size: 14, color: Colors.teal),
                const SizedBox(width: 4),
                Text(
                  'المورد: ${voucher.supplierName!}',
                  style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ]),
            if (voucher.supplierPhone?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(voucher.supplierPhone!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ]),
            ],
            if (voucher.supplierRef?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.receipt_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('رقم الفاتورة: ${voucher.supplierRef!}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ]),
            ],
            if (voucher.receivedBy?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.person_pin_outlined, size: 13, color: Colors.indigo),
                const SizedBox(width: 4),
                Text('استلمه: ${voucher.receivedBy!}', style: const TextStyle(color: Colors.indigo, fontSize: 12)),
              ]),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(voucher.date ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const Spacer(),
                Text('${voucher.itemCount} صنف', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            if (!isPosted) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('تعديل'),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => _ReceiptVoucherDialog(
                          voucherId: voucher.id,
                          onSaved: onAction,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                    label: const Text('ترحيل', style: TextStyle(color: Colors.white)),
                    onPressed: () => _postVoucher(context, ref),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _postVoucher(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الترحيل'),
        content: Text('سيتم إضافة مواد سند ${voucher.voucherNumber} للمخزن الرئيسي. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ترحيل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final ds = ref.read(dataSourceProvider);
      await ds.postReceiptVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم ترحيل السند وإضافة المواد للمخزن'), backgroundColor: Colors.green),
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
// Transfer Tab
// ══════════════════════════════════════════════════════════════════

class _TransferTab extends ConsumerWidget {
  const _TransferTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(_transferVouchersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_transferVouchersProvider),
      child: vouchers.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سندات تحويل', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) => TransferVoucherCard(
              voucher: TransferVoucherModel.fromJson(list[i]),
              onAction: () => ref.invalidate(_transferVouchersProvider),
              role: 'manager',
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: ${Helpers.friendlyError(e)}')),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Transfer Voucher Card (shared between manager & mixing pages)
// ══════════════════════════════════════════════════════════════════

class TransferVoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final VoidCallback onAction;
  final String role; // 'manager' | 'mixer'
  const TransferVoucherCard({
    required this.voucher,
    required this.onAction,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusText, statusColor) = _statusInfo(voucher.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz_outlined, color: statusColor, size: 20),
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
            if (voucher.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(voucher.notes!, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            ],
            if (voucher.isConfirmed && voucher.confirmedBy != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.verified_outlined, size: 13, color: Colors.green),
                const SizedBox(width: 4),
                Text('أُكِّد بواسطة: ${voucher.confirmedBy}',
                    style: const TextStyle(color: Colors.green, fontSize: 12)),
              ]),
            ],
            // Actions
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // View details
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('تفاصيل'),
                  onPressed: () => _showDetails(context, ref),
                ),
                if (role == 'manager') ...[
                  if (voucher.canEdit) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('تعديل'),
                      onPressed: () => showDialog(
                        context: context,
                        useSafeArea: false,
                        builder: (_) => _TransferVoucherDialog(
                          voucherId: voucher.id,
                          onSaved: onAction,
                        ),
                      ),
                    ),
                  ],
                  if (voucher.isDraft) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      icon: const Icon(Icons.send_outlined, size: 16, color: Colors.white),
                      label: const Text('إرسال', style: TextStyle(color: Colors.white)),
                      onPressed: () => _submitVoucher(context, ref),
                    ),
                  ],
                  if (voucher.isDraft || voucher.isPending) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('إلغاء'),
                      onPressed: () => _cancelVoucher(context, ref),
                    ),
                  ],
                ],
                if (role == 'mixer' && voucher.canConfirm) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                    label: const Text('تأكيد الاستلام', style: TextStyle(color: Colors.white)),
                    onPressed: () => _confirmVoucher(context, ref),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _statusInfo(String status) => switch (status) {
        'draft' => ('مسودة', Colors.grey),
        'pending' => ('قيد الانتظار', Colors.orange),
        'confirmed' => ('مُؤكَّد', Colors.green),
        'cancelled' => ('ملغى', Colors.red),
        _ => (status, Colors.grey),
      };

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    try {
      final ds = ref.read(dataSourceProvider);
      final data = await ds.getTransferVoucher(voucher.id!);
      final full = TransferVoucherModel.fromJson(data);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('سند تحويل — ${full.voucherNumber}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('البنود:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (full.items.isEmpty)
                  const Text('لا توجد بنود', style: TextStyle(color: Colors.grey))
                else
                  ...full.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.materialName, style: const TextStyle(fontSize: 13))),
                            Text(
                              Helpers.formatQuantityInKg(item.requestedQty, item.unit),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitVoucher(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال للتأكيد'),
        content: const Text('سيتم إرسال السند لمشرف الخلطات للتأكيد. لن يمكن حذفه بعد ذلك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.submitTransferVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال السند لمشرف الخلطات'), backgroundColor: Colors.blue),
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

  Future<void> _cancelVoucher(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء السند'),
        content: const Text('هل تريد إلغاء هذا السند نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، إلغاء', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.cancelTransferVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء السند'), backgroundColor: Colors.red),
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

  Future<void> _confirmVoucher(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد استلام المواد'),
        content: Text(
          'بتأكيد هذا السند سيتم:\n'
          '• خصم المواد من المخزن الرئيسي\n'
          '• إضافتها لمخزن الخلطات\n\n'
          'لا يمكن التراجع — أنشئ سند مرتجع للتسوية إن لزم.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الاستلام', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': 'مشرف الخلطات'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تأكيد الاستلام وتحديث المخزون'), backgroundColor: Colors.green),
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
// Receipt Voucher Dialog
// ══════════════════════════════════════════════════════════════════

class _ReceiptVoucherDialog extends ConsumerStatefulWidget {
  final String? voucherId;
  final String? keeperName;
  final VoidCallback onSaved;
  const _ReceiptVoucherDialog({this.voucherId, this.keeperName, required this.onSaved});

  @override
  ConsumerState<_ReceiptVoucherDialog> createState() => _ReceiptVoucherDialogState();
}

class _ReceiptVoucherDialogState extends ConsumerState<_ReceiptVoucherDialog> {
  final _supplierCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();
  final _supplierRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _items = <_ItemEntry>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.voucherId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final ds = ref.read(dataSourceProvider);
      final data = await ds.getReceiptVoucher(widget.voucherId!);
      final v = ReceiptVoucherModel.fromJson(data);
      _supplierCtrl.text = v.supplierName ?? '';
      _supplierPhoneCtrl.text = v.supplierPhone ?? '';
      _supplierRefCtrl.text = v.supplierRef ?? '';
      _notesCtrl.text = v.notes ?? '';
      for (final item in v.items) {
        _items.add(_ItemEntry()
          ..name = item.materialName
          ..qty = item.requestedQty
          ..unit = item.unit
          ..materialId = item.materialId);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    _supplierRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_ItemEntry()));
  void _removeItem(int idx) => setState(() => _items.removeAt(idx));

  Future<void> _save() async {
    if (_supplierCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم المورد مطلوب'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف بنداً واحداً على الأقل'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final keeperName = widget.keeperName ?? 'أمين المخزن';
      final data = {
        'supplier_name': _supplierCtrl.text.trim(),
        'supplier_phone': _supplierPhoneCtrl.text.trim(),
        'supplier_ref': _supplierRefCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'created_by': keeperName,
        'received_by': keeperName,
        'items': _items
            .where((e) => e.name.isNotEmpty && e.qty > 0)
            .map((e) => {
                  'material_name': e.name,
                  'unit': e.unit,
                  'requested_qty': e.qty,
                  if (e.materialId != null) 'material_id': e.materialId,
                })
            .toList(),
      };
      if (widget.voucherId != null) {
        await ds.updateReceiptVoucher(widget.voucherId!, data);
      } else {
        await ds.createReceiptVoucher(data);
      }
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
    final summaryAsync = ref.watch(_summaryProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == 'main')
            .toList() ??
        [];
    final keeperName = widget.keeperName ?? 'أمين المخزن';

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.download_outlined, color: Colors.teal),
        const SizedBox(width: 8),
        Text(widget.voucherId != null ? 'تعديل سند استلام' : 'سند استلام وارد جديد'),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── المستلِم (أمين المخزن) ──────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_pin_outlined, color: Colors.teal, size: 18),
                  const SizedBox(width: 8),
                  const Text('المستلِم: ', style: TextStyle(color: Colors.teal, fontSize: 13)),
                  Text(keeperName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 14),
              // ── بيانات المورد ────────────────────────────────
              const Text('بيانات المورد',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _supplierCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد *',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _supplierPhoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'هاتف المورد (اختياري)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _supplierRefCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم الفاتورة / المرجع (اختياري)',
                  prefixIcon: Icon(Icons.receipt_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('البنود', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('إضافة بند'),
                    onPressed: _addItem,
                  ),
                ],
              ),
              const Divider(),
              ..._items.asMap().entries.map((e) => _ItemRow(
                    index: e.key,
                    entry: e.value,
                    materials: materials,
                    onRemove: () => _removeItem(e.key),
                    onChanged: () => setState(() {}),
                  )),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: Text('اضغط "إضافة بند" لإضافة مادة', style: TextStyle(color: Colors.grey))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          onPressed: _loading ? null : _save,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('حفظ السند'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Transfer Voucher Dialog
// ══════════════════════════════════════════════════════════════════

class _TransferVoucherDialog extends ConsumerStatefulWidget {
  final String? voucherId;
  final String? keeperName;
  final VoidCallback onSaved;
  const _TransferVoucherDialog({this.voucherId, this.keeperName, required this.onSaved});

  @override
  ConsumerState<_TransferVoucherDialog> createState() => _TransferVoucherDialogState();
}

class _TransferVoucherDialogState extends ConsumerState<_TransferVoucherDialog> {
  final _notesCtrl = TextEditingController();
  final _items = <_ItemEntry>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.voucherId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final ds = ref.read(dataSourceProvider);
      final data = await ds.getTransferVoucher(widget.voucherId!);
      final v = TransferVoucherModel.fromJson(data);
      _notesCtrl.text = v.notes ?? '';
      for (final item in v.items) {
        _items.add(_ItemEntry()
          ..name = item.materialName
          ..qty = item.requestedQty
          ..unit = item.unit
          ..materialId = item.materialId);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_ItemEntry()));
  void _removeItem(int idx) => setState(() => _items.removeAt(idx));

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف بنداً واحداً على الأقل'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final itemsList = _items
          .where((e) => e.name.isNotEmpty && e.qty > 0)
          .map((e) => {
                'material_name': e.name,
                'unit': e.unit,
                'requested_qty': e.qty,
                if (e.materialId != null) 'material_id': e.materialId,
              })
          .toList();

      if (widget.voucherId != null) {
        await ds.updateTransferVoucher(widget.voucherId!, {
          'notes': _notesCtrl.text.trim(),
          'items': itemsList,
        });
      } else {
        await ds.createTransferVoucher({
          'notes': _notesCtrl.text.trim(),
          'created_by': widget.keeperName ?? 'أمين المخزن',
          'items': itemsList,
        });
      }
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
    final summaryAsync = ref.watch(_summaryProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == 'main')
            .toList() ??
        [];

    return AlertDialog(
      title: Text(widget.voucherId != null ? 'تعديل سند تحويل' : 'سند تحويل جديد'),
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
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المخزن الرئيسي ← مخزن الخلطات',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
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
                  const Text('المواد المحوَّلة', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('إضافة بند'),
                    onPressed: _addItem,
                  ),
                ],
              ),
              const Divider(),
              ..._items.asMap().entries.map((e) => _ItemRow(
                    index: e.key,
                    entry: e.value,
                    materials: materials,
                    onRemove: () => _removeItem(e.key),
                    onChanged: () => setState(() {}),
                  )),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: Text('اضغط "إضافة بند" لإضافة مادة', style: TextStyle(color: Colors.grey))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: _loading ? null : _save,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
        ),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────

class _ItemEntry {
  String name = '';
  String unit = 'كجم';
  double qty = 0;
  String? materialId;
}

class _ItemRow extends StatelessWidget {
  final int index;
  final _ItemEntry entry;
  final List<InventorySummaryModel> materials;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _ItemRow({
    required this.index,
    required this.entry,
    required this.materials,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Autocomplete<InventorySummaryModel>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return materials;
                return materials
                    .where((m) => m.materialName.contains(textEditingValue.text))
                    .toList();
              },
              displayStringForOption: (m) => m.materialName,
              fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                if (entry.name.isNotEmpty && ctrl.text.isEmpty) ctrl.text = entry.name;
                return TextFormField(
                  controller: ctrl,
                  focusNode: fn,
                  decoration: const InputDecoration(
                    labelText: 'اسم المادة',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    entry.name = v;
                    onChanged();
                  },
                );
              },
              onSelected: (m) {
                entry.name = m.materialName;
                entry.unit = m.unit;
                entry.materialId = m.materialId;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: entry.qty > 0 ? entry.qty.toString() : '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'الكمية',
                suffixText: entry.unit,
                isDense: true,
              ),
              onChanged: (v) {
                entry.qty = double.tryParse(v) ?? 0;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<String>(
              value: entry.unit,
              decoration: const InputDecoration(isDense: true, labelText: 'وحدة'),
              items: AppConstants.units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) {
                if (v != null) entry.unit = v;
                onChanged();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
