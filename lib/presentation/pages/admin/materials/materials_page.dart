import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/raw_material_model.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/helpers.dart';

class MaterialsPage extends ConsumerStatefulWidget {
  const MaterialsPage({super.key});

  @override
  ConsumerState<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends ConsumerState<MaterialsPage> {
  String _search = '';
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final materials = ref.watch(rawMaterialsProvider);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SearchBar(
                  hintText: 'بحث عن مادة...',
                  leading: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                materials.when(
                  data: (list) {
                    final categories = list.map((m) => m.category).toSet().toList()..sort();
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('الكل'),
                            selected: _categoryFilter == null,
                            onSelected: (_) => setState(() => _categoryFilter = null),
                          ),
                          const SizedBox(width: 6),
                          ...categories.map((c) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(c),
                                  selected: _categoryFilter == c,
                                  onSelected: (_) =>
                                      setState(() => _categoryFilter = c),
                                ),
                              )),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => ErrorWidget2(
                    message: Helpers.friendlyError(e),
                    onRetry: () => ref.invalidate(rawMaterialsProvider),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: materials.when(
              data: (list) {
                var filtered = list;
                if (_search.isNotEmpty) {
                  filtered = filtered.where((m) => m.name.contains(_search)).toList();
                }
                if (_categoryFilter != null) {
                  filtered = filtered.where((m) => m.category == _categoryFilter).toList();
                }
                if (filtered.isEmpty) {
                  return const EmptyWidget(
                      message: 'لا توجد مواد خام', icon: Icons.science_outlined);
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(rawMaterialsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _MaterialCard(material: filtered[i]),
                  ),
                );
              },
              loading: () => const ShimmerList(),
              error: (e, _) => ErrorWidget2(
                message: Helpers.friendlyError(e),
                onRetry: () => ref.invalidate(rawMaterialsProvider),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مادة'),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, RawMaterialModel? material) {
    final nameCtrl = TextEditingController(text: material?.name);
    final categoryCtrl = TextEditingController(text: material?.category);
    final minStockCtrl =
        TextEditingController(text: material != null ? material.minStock.toString() : '');
    String selectedUnit = material?.unit ?? AppConstants.units.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Text(material == null ? 'إضافة مادة خام' : 'تعديل المادة الخام'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // كود المادة — للقراءة فقط، يُولَّد تلقائياً
                if (material?.code != null && material!.code!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'معرّف المادة (تلقائي)',
                        prefixIcon: const Icon(Icons.qr_code_2_outlined),
                        filled: true,
                        fillColor: Colors.indigo.shade50,
                      ),
                      child: Text(
                        material.code!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم *'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: minStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الحد الأدنى للتنبيه'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedUnit,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: AppConstants.units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => ss(() => selectedUnit = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final ds = ref.read(dataSourceProvider);
                await ds.upsertRawMaterial({
                  if (material != null) 'id': material.id,
                  'name': nameCtrl.text.trim(),
                  'category': categoryCtrl.text.trim(),
                  'min_stock': double.tryParse(minStockCtrl.text) ?? 0,
                  'unit': selectedUnit,
                  'is_active': true,
                });
                ref.invalidate(rawMaterialsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialCard extends ConsumerWidget {
  final RawMaterialModel material;
  const _MaterialCard({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
          child: Text(
            (material.code != null && material.code!.isNotEmpty)
                ? material.code!.split('-').first
                : (material.name.isNotEmpty ? material.name[0] : '?'),
            style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 11),
          ),
        ),
        title: Row(
          children: [
            if (material.code != null && material.code!.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border.all(
                      color: Colors.indigo.shade200, width: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  material.code!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(material.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        subtitle: Text(
          '${material.category} • الحد الأدنى: ${Helpers.formatQuantityInKg(material.minStock.toDouble(), material.unit)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(material.unit,
                  style: const TextStyle(fontSize: 12, color: Colors.blue)),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  if (context.mounted) {
                    _showEditDialogStatic(context, ref, material);
                  }
                } else if (v == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('تأكيد الحذف'),
                      content: Text('هل تريد حذف "${material.name}"؟'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('حذف', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final ds = ref.read(dataSourceProvider);
                    await ds.deleteRawMaterial(material.id);
                    ref.invalidate(rawMaterialsProvider);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('حذف',
                      style: TextStyle(
                          color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialogStatic(
      BuildContext context, WidgetRef ref, RawMaterialModel material) {
    final nameCtrl = TextEditingController(text: material.name);
    final categoryCtrl = TextEditingController(text: material.category);
    final minStockCtrl = TextEditingController(text: material.minStock.toString());
    String selectedUnit = material.unit;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('تعديل المادة الخام'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // كود المادة — للقراءة فقط
                if (material.code != null && material.code!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'معرّف المادة (تلقائي)',
                        prefixIcon: const Icon(Icons.qr_code_2_outlined),
                        filled: true,
                        fillColor: Colors.indigo.shade50,
                      ),
                      child: Text(
                        material.code!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'الاسم')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: categoryCtrl,
                    decoration: const InputDecoration(labelText: 'الفئة')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: minStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الحد الأدنى'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedUnit,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: AppConstants.units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => ss(() => selectedUnit = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final ds = ref.read(dataSourceProvider);
                await ds.upsertRawMaterial({
                  'id': material.id,
                  'name': nameCtrl.text.trim(),
                  'category': categoryCtrl.text.trim(),
                  'min_stock': double.tryParse(minStockCtrl.text) ?? material.minStock,
                  'unit': selectedUnit,
                  'is_active': true,
                });
                ref.invalidate(rawMaterialsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
