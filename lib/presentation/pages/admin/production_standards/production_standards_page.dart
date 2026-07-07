import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/production_standard_model.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';

class ProductionStandardsPage extends ConsumerStatefulWidget {
  const ProductionStandardsPage({super.key});

  @override
  ConsumerState<ProductionStandardsPage> createState() =>
      _ProductionStandardsPageState();
}

class _ProductionStandardsPageState
    extends ConsumerState<ProductionStandardsPage> {
  // Load ALL (not just active) for management
  final _allStandardsProvider =
      FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
    final ds = ref.read(dataSourceProvider);
    return ds.getProductionStandards(activeOnly: false);
  });

  @override
  Widget build(BuildContext context) {
    final standardsAsync = ref.watch(_allStandardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('معايير الإنتاج'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_allStandardsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة معيار'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: standardsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyWidget(
              message: 'لا توجد معايير إنتاج مضافة بعد',
              icon: Icons.straighten_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              final isActive = s['is_active'] as bool? ?? true;
              final gramPerPair =
                  (s['standard_gram_per_pair'] as num?)?.toDouble() ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isActive
                        ? Colors.indigo.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor:
                        isActive ? Colors.indigo.shade50 : Colors.grey.shade100,
                    child: Icon(
                      Icons.straighten,
                      color: isActive ? Colors.indigo : Colors.grey,
                    ),
                  ),
                  title: Text(
                    s['product_name'] as String? ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isActive ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Chip(
                            '${gramPerPair.toStringAsFixed(0)} جرام/زوج',
                            Colors.indigo,
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            '${(gramPerPair / 1000).toStringAsFixed(3)} كجم/زوج',
                            Colors.teal,
                          ),
                        ],
                      ),
                      if (s['product_code'] != null &&
                          (s['product_code'] as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'كود: ${s['product_code']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      if (s['notes'] != null &&
                          (s['notes'] as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          s['notes'] as String,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') {
                        _showForm(context, existing: s);
                      } else if (action == 'toggle') {
                        _toggleActive(s['id'] as String, s, !isActive);
                      } else if (action == 'delete') {
                        _confirmDelete(s['id'] as String,
                            s['product_name'] as String? ?? '');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 18,
                                color: Colors.blue),
                            SizedBox(width: 8),
                            Text('تعديل'),
                          ])),
                      PopupMenuItem(
                          value: 'toggle',
                          child: Row(children: [
                            Icon(
                              isActive
                                  ? Icons.toggle_off_outlined
                                  : Icons.toggle_on_outlined,
                              size: 18,
                              color: isActive ? Colors.orange : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(isActive ? 'تعطيل' : 'تفعيل'),
                          ])),
                      const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline, size: 18,
                                color: Colors.red),
                            SizedBox(width: 8),
                            Text('حذف',
                                style: TextStyle(color: Colors.red)),
                          ])),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorWidget2(
          message: Helpers.friendlyError(e),
          onRetry: () => ref.invalidate(_allStandardsProvider),
        ),
      ),
    );
  }

  void _showForm(BuildContext context,
      {Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(
        text: existing?['product_name'] as String? ?? '');
    final codeCtrl = TextEditingController(
        text: existing?['product_code'] as String? ?? '');
    final gramCtrl = TextEditingController(
        text: (existing?['standard_gram_per_pair'] as num?)
                ?.toStringAsFixed(0) ??
            '');
    final notesCtrl = TextEditingController(
        text: existing?['notes'] as String? ?? '');
    final isNew = existing == null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(isNew ? Icons.add_circle_outline : Icons.edit_outlined,
              color: Colors.indigo),
          const SizedBox(width: 8),
          Text(isNew ? 'إضافة معيار إنتاج' : 'تعديل المعيار',
              style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف *',
                  hintText: 'مثال: رجالي، ولادي، نسائي...',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'كود الصنف (اختياري)',
                  prefixIcon: Icon(Icons.qr_code_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: gramCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المعيار (جرام/زوج) *',
                  hintText: 'مثال: 479',
                  prefixIcon: Icon(Icons.straighten),
                  suffixText: 'جرام/زوج',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final gram = double.tryParse(gramCtrl.text.trim());
              if (name.isEmpty || gram == null || gram <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'يرجى إدخال اسم الصنف والمعيار بالجرام/زوج'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              try {
                final ds = ref.read(dataSourceProvider);
                final data = {
                  'product_name': name,
                  'product_code': codeCtrl.text.trim().isEmpty
                      ? null
                      : codeCtrl.text.trim(),
                  'standard_gram_per_pair': gram,
                  'is_active': true,
                  'notes': notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                };
                if (isNew) {
                  await ds.createProductionStandard(data);
                } else {
                  data['is_active'] = existing['is_active'] as bool? ?? true;
                  await ds.updateProductionStandard(
                      existing['id'] as String, data);
                }
                ref.invalidate(_allStandardsProvider);
                ref.invalidate(productionStandardsProvider);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(isNew
                        ? 'تم إضافة المعيار بنجاح'
                        : 'تم تحديث المعيار'),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('خطأ: ${e.toString().replaceFirst("Exception: ", "")}'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: Text(isNew ? 'إضافة' : 'حفظ',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(
      String id, Map<String, dynamic> s, bool newActive) async {
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.updateProductionStandard(id, {
        'product_name': s['product_name'],
        'product_code': s['product_code'],
        'standard_gram_per_pair': s['standard_gram_per_pair'],
        'is_active': newActive,
        'notes': s['notes'],
      });
      ref.invalidate(_allStandardsProvider);
      ref.invalidate(productionStandardsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _confirmDelete(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف معيار "$name"؟\n\nلا يمكن حذف معيار مستخدم في سجلات الإنتاج.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        final ds = ref.read(dataSourceProvider);
        await ds.deleteProductionStandard(id);
        ref.invalidate(_allStandardsProvider);
        ref.invalidate(productionStandardsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم حذف المعيار'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
