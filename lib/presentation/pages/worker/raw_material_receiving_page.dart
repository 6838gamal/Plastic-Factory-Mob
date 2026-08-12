// lib/presentation/pages/worker/receiving_warehouse_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/api_datasource.dart';
import '../../../data/models/inventory_summary_model.dart';
import '../../../data/models/voucher_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reference_data_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Providers خاصة بشاشة استلام وارد المواد
// ──────────────────────────────────────────────────────────────────────────────

final _receivingInventoryProvider = FutureProvider.autoDispose<List<InventorySummaryModel>>((ref) async {
  final summary = await ref.watch(inventorySummaryProvider.future);
  return summary.where((m) => m.warehouseType == 'receiving').toList();
});

final _receivingIncomingProvider = FutureProvider.autoDispose<List<TransferVoucherModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  final raw = await ds.getTransferVouchers(transferType: 'mixer_to_receiving');
  return raw.map(TransferVoucherModel.fromJson).toList();
});

// ──────────────────────────────────────────────────────────────────────────────
// شاشة استلام وارد المواد
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
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_receivingInventoryProvider);
    ref.invalidate(_receivingIncomingProvider);
    ref.invalidate(inventorySummaryProvider);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text('شاشة استلام وارد المواد'),
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
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.arrow_downward),
              ),
              text: 'وارد من الخلاط',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ReceivingInventoryTab(onRefresh: _refresh),
          _ReceivingIncomingTab(operatorName: _operatorName, onRefresh: _refresh),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// تبويب المخزون
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingInventoryTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _ReceivingInventoryTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_receivingInventoryProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('لا توجد مواد في شاشة الاستلام', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('المواد تصل هنا بعد تأكيدها من مخزن الخلاط',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }
        final total = items.fold(0.0, (s, m) => s + m.currentBalance);
        return Column(
          children: [
            _buildSummaryCard('إجمالي مواد الاستلام', total, Colors.deepPurple),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (ctx, i) => _buildMaterialCard(items[i], Colors.deepPurple),
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
                Text('لا توجد طلبات واردة من مخزن الخلاط', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 6),
                Text('سيتم استلام المواد هنا بعد تأكيدها من مخزن الخلاط',
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
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// بطاقة السند لشاشة الاستلام
// ──────────────────────────────────────────────────────────────────────────────

class _ReceivingVoucherCard extends ConsumerWidget {
  final TransferVoucherModel voucher;
  final String operatorName;
  final VoidCallback onAction;

  const _ReceivingVoucherCard({
    required this.voucher,
    required this.operatorName,
    required this.onAction,
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
                const Icon(Icons.assignment_outlined, size: 16, color: Colors.deepPurple),
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
                  // Confirm receipt
                  if (voucher.isPending)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('تأكيد استلام المواد'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'تأكيد استلام المواد',
                          'هل تأكد استلام جميع المواد من مخزن الخلاط؟\nسيتم تأكيد استلام المواد في شاشة الاستلام.',
                        );
                        if (ok) {
                          try {
                            await ds.confirmTransferVoucher(voucher.id!, {'confirmed_by': operatorName});
                            onAction();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم تأكيد استلام المواد بنجاح'),
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
        Icon(Icons.assignment_outlined, color: color),
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
