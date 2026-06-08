import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/supabase_datasource.dart';
import '../../../../data/models/inventory_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../widgets/common/loading_widget.dart';

final inventoryPageProvider = FutureProvider.family<List<InventoryModel>, String>(
  (ref, warehouse) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getInventory(warehouseType: warehouse.isEmpty ? null : warehouse);
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'المخزن الرئيسي'),
            Tab(text: 'مخزن الخلاط'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(12),
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
              _InventoryList(warehouse: '', search: _search),
              _InventoryList(warehouse: AppConstants.warehouseMain, search: _search),
              _InventoryList(warehouse: AppConstants.warehouseMixer, search: _search),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryList extends ConsumerWidget {
  final String warehouse;
  final String search;
  const _InventoryList({required this.warehouse, required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryPageProvider(warehouse));

    return inventory.when(
      data: (list) {
        final filtered = search.isEmpty
            ? list
            : list.where((i) => i.materialName.contains(search)).toList();

        if (filtered.isEmpty) {
          return const EmptyWidget(
            message: 'لا توجد بيانات مخزون',
            icon: Icons.inventory_2_outlined,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(inventoryPageProvider(warehouse)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _InventoryCard(item: filtered[i]),
          ),
        );
      },
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: 'خطأ في التحميل: $e',
        onRetry: () => ref.invalidate(inventoryPageProvider(warehouse)),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final InventoryModel item;
  const _InventoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.isCritical
        ? Colors.red
        : item.isLowStock
            ? Colors.orange
            : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.materialName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                _WarehouseChip(warehouse: item.warehouseType),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _InfoItem(
                    label: 'الرصيد',
                    value: '${item.balance.toStringAsFixed(2)} ${item.unit}',
                    color: color,
                  ),
                ),
                Expanded(
                  child: _InfoItem(
                    label: 'الحد الأدنى',
                    value: '${item.minStock.toStringAsFixed(0)} ${item.unit}',
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (item.balance / (item.minStock * 2)).clamp(0, 1),
                backgroundColor: color.withOpacity(0.2),
                color: color,
                minHeight: 6,
              ),
            ),
            if (item.isLowStock) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    item.isCritical ? Icons.error : Icons.warning_amber,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.isCritical ? 'مخزون حرج!' : 'مخزون منخفض',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
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

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14)),
      ],
    );
  }
}

class _WarehouseChip extends StatelessWidget {
  final String warehouse;
  const _WarehouseChip({required this.warehouse});

  @override
  Widget build(BuildContext context) {
    final label = warehouse == AppConstants.warehouseMain ? 'رئيسي' : 'خلاط';
    final color = warehouse == AppConstants.warehouseMain ? Colors.blue : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}
