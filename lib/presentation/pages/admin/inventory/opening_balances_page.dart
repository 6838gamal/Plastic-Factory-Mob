import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';

final _openingBalancesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getOpeningBalances();
});

class OpeningBalancesPage extends ConsumerWidget {
  const OpeningBalancesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(_openingBalancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأرصدة الافتتاحية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_openingBalancesProvider),
          ),
        ],
      ),
      body: balancesAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.playlist_add_check, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('لا توجد أرصدة افتتاحية مسجّلة',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) => _BalanceCard(
              balance: list[i],
              onEdit: () => _showEditDialog(context, ref, list[i]),
              onDelete: () => _confirmDelete(context, ref, list[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text('خطأ: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(_openingBalancesProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('إضافة رصيد'),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    _showBalanceFormDialog(context, ref, existing: null);
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> existing) {
    _showBalanceFormDialog(context, ref, existing: existing);
  }

  void _showBalanceFormDialog(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic>? existing,
  }) {
    final isEdit = existing != null;
    final balCtrl = TextEditingController(
        text: isEdit ? existing['balance']?.toString() : '');
    final reasonCtrl = TextEditingController(
        text: isEdit ? (existing['reason'] ?? '') : '');
    String warehouse = isEdit ? (existing['warehouse_type'] ?? 'main') : 'main';
    String? materialId = isEdit ? existing['material_id']?.toString() : null;
    String materialName = isEdit ? (existing['material_name'] ?? '') : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.add_circle_outline,
                  color: Colors.blue),
              const SizedBox(width: 8),
              Text(isEdit ? 'تعديل الرصيد الافتتاحي' : 'إضافة رصيد افتتاحي'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdit)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.science_outlined, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            materialName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _MaterialIdInput(
                    onChanged: (id, name) {
                      materialId = id;
                      materialName = name;
                    },
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: warehouse,
                  decoration: const InputDecoration(
                    labelText: 'المخزن',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                  ),
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
                  decoration: const InputDecoration(
                    labelText: 'الرصيد الافتتاحي',
                    prefixIcon: Icon(Icons.scale_outlined),
                    suffixText: 'كجم',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'السبب / الملاحظة',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final bal = double.tryParse(balCtrl.text);
                if (bal == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('أدخل رصيداً صحيحاً')));
                  return;
                }
                if (!isEdit && materialId == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('اختر مادة خام')));
                  return;
                }
                final ds = ref.read(dataSourceProvider);
                try {
                  if (isEdit) {
                    await ds.updateOpeningBalance(existing!['id'].toString(), {
                      'material_id': existing['material_id'].toString(),
                      'warehouse_type': warehouse,
                      'balance': bal,
                      'reason': reasonCtrl.text.trim().isEmpty
                          ? null
                          : reasonCtrl.text.trim(),
                    });
                  } else {
                    await ds.addOpeningBalance({
                      'material_id': materialId!,
                      'warehouse_type': warehouse,
                      'balance': bal,
                      'reason': reasonCtrl.text.trim().isEmpty
                          ? null
                          : reasonCtrl.text.trim(),
                      'created_by': ref.read(authProvider).user?.email ?? 'admin',
                    });
                  }
                  ref.invalidate(_openingBalancesProvider);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(isEdit
                            ? 'تم تحديث الرصيد الافتتاحي'
                            : 'تم حفظ الرصيد الافتتاحي'),
                        backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> balance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الرصيد الافتتاحي'),
        content: Text(
            'هل تريد حذف الرصيد الافتتاحي لـ "${balance['material_name'] ?? ''}"؟\nلا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(dataSourceProvider).deleteOpeningBalance(balance['id'].toString());
        ref.invalidate(_openingBalancesProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حذف الرصيد الافتتاحي'), backgroundColor: Colors.orange));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final Map<String, dynamic> balance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _BalanceCard(
      {required this.balance, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final warehouse = balance['warehouse_type'] == 'mixer' ? 'مخزن الخلاط' : 'المخزن الرئيسي';
    final bal = double.tryParse(balance['balance']?.toString() ?? '0') ?? 0;
    final unit = balance['unit'] ?? 'كجم';
    final dateStr = balance['balance_date']?.toString().split('T').first ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance['material_name'] ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Tag(warehouse, color: Colors.teal),
                      const SizedBox(width: 6),
                      if (dateStr.isNotEmpty) _Tag(dateStr, color: Colors.grey),
                    ],
                  ),
                  if ((balance['reason'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        balance['reason'],
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${bal.toStringAsFixed(1)} $unit',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionButton(
                      icon: Icons.edit_outlined,
                      color: Colors.blue,
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 4),
                    _ActionButton(
                      icon: Icons.delete_outline,
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _MaterialIdInput extends StatefulWidget {
  final void Function(String id, String name) onChanged;
  const _MaterialIdInput({required this.onChanged});

  @override
  State<_MaterialIdInput> createState() => _MaterialIdInputState();
}

class _MaterialIdInputState extends State<_MaterialIdInput> {
  List<Map<String, dynamic>> _materials = [];
  String? _selectedId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ds = ApiDataSource();
      final mats = await ds.getRawMaterials();
      if (mounted) {
        setState(() {
          _materials =
              mats.map((m) => {'id': m.id, 'name': m.name}).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    if (_materials.isEmpty) {
      return const Text('لا توجد مواد خام. أضف مواداً أولاً.',
          style: TextStyle(color: Colors.red));
    }
    return DropdownButtonFormField<String>(
      value: _selectedId,
      decoration: const InputDecoration(
        labelText: 'المادة الخام *',
        prefixIcon: Icon(Icons.science_outlined),
      ),
      items: _materials
          .map((m) => DropdownMenuItem<String>(
                value: m['id'].toString(),
                child: Text(m['name'].toString()),
              ))
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _selectedId = v);
        final mat = _materials.firstWhere((m) => m['id'].toString() == v,
            orElse: () => {});
        widget.onChanged(v, mat['name']?.toString() ?? '');
      },
    );
  }
}
