import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/inventory_model.dart';
import '../../../../data/models/inventory_summary_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';

final _summaryProvider = FutureProvider<List<InventorySummaryModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getInventorySummary();
});

final _txProvider = FutureProvider.family<List<InventoryTransactionModel>, String>(
  (ref, materialId) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getInventoryTransactions(materialId: materialId.isEmpty ? null : materialId);
  },
);

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'الأرصدة'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'الحركات'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SearchBar(
              hintText: 'بحث عن مادة...',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SummaryTab(search: _search),
                _TransactionsTab(search: _search),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showActionDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة حركة'),
      ),
    );
  }

  void _showActionDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('اختر نوع الحركة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.add_circle_outline, color: Colors.white)),
              title: const Text('استلام وارد'),
              subtitle: const Text('إضافة مواد خام جديدة للمخزون'),
              onTap: () {
                Navigator.pop(context);
                _showReceiveDialog(context);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.tune, color: Colors.white)),
              title: const Text('تسوية يدوية'),
              subtitle: const Text('تعديل الرصيد يدوياً (زيادة أو نقصان)'),
              onTap: () {
                Navigator.pop(context);
                _showAdjustmentDialog(context);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.playlist_add_check, color: Colors.white)),
              title: const Text('رصيد افتتاحي'),
              subtitle: const Text('تسجيل الرصيد الافتتاحي لمادة'),
              onTap: () {
                Navigator.pop(context);
                _showOpeningBalanceDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showReceiveDialog(BuildContext context) {
    _showInventoryDialog(
      context,
      title: 'استلام وارد',
      transactionType: 'in',
      positiveOnly: true,
      icon: Icons.add_circle_outline,
      iconColor: Colors.green,
    );
  }

  void _showAdjustmentDialog(BuildContext context) {
    _showInventoryDialog(
      context,
      title: 'تسوية يدوية',
      transactionType: 'adjustment',
      positiveOnly: false,
      icon: Icons.tune,
      iconColor: Colors.orange,
    );
  }

  Future<void> _showInventoryDialog(
    BuildContext context, {
    required String title,
    required String transactionType,
    required bool positiveOnly,
    required IconData icon,
    required Color iconColor,
  }) async {
    final summaryAsync = ref.read(_summaryProvider);
    final materials = summaryAsync.value ?? [];
    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مواد خام. أضف مواداً أولاً.')));
      return;
    }

    InventorySummaryModel? selected = materials.first;
    String warehouse = AppConstants.warehouseMain;
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isPositive = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Text(title),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventorySummaryModel>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'المادة الخام'),
                  items: materials
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.materialName)))
                      .toList(),
                  onChanged: (v) => ss(() => selected = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: warehouse,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: const [
                    DropdownMenuItem(value: 'main', child: Text('المخزن الرئيسي')),
                    DropdownMenuItem(value: 'mixer', child: Text('مخزن الخلاط')),
                  ],
                  onChanged: (v) => ss(() => warehouse = v!),
                ),
                const SizedBox(height: 12),
                if (!positiveOnly) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('زيادة (+)'),
                          selected: isPositive,
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) => ss(() => isPositive = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('نقصان (-)'),
                          selected: !isPositive,
                          selectedColor: Colors.red.shade100,
                          onSelected: (_) => ss(() => isPositive = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية (${selected?.unit ?? 'كجم'})',
                    prefixIcon: Icon(
                      positiveOnly || isPositive ? Icons.add : Icons.remove,
                      color: positiveOnly || isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: iconColor),
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text);
                if (qty == null || qty <= 0 || selected == null) return;
                final ds = ref.read(dataSourceProvider);
                try {
                  final currentInv = await ds.getMaterialInventory(selected!.materialId, warehouse);
                  final currentBalance = currentInv?.balance ?? 0;
                  final effectiveQty = (positiveOnly || isPositive) ? qty : -qty;
                  final newBalance = currentBalance + effectiveQty;

                  await ds.addInventoryTransaction(InventoryTransactionModel(
                    id: '',
                    materialId: selected!.materialId,
                    warehouseType: warehouse,
                    transactionType: transactionType,
                    quantity: qty,
                    createdBy: 'admin',
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    createdAt: DateTime.now(),
                  ));
                  await ds.updateInventoryBalance(selected!.materialId, warehouse, newBalance);

                  ref.invalidate(_summaryProvider);
                  ref.invalidate(_txProvider(''));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('تم تسجيل $title بنجاح')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOpeningBalanceDialog(BuildContext context) async {
    final summaryAsync = ref.read(_summaryProvider);
    final materials = summaryAsync.value ?? [];
    if (materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مواد خام. أضف مواداً أولاً.')));
      return;
    }

    InventorySummaryModel? selected = materials.first;
    String warehouse = AppConstants.warehouseMain;
    final balCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.playlist_add_check, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('رصيد افتتاحي'),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventorySummaryModel>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'المادة الخام'),
                  items: materials
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.materialName)))
                      .toList(),
                  onChanged: (v) => ss(() => selected = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: warehouse,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: const [
                    DropdownMenuItem(value: 'main', child: Text('المخزن الرئيسي')),
                    DropdownMenuItem(value: 'mixer', child: Text('مخزن الخلاط')),
                  ],
                  onChanged: (v) => ss(() => warehouse = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: balCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'الرصيد الافتتاحي (${selected?.unit ?? 'كجم'})'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'السبب / الملاحظة'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final bal = double.tryParse(balCtrl.text);
                if (bal == null || selected == null) return;
                final ds = ref.read(dataSourceProvider);
                try {
                  await ds.addOpeningBalance({
                    'material_id': selected!.materialId,
                    'warehouse_type': warehouse,
                    'balance': bal,
                    'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                    'created_by': 'admin',
                  });
                  await ds.updateInventoryBalance(selected!.materialId, warehouse, bal);
                  ref.invalidate(_summaryProvider);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('تم حفظ الرصيد الافتتاحي')));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  final String search;
  const _SummaryTab({required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(_summaryProvider);

    return summary.when(
      data: (list) {
        final filtered = search.isEmpty
            ? list
            : list.where((s) => s.materialName.contains(search)).toList();

        if (filtered.isEmpty) {
          return const EmptyWidget(
              message: 'لا توجد بيانات مخزون', icon: Icons.inventory_2_outlined);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_summaryProvider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _SummaryCard(item: filtered[i]),
          ),
        );
      },
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(_summaryProvider),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final InventorySummaryModel item;
  const _SummaryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final Color statusColor = item.isCritical
        ? Colors.red
        : item.isLow
            ? Colors.orange
            : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.materialName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.isCritical ? 'حرج' : item.isLow ? 'منخفض' : 'طبيعي',
                    style: TextStyle(
                        color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('الرصيد الحالي: ',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  Text(
                    '${item.currentBalance.toStringAsFixed(2)} ${item.unit}',
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                _BalanceChip('افتتاحي', item.openingBalance, item.unit, Colors.blue),
                const SizedBox(width: 6),
                _BalanceChip('وارد', item.totalIn, item.unit, Colors.green),
                const SizedBox(width: 6),
                _BalanceChip('منصرف', item.totalOut, item.unit, Colors.red),
                const SizedBox(width: 6),
                _BalanceChip('تسويات', item.netAdjustments, item.unit, Colors.purple),
              ],
            ),
            const SizedBox(height: 8),
            if (item.minStock > 0) ...[
              Row(
                children: [
                  Text('الحد الأدنى: ${item.minStock.toStringAsFixed(0)} ${item.unit}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (item.currentBalance / (item.minStock * 2)).clamp(0, 1),
                        backgroundColor: statusColor.withOpacity(0.15),
                        color: statusColor,
                        minHeight: 5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  const _BalanceChip(this.label, this.value, this.unit, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final String search;
  const _TransactionsTab({required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(_txProvider(''));

    return txs.when(
      data: (list) {
        final filtered = search.isEmpty
            ? list
            : list
                .where((t) =>
                    (t.materialId.contains(search)) ||
                    (t.notes?.contains(search) ?? false))
                .toList();

        if (filtered.isEmpty) {
          return const EmptyWidget(message: 'لا توجد حركات مخزون', icon: Icons.swap_horiz);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_txProvider('')),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _TxCard(tx: filtered[i]),
          ),
        );
      },
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(_txProvider('')),
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  final InventoryTransactionModel tx;
  const _TxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final typeInfo = _txTypeInfo(tx.transactionType);
    final warehouse = tx.warehouseType == AppConstants.warehouseMain ? 'رئيسي' : 'خلاط';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeInfo.$2.withOpacity(0.15),
          child: Icon(typeInfo.$1, color: typeInfo.$2, size: 20),
        ),
        title: Row(
          children: [
            Text(typeInfo.$3, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 6),
            Text('• $warehouse', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tx.createdAt.toLocal().toString().substring(0, 16)}  |  بواسطة: ${tx.createdBy}',
              style: const TextStyle(fontSize: 11),
            ),
            if (tx.notes != null && tx.notes!.isNotEmpty)
              Text(tx.notes!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        trailing: Text(
          '${tx.transactionType == 'out' ? '-' : '+'}${tx.quantity.toStringAsFixed(2)}',
          style: TextStyle(
            color: tx.transactionType == 'out' ? Colors.red : Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        isThreeLine: tx.notes != null && tx.notes!.isNotEmpty,
      ),
    );
  }

  (IconData, Color, String) _txTypeInfo(String type) {
    return switch (type) {
      'in' => (Icons.arrow_downward, Colors.green, 'وارد'),
      'out' => (Icons.arrow_upward, Colors.red, 'منصرف'),
      'transfer' => (Icons.swap_horiz, Colors.blue, 'تحويل'),
      'adjustment' => (Icons.tune, Colors.orange, 'تسوية'),
      'opening' => (Icons.playlist_add_check, Colors.purple, 'افتتاحي'),
      _ => (Icons.circle, Colors.grey, type),
    };
  }
}
