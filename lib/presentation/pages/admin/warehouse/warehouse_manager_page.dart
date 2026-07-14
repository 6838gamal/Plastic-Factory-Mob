import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/voucher_models.dart';
import '../../../../data/models/inventory_summary_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/reference_data_provider.dart'
    show inventorySummaryProvider, allRawMaterialsAsSummaryProvider;
import '../../../../core/utils/helpers.dart';
import '../../../../core/constants/app_constants.dart';
import '../suppliers/suppliers_page.dart';

// ── Providers ────────────────────────────────────────────────────

final _receiptVouchersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getReceiptVouchers();
});

final transferVouchersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getTransferVouchers();
});

final _approvedReceiptsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getReceiptVouchers(status: 'approved');
});

// ملخص المخزون: يُستخدم inventorySummaryProvider المشترك من reference_data_provider.dart

final _suppliersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(dataSourceProvider).getSuppliers();
});

final _withdrawalVouchersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(dataSourceProvider).getWithdrawalVouchers();
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
    // Keepers see 4 tabs (+ incoming receipt); admins see 3 (transfers live in mixing-warehouse)
    _tabs = TabController(length: widget.keeperName == null ? 3 : 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKeeper = widget.keeperName != null;
    // Admin: 3 tabs (Receipts, Withdrawals, Suppliers) — transfers live in mixing-warehouse page
    // Keeper: 4 tabs (استلام وارد, Receipts, Withdrawals, Suppliers)
    final suppliersIndex = isKeeper ? 3 : 2;

    final tabs = isKeeper
        ? const [
            Tab(icon: Icon(Icons.inbox_outlined), text: 'استلام وارد'),
            Tab(icon: Icon(Icons.download_outlined), text: 'سندات الاستلام'),
            Tab(icon: Icon(Icons.remove_circle_outline), text: 'سندات السحب'),
            Tab(icon: Icon(Icons.business_outlined), text: 'الموردون'),
          ]
        : const [
            Tab(icon: Icon(Icons.download_outlined), text: 'سندات الاستلام'),
            Tab(icon: Icon(Icons.remove_circle_outline), text: 'سندات السحب'),
            Tab(icon: Icon(Icons.business_outlined), text: 'الموردون'),
          ];

    final tabViews = isKeeper
        ? <Widget>[
            _IncomingReceiptTab(keeperName: widget.keeperName),
            _ReceiptTab(isAdmin: false, keeperName: widget.keeperName),
            _WithdrawalTab(isAdmin: false, keeperName: widget.keeperName),
            const SuppliersPage(),
          ]
        : <Widget>[
            const _ReceiptTab(isAdmin: true),
            _WithdrawalTab(isAdmin: true, keeperName: null),
            const SuppliersPage(),
          ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ColoredBox(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: tabs,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: TabBarView(controller: _tabs, children: tabViews),
            ),
          ),
        ],
      ),
      // Hide FAB on: suppliers tab (both roles), incoming-receipt tab (keeper tab 0)
      floatingActionButton: (_tabs.index == suppliersIndex || (isKeeper && _tabs.index == 0))
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                // Keeper: tab 0=incoming(no FAB handled above), 1=receipts, 2=withdrawals, 3=suppliers
              // Admin:  tab 0=receipts, 1=withdrawals, 2=suppliers
              if (isKeeper) {
                if (_tabs.index == 1) _showCreateReceiptDialog(context);
                else _showCreateWithdrawalDialog(context);
              } else {
                if (_tabs.index == 0) _showCreateReceiptDialog(context);
                else _showCreateWithdrawalDialog(context);
              }
            },
            icon: const Icon(Icons.add),
            label: Text(() {
              if (isKeeper) return _tabs.index == 1 ? 'سند استلام جديد' : 'سند سحب جديد';
              return _tabs.index == 0 ? 'سند استلام جديد' : 'سند سحب جديد';
            }()),
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
          // For keeper: switch to "سندات الاستلام" tab (index 1) so the new draft is visible
          if (widget.keeperName != null) {
            _tabs.animateTo(1);
          }
        },
      ),
    );
  }

  void _showCreateTransferDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => TransferVoucherDialog(
        keeperName: widget.keeperName,
        onSaved: () {
          ref.invalidate(transferVouchersProvider);
        },
      ),
    );
  }

  void _showCreateWithdrawalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _WithdrawalVoucherDialog(
        keeperName: widget.keeperName,
        onSaved: () {
          ref.invalidate(_withdrawalVouchersProvider);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Receipt Tab
// ══════════════════════════════════════════════════════════════════

class _ReceiptTab extends ConsumerWidget {
  final bool isAdmin;
  final String? keeperName;
  const _ReceiptTab({required this.isAdmin, this.keeperName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(_receiptVouchersProvider);

    return vouchers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: ${Helpers.friendlyError(e)}')),
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

          // Admin: pending_approval first, then approved, then rest
          final sorted = isAdmin
              ? [
                  ...list.where((v) => v['status'] == 'pending_approval'),
                  ...list.where((v) => v['status'] == 'approved'),
                  ...list.where((v) =>
                      v['status'] != 'pending_approval' &&
                      v['status'] != 'approved'),
                ]
              : list;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_receiptVouchersProvider),
            child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              try {
                return _ReceiptVoucherCard(
                  voucher: ReceiptVoucherModel.fromJson(sorted[i]),
                  isAdmin: isAdmin,
                  keeperName: keeperName,
                  onAction: () => ref.invalidate(_receiptVouchersProvider),
                );
              } catch (e, st) {
                debugPrint('_ReceiptTab parse error at index $i: $e\n$st');
                return Card(
                  color: Colors.red.shade50,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'تعذّر عرض هذا السند',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Incoming Receipt Tab (keeper) — shows approved vouchers ready to post
// ══════════════════════════════════════════════════════════════════

class _IncomingReceiptTab extends ConsumerWidget {
  final String? keeperName;
  const _IncomingReceiptTab({this.keeperName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(_approvedReceiptsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_approvedReceiptsProvider),
      child: vouchers.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سندات بانتظار الاستلام',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                  SizedBox(height: 6),
                  Text(
                    'عندما تُوافق الإدارة على سند استلام\nسيظهر هنا لتقوم بترحيله للمخزن',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // ── Banner ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.white,
                child: Row(
                  children: [
                    const Icon(Icons.info_outlined, size: 16, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'هذه السندات وافقت عليها الإدارة — اضغط "ترحيل للمخزن" لإضافة المواد للمخزن الرئيسي',
                        style: TextStyle(color: Colors.teal.shade800, fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${list.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ── List ────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    try {
                      return _ReceiptVoucherCard(
                        voucher: ReceiptVoucherModel.fromJson(list[i]),
                        isAdmin: false,
                        keeperName: keeperName,
                        onAction: () => ref.invalidate(_approvedReceiptsProvider),
                      );
                    } catch (e, st) {
                      debugPrint('_IncomingReceiptTab parse error at index $i: $e\n$st');
                      return Card(
                        color: Colors.red.shade50,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'تعذّر عرض هذا السند',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      );
                    }
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

// ── Status helpers ────────────────────────────────────────────────

Color _receiptStatusColor(String? status) {
  switch (status) {
    case 'posted':           return Colors.green;
    case 'approved':         return Colors.teal;
    case 'pending_approval': return Colors.indigo;
    case 'rejected':         return Colors.red;
    default:                 return Colors.orange;
  }
}

String _receiptStatusText(String? status) {
  switch (status) {
    case 'posted':           return 'مُرحَّل';
    case 'approved':         return 'مقبول — بانتظار الاستلام';
    case 'pending_approval': return 'بانتظار الموافقة';
    case 'rejected':         return 'مرفوض';
    default:                 return 'مسودة';
  }
}

// ── Card ──────────────────────────────────────────────────────────

class _ReceiptVoucherCard extends ConsumerWidget {
  final ReceiptVoucherModel voucher;
  final bool isAdmin;
  final String? keeperName;
  final VoidCallback onAction;
  const _ReceiptVoucherCard({
    required this.voucher,
    required this.isAdmin,
    this.keeperName,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = voucher.status ?? 'draft';
    final statusColor = _receiptStatusColor(status);
    final statusText = _receiptStatusText(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────
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

            // ── Supplier info ────────────────────────────────────
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

            // ── Items as chips (name + qty) ───────────────────────
            if (voucher.items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: voucher.items.map((item) {
                  final qty = item.requestedQty % 1 == 0
                      ? item.requestedQty.toInt().toString()
                      : item.requestedQty.toString();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 0.8),
                    ),
                    child: Text(
                      '${item.materialName}  $qty ${item.unit}',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                    ),
                  );
                }).toList(),
              ),
            ] else if (voucher.itemNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: voucher.itemNames
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200, width: 0.8),
                          ),
                          child: Text(name,
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                        ))
                    .toList(),
              ),
            ],

            // ── Date / count ─────────────────────────────────────
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

            const SizedBox(height: 10),
            // ── Action buttons (role + status aware) ─────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // audit trail — always visible
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[500],
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.history_outlined, size: 13),
                  label: const Text('سجل', style: TextStyle(fontSize: 11)),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _ReceiptAuditDialog(voucher: voucher),
                  ),
                ),
                const Spacer(),
                // ── Admin: pending_approval ──────────────────────
                if (isAdmin && status == 'pending_approval') ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('رفض', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                    onPressed: () => _rejectVoucher(context, ref),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('قبول', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white),
                    onPressed: () => _approveVoucher(context, ref),
                  ),
                ],
                // ── Admin: approved → edit quantities + post ─────
                if (isAdmin && status == 'approved') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('تعديل الكميات',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _ReceiptVoucherDialog(
                        voucherId: voucher.id,
                        onSaved: onAction,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.warehouse_outlined, size: 14),
                    label: const Text('ترحيل للمخزن',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                    onPressed: () => _postVoucher(context, ref),
                  ),
                ],
                // ── Keeper: draft ────────────────────────────────
                if (!isAdmin && status == 'draft') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _ReceiptVoucherDialog(
                        voucherId: voucher.id,
                        keeperName: keeperName,
                        onSaved: onAction,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.send_outlined, size: 14),
                    label: const Text('إرسال للإدارة',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo),
                    onPressed: () => _submitVoucher(context, ref),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: Colors.red),
                    label: const Text('حذف',
                        style:
                            TextStyle(fontSize: 12, color: Colors.red)),
                    onPressed: () => _deleteVoucher(context, ref),
                  ),
                ],
                // ── Keeper: pending ──────────────────────────────
                if (!isAdmin && status == 'pending_approval')
                  const Text('بانتظار موافقة الإدارة',
                      style:
                          TextStyle(fontSize: 12, color: Colors.orange)),
                // ── Keeper: approved → post ──────────────────────
                if (!isAdmin && status == 'approved') ...[
                  Text('مقبول ✓',
                      style: TextStyle(
                          fontSize: 12, color: Colors.teal.shade700)),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.warehouse_outlined, size: 14),
                    label: const Text('ترحيل للمخزن',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact),
                    onPressed: () => _postVoucher(context, ref),
                  ),
                ],
                // ── Keeper: rejected → delete ────────────────────
                if (!isAdmin && status == 'rejected')
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: Colors.red),
                    label: const Text('حذف',
                        style:
                            TextStyle(fontSize: 12, color: Colors.red)),
                    onPressed: () => _deleteVoucher(context, ref),
                  ),
                // ── Admin: can delete any voucher, including posted ──
                // (deleting a posted voucher reverses its inventory effect
                // on the server so the main-warehouse balance stays correct)
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                    label: const Text('حذف', style: TextStyle(fontSize: 12, color: Colors.red)),
                    onPressed: () => _deleteVoucher(context, ref, isPosted: status == 'posted'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _submitVoucher(BuildContext context, WidgetRef ref) async {
    if (voucher.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الإرسال: السند غير مكتمل'), backgroundColor: Colors.red),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال للإدارة'),
        content: Text('سيُرسل السند ${voucher.voucherNumber} للإدارة لمراجعته والموافقة عليه.\nلن تتمكن من التعديل بعد الإرسال.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final name = keeperName ?? 'أمين المخزن';
      await ref.read(dataSourceProvider).submitReceiptVoucher(voucher.id!, submittedBy: name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال السند للإدارة بنجاح'), backgroundColor: Colors.indigo),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _approveVoucher(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قبول السند'),
        content: Text(
          'سيُقبل السند ${voucher.voucherNumber} ويظهر في قائمة الاستلام بالمخزن الرئيسي.\n'
          'يمكنك تعديل الكميات ثم الترحيل للمخزن لاحقاً.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('قبول', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).approveReceiptVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم قبول السند — يظهر الآن في قائمة الاستلام للمخزن الرئيسي'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _postVoucher(BuildContext context, WidgetRef ref) async {
    if (voucher.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الترحيل: السند غير مكتمل'), backgroundColor: Colors.red),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ترحيل للمخزن'),
        content: Text(
          'سيُضاف محتوى السند ${voucher.voucherNumber} للمخزن الرئيسي بالكميات المحددة.\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ترحيل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final name = isAdmin ? (keeperName ?? 'المدير') : (keeperName ?? 'أمين المخزن');
      await ref.read(dataSourceProvider).postReceiptVoucher(voucher.id!, performedBy: name);
      ref.invalidate(inventorySummaryProvider); // السند أضاف كمية للمخزن الرئيسي — حدّث الكروت
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم ترحيل السند للمخزن الرئيسي بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Helpers.friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectVoucher(BuildContext context, WidgetRef ref) async {
    if (voucher.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض السند'),
        content: Text('هل تريد رفض السند ${voucher.voucherNumber}؟ لن تُضاف أي مواد للمخزن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).rejectReceiptVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض السند'), backgroundColor: Colors.red),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Helpers.friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteVoucher(BuildContext context, WidgetRef ref,
      {bool isPosted = false}) async {
    if (voucher.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السند'),
        content: Text(isPosted
            ? 'السند ${voucher.voucherNumber} مُرحَّل بالفعل وأثّر على رصيد المخزن الرئيسي.\n'
                'حذفه سيعكس الكميات التي أضافها (خصمها من الرصيد الحالي) نهائياً. هل أنت متأكد؟'
            : 'سيُحذف السند ${voucher.voucherNumber} نهائياً. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).deleteReceiptVoucher(voucher.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف السند'), backgroundColor: Colors.grey),
        );
      }
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Helpers.friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Receipt Audit Trail Dialog
// ══════════════════════════════════════════════════════════════════

class _ReceiptAuditDialog extends StatelessWidget {
  final ReceiptVoucherModel voucher;
  const _ReceiptAuditDialog({required this.voucher});

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = <_AuditEvent>[
      _AuditEvent(
        icon: Icons.add_circle_outline,
        color: Colors.blue,
        title: 'إنشاء السند',
        by: voucher.createdBy,
        at: voucher.createdAt,
        done: true,
      ),
      _AuditEvent(
        icon: Icons.send_outlined,
        color: Colors.indigo,
        title: 'إرسال للإدارة',
        by: voucher.submittedBy,
        at: voucher.submittedAt,
        done: voucher.submittedAt != null,
      ),
      _AuditEvent(
        icon: Icons.check_circle_outline,
        color: Colors.teal,
        title: 'قبول الإدارة',
        by: voucher.approvedBy,
        at: voucher.approvedAt,
        done: voucher.approvedAt != null,
      ),
      _AuditEvent(
        icon: Icons.warehouse_outlined,
        color: Colors.green,
        title: 'ترحيل للمخزن الرئيسي',
        by: voucher.postedBy,
        at: voucher.postedAt,
        done: voucher.postedAt != null,
      ),
    ];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history_outlined, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Text('سجل التدقيق — ${voucher.voucherNumber ?? ""}',
              style: const TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < events.length; i++) ...[
              _buildStep(events[i], _fmt),
              if (i < events.length - 1)
                Padding(
                  padding: const EdgeInsets.only(right: 15),
                  child: Container(
                    width: 2,
                    height: 16,
                    color: i < events.indexWhere((e) => !e.done)
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Widget _buildStep(_AuditEvent e, String Function(String?) fmt) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: e.done ? e.color : Colors.grey.shade300,
              child: Icon(e.icon, size: 14,
                  color: e.done ? Colors.white : Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: e.done ? Colors.black87 : Colors.grey,
                    )),
                if (e.done) ...[
                  if (e.by?.isNotEmpty == true)
                    Text('بواسطة: ${e.by}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  if (e.at?.isNotEmpty == true)
                    Text(fmt(e.at),
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ] else
                  Text('لم يتم بعد',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditEvent {
  final IconData icon;
  final Color color;
  final String title;
  final String? by;
  final String? at;
  final bool done;
  const _AuditEvent({
    required this.icon,
    required this.color,
    required this.title,
    this.by,
    this.at,
    required this.done,
  });
}

// ══════════════════════════════════════════════════════════════════
// Transfer Tab
// ══════════════════════════════════════════════════════════════════

class TransferTab extends ConsumerWidget {
  const TransferTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(transferVouchersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(transferVouchersProvider),
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
              onAction: () => ref.invalidate(transferVouchersProvider),
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
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.blue.shade200, width: 0.8),
                          ),
                          child: Text(name,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade800)),
                        ))
                    .toList(),
              ),
            ],
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
                        builder: (_) => TransferVoucherDialog(
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
        builder: (ctx) => AlertDialog(
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
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
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال للتأكيد'),
        content: const Text('سيتم إرسال السند لمشرف الخلطات للتأكيد. لن يمكن حذفه بعد ذلك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(ctx, true),
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
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء السند'),
        content: const Text('هل تريد إلغاء هذا السند نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
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
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد استلام المواد'),
        content: Text(
          'بتأكيد هذا السند سيتم:\n'
          '• خصم المواد من المخزن الرئيسي\n'
          '• إضافتها لمخزن الخلطات\n\n'
          'لا يمكن التراجع — أنشئ سند مرتجع للتسوية إن لزم.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الاستلام', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': 'مشرف الخلطات'});
      ref.invalidate(inventorySummaryProvider); // نقل كمية من الرئيسي إلى الخلاط — حدّث الكروت في كل الشاشات
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
  String? _selectedSupplierName;
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
      _selectedSupplierName = v.supplierName;
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
    _supplierPhoneCtrl.dispose();
    _supplierRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_ItemEntry()));
  void _removeItem(int idx) => setState(() => _items.removeAt(idx));

  Future<void> _save() async {
    if (_selectedSupplierName == null || _selectedSupplierName!.trim().isEmpty) {
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
    final incompleteIndexes = <int>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.isEmpty || _items[i].qty <= 0) i + 1,
    ];
    if (incompleteIndexes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أكمل بيانات البند رقم ${incompleteIndexes.join('، ')} (اختر المادة وأدخل كمية أكبر من صفر) قبل الحفظ',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final keeperName = widget.keeperName ?? 'أمين المخزن';
      final data = {
        'supplier_name': _selectedSupplierName ?? '',
        'supplier_phone': _supplierPhoneCtrl.text.trim(),
        'supplier_ref': _supplierRefCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'created_by': keeperName,
        'received_by': keeperName,
        'items': _items
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
    // allRawMaterialsAsSummaryProvider: يشمل كل المواد الخام النشطة (حتى غير المستلمة بعد)
    // حتى تظهر المواد المضافة حديثاً في قائمة البنود فوراً دون انتظار أول استلام لها.
    final summaryAsync = ref.watch(allRawMaterialsAsSummaryProvider);
    final suppliersAsync = ref.watch(_suppliersProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == 'main')
            .toList() ??
        [];
    final suppliers = suppliersAsync.valueOrNull ?? [];
    final keeperName = widget.keeperName ?? 'أمين المخزن';
    final matsLoading = summaryAsync.isLoading;

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
              DropdownButtonFormField<String>(
                value: suppliers.any((s) => s['name'] == _selectedSupplierName)
                    ? _selectedSupplierName
                    : (_selectedSupplierName != null && _selectedSupplierName!.isNotEmpty
                        ? _selectedSupplierName
                        : null),
                decoration: const InputDecoration(
                  labelText: 'اسم المورد *',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
                hint: const Text('اختر المورد'),
                items: [
                  ...suppliers.map((s) {
                    final name = s['name'] as String? ?? '';
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    );
                  }),
                  // Keep existing name as option if not in current suppliers list
                  if (_selectedSupplierName != null &&
                      _selectedSupplierName!.isNotEmpty &&
                      !suppliers.any((s) => s['name'] == _selectedSupplierName))
                    DropdownMenuItem<String>(
                      value: _selectedSupplierName!,
                      child: Text(_selectedSupplierName!, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _selectedSupplierName = v;
                    final found = suppliers.where((s) => s['name'] == v).firstOrNull;
                    if (found != null && (found['phone'] as String?)?.isNotEmpty == true) {
                      _supplierPhoneCtrl.text = found['phone'] as String;
                    }
                  });
                },
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
              if (matsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ..._items.asMap().entries.map((e) => _ItemRow(
                      index: e.key,
                      entry: e.value,
                      materials: materials,
                      onRemove: () => _removeItem(e.key),
                      onChanged: () => setState(() {}),
                      allowNewMaterial: true,
                    )),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: Text('اضغط "إضافة بند" لإضافة مادة', style: TextStyle(color: Colors.grey))),
                  ),
              ],
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

class TransferVoucherDialog extends ConsumerStatefulWidget {
  final String? voucherId;
  final String? keeperName;
  final VoidCallback onSaved;
  const TransferVoucherDialog({this.voucherId, this.keeperName, required this.onSaved});

  @override
  ConsumerState<TransferVoucherDialog> createState() => _TransferVoucherDialogState();
}

class _TransferVoucherDialogState extends ConsumerState<TransferVoucherDialog> {
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
    final incompleteIndexes = <int>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.isEmpty || _items[i].qty <= 0) i + 1,
    ];
    if (incompleteIndexes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أكمل بيانات البند رقم ${incompleteIndexes.join('، ')} (اختر المادة وأدخل كمية أكبر من صفر) قبل الحفظ',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final itemsList = _items
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
    final summaryAsync = ref.watch(inventorySummaryProvider);
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
  double availableQty = 0;
  // مادة جديدة كتبها أمين المخزن يدوياً (غير موجودة بعد في راw_materials).
  // لا تُنشأ في قاعدة البيانات إلا بعد قبول وترحيل سند التوريد إلى المخزن
  // الرئيسي — قبل ذلك لا تظهر في أي شاشة أخرى (بما فيها إدخال الطبخات).
  bool isNew = false;
}

class _ItemRow extends StatelessWidget {
  final int index;
  final _ItemEntry entry;
  final List<InventorySummaryModel> materials;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  // عند true تتم إتاحة خيار "مادة جديدة" لكتابة اسم مادة غير موجودة بعد —
  // يُستخدم فقط في سند الاستلام (توريد) وليس التحويل أو الصرف، حيث لا معنى
  // لصرف أو تحويل مادة غير موجودة أصلاً في المخزون.
  final bool allowNewMaterial;
  const _ItemRow({
    required this.index,
    required this.entry,
    required this.materials,
    required this.onRemove,
    required this.onChanged,
    this.allowNewMaterial = false,
  });

  @override
  Widget build(BuildContext context) {
    final itemNo = index + 1;
    final selected = entry.name.isNotEmpty
        ? materials
            .where((m) =>
                (entry.materialId != null && entry.materialId!.isNotEmpty)
                    ? m.materialId == entry.materialId
                    : m.materialName == entry.name)
            .firstOrNull
        : null;
    final availableQty = selected?.currentBalance ?? entry.availableQty;
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
          // ── Header: item number + remove ─────────────────────
          Row(
            children: [
              Text(
                'البند $itemNo',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
              ),
              const Spacer(),
              InkWell(
                onTap: onRemove,
                child: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (allowNewMaterial)
            InkWell(
              onTap: () {
                entry.isNew = !entry.isNew;
                entry.name = '';
                entry.materialId = null;
                entry.availableQty = 0;
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      entry.isNew ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 6),
                    const Text('مادة جديدة غير موجودة بالقائمة',
                        style: TextStyle(fontSize: 12.5, color: Colors.indigo)),
                  ],
                ),
              ),
            ),
          // ── Material dropdown (full width) — أو حقل اسم مادة جديدة ──
          if (entry.isNew) ...[
            TextFormField(
              key: ValueKey('newmat_name_$index'),
              initialValue: entry.name,
              decoration: const InputDecoration(
                labelText: 'اسم المادة الجديدة *',
                prefixIcon: Icon(Icons.new_label_outlined, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
                helperText: 'ستُضاف إلى قائمة المواد الخام تلقائياً عند قبول وترحيل السند',
                helperMaxLines: 2,
              ),
              onChanged: (v) {
                entry.name = v;
                entry.materialId = null;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: entry.unit,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'الوحدة',
                border: OutlineInputBorder(),
              ),
              items: AppConstants.units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) {
                if (v != null) entry.unit = v;
                onChanged();
              },
            ),
          ] else ...[
            DropdownButtonFormField<InventorySummaryModel>(
              value: selected,
              decoration: const InputDecoration(
                labelText: 'اسم المادة *',
                prefixIcon: Icon(Icons.science_outlined, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              hint: const Text('اختر المادة', style: TextStyle(fontSize: 13)),
              isExpanded: true,
              items: materials
                  .map((m) => DropdownMenuItem<InventorySummaryModel>(
                        value: m,
                        child: Text(
                          '${m.materialName}  —  متوفر: ${Helpers.formatQuantityInKg(m.currentBalance, m.unit)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ))
                  .toList(),
              onChanged: (m) {
                if (m != null) {
                  entry.name = m.materialName;
                  entry.unit = m.unit;
                  entry.materialId = m.materialId;
                  entry.availableQty = m.currentBalance;
                  onChanged();
                }
              },
            ),
          ],
          if (!entry.isNew && selected != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'المتوفر حالياً: ${Helpers.formatQuantityInKg(availableQty, entry.unit)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: availableQty > 0
                      ? () {
                          entry.qty = availableQty;
                          onChanged();
                        }
                      : null,
                  child: Text(
                    'استخدام القيمة المتوفرة',
                    style: TextStyle(
                      color: availableQty > 0 ? Colors.teal : Colors.grey.shade400,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // ── Qty + Unit side by side ──────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey('qty_${entry.materialId}_${entry.qty}'),
                  initialValue: entry.qty > 0 ? entry.qty.toString() : '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الكمية *',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.scale_outlined, size: 18),
                  ),
                  onChanged: (v) {
                    entry.qty = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: entry.unit,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'الوحدة',
                    border: OutlineInputBorder(),
                  ),
                  items: AppConstants.units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) entry.unit = v;
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

// ══════════════════════════════════════════════════════════════════
// Withdrawal Tab
// ══════════════════════════════════════════════════════════════════

class _WithdrawalTab extends ConsumerWidget {
  final bool isAdmin;
  final String? keeperName;
  const _WithdrawalTab({required this.isAdmin, this.keeperName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchersAsync = ref.watch(_withdrawalVouchersProvider);

    return vouchersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (vouchers) {
        if (vouchers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.remove_circle_outline, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد سندات سحب', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_withdrawalVouchersProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vouchers.length,
            itemBuilder: (ctx, i) {
              final v = WithdrawalVoucherModel.fromJson(vouchers[i]);
              return _WithdrawalVoucherCard(
                voucher: v,
                isAdmin: isAdmin,
                keeperName: keeperName,
                onAction: () => ref.invalidate(_withdrawalVouchersProvider),
              );
            },
          ),
        );
      },
    );
  }
}

class _WithdrawalVoucherCard extends ConsumerWidget {
  final WithdrawalVoucherModel voucher;
  final bool isAdmin;
  final String? keeperName;
  final VoidCallback onAction;

  const _WithdrawalVoucherCard({
    required this.voucher,
    required this.isAdmin,
    this.keeperName,
    required this.onAction,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'pending_approval': return Colors.orange;
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.blueGrey;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'draft': return 'مسودة';
      case 'pending_approval': return 'بانتظار الموافقة';
      case 'approved': return 'معتمد';
      case 'rejected': return 'مرفوض';
      default: return s;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(voucher.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.remove_circle_outline, color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Text(voucher.voucherNumber ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                StatusBadge(text: _statusLabel(voucher.status), color: color),
              ],
            ),
            const Divider(height: 14),
            if (voucher.purpose?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(child: Text(voucher.purpose!, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            if (voucher.itemNames.isNotEmpty) ...[
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
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                const Icon(Icons.list_alt, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text('${voucher.itemCount} بند', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(width: 16),
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(voucher.createdBy ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // ── Admin actions ───────────────────────────────
                if (isAdmin && voucher.isPending) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('رفض', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    onPressed: () => _reject(context, ref),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('اعتماد', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _approve(context, ref),
                  ),
                ],
                // ── Admin: delete any non-approved voucher ──────
                if (isAdmin && voucher.status != 'approved') ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                    label: const Text('حذف', style: TextStyle(fontSize: 12, color: Colors.red)),
                    onPressed: () => _delete(context, ref),
                  ),
                ],
                // ── Keeper actions ──────────────────────────────
                if (!isAdmin) ...[
                  if (voucher.isDraft) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _WithdrawalVoucherDialog(
                          voucherId: voucher.id,
                          keeperName: keeperName,
                          onSaved: onAction,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.send_outlined, size: 14),
                      label: const Text('إرسال للاعتماد', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                      onPressed: () => _submit(context, ref),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                      label: const Text('حذف', style: TextStyle(fontSize: 12, color: Colors.red)),
                      onPressed: () => _delete(context, ref),
                    ),
                  ],
                  if (voucher.isPending)
                    const Text('بانتظار موافقة الإدارة',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  if (voucher.isRejected)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                      label: const Text('حذف', style: TextStyle(fontSize: 12, color: Colors.red)),
                      onPressed: () => _delete(context, ref),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإرسال'),
        content: const Text('هل تريد إرسال سند السحب للاعتماد؟ لن تتمكن من تعديله بعد الإرسال.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ds = ref.read(dataSourceProvider);
      final name = keeperName ?? 'أمين المخزن';
      await ds.submitWithdrawalVoucher(voucher.id!, submittedBy: name);
      onAction();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال السند للاعتماد'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاعتماد'),
        content: Text('اعتماد سند السحب ${voucher.voucherNumber}؟\nسيتم خصم الكميات من المخزن الرئيسي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).approveWithdrawalVoucher(voucher.id!);
      ref.invalidate(inventorySummaryProvider); // خصم من المخزن الرئيسي — حدّث الكروت
      onAction();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد سند السحب وخصم الكميات'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض السند'),
        content: Text('رفض سند السحب ${voucher.voucherNumber}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).rejectWithdrawalVoucher(voucher.id!);
      onAction();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض السند'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السند'),
        content: const Text('هل أنت متأكد من حذف سند السحب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataSourceProvider).deleteWithdrawalVoucher(voucher.id!);
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
// Withdrawal Voucher Dialog
// ══════════════════════════════════════════════════════════════════

class _WithdrawalVoucherDialog extends ConsumerStatefulWidget {
  final String? voucherId;
  final String? keeperName;
  final VoidCallback onSaved;
  const _WithdrawalVoucherDialog({this.voucherId, this.keeperName, required this.onSaved});

  @override
  ConsumerState<_WithdrawalVoucherDialog> createState() => _WithdrawalVoucherDialogState();
}

class _WithdrawalVoucherDialogState extends ConsumerState<_WithdrawalVoucherDialog> {
  final _purposeCtrl = TextEditingController();
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
      final data = await ref.read(dataSourceProvider).getWithdrawalVoucher(widget.voucherId!);
      final v = WithdrawalVoucherModel.fromJson(data);
      _purposeCtrl.text = v.purpose ?? '';
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
    _purposeCtrl.dispose();
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
    final incompleteIndexes = <int>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.isEmpty || _items[i].qty <= 0) i + 1,
    ];
    if (incompleteIndexes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أكمل بيانات البند رقم ${incompleteIndexes.join('، ')} (اختر المادة وأدخل كمية أكبر من صفر) قبل الحفظ',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final keeperName = widget.keeperName ?? 'أمين المخزن';
      final data = {
        'purpose': _purposeCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'created_by': keeperName,
        'items': _items
            .map((e) => {
                  'material_name': e.name,
                  'unit': e.unit,
                  'requested_qty': e.qty,
                  if (e.materialId != null) 'material_id': e.materialId,
                })
            .toList(),
      };
      if (widget.voucherId != null) {
        await ds.updateWithdrawalVoucher(widget.voucherId!, data);
      } else {
        await ds.createWithdrawalVoucher(data);
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
    final summaryAsync = ref.watch(inventorySummaryProvider);
    final materials = summaryAsync.valueOrNull
            ?.where((m) => m.warehouseType == 'main')
            .toList() ??
        [];
    final keeperName = widget.keeperName ?? 'أمين المخزن';

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.remove_circle_outline, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Text(widget.voucherId != null ? 'تعديل سند سحب' : 'سند سحب جديد'),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── منشئ السند ──────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepOrange.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_pin_outlined, color: Colors.deepOrange, size: 18),
                  const SizedBox(width: 8),
                  const Text('منشئ السند: ', style: TextStyle(color: Colors.deepOrange, fontSize: 13)),
                  Text(keeperName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 14),
              // ── سبب السحب ───────────────────────────────────
              TextField(
                controller: _purposeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'سبب / الغرض من السحب *',
                  prefixIcon: Icon(Icons.info_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 1,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('المواد المطلوب سحبها',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('حفظ السند'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════

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
