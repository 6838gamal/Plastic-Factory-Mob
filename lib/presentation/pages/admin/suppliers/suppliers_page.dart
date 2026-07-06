import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';

// ── Provider ─────────────────────────────────────────────────────

final _suppliersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getSuppliers();
});

// ── Supplier categories ───────────────────────────────────────────

const _categories = [
  'مواد خام',
  'مواد تعبئة',
  'مواد كيميائية',
  'آلات ومعدات',
  'قطع غيار',
  'خدمات',
  'أخرى',
];

// ── Page ─────────────────────────────────────────────────────────

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  String _search = '';
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_suppliersProvider);

    return Scaffold(
      body: Column(
        children: [
          // ── Search + filter bar ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث باسم المورد أو رقم الهاتف ...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      filled: true,
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('النشطون فقط'),
                  selected: _activeOnly,
                  onSelected: (v) => setState(() => _activeOnly = v),
                  selectedColor: Colors.teal.withOpacity(0.2),
                  checkmarkColor: Colors.teal,
                ),
              ],
            ),
          ),

          // ── List ──────────────────────────────────────────────
          Expanded(
            child: async.when(
              data: (list) {
                final filtered = list.where((s) {
                  if (_activeOnly && s['is_active'] != true) return false;
                  if (_search.isEmpty) return true;
                  final name = (s['name'] ?? '').toString().toLowerCase();
                  final phone = (s['phone'] ?? '').toString();
                  return name.contains(_search.toLowerCase()) ||
                      phone.contains(_search);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.business_outlined,
                            size: 60, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          list.isEmpty
                              ? 'لا يوجد موردون بعد\nاضغط + لإضافة مورد'
                              : 'لا توجد نتائج للبحث',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_suppliersProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _SupplierCard(
                      supplier: filtered[i],
                      onChanged: () => ref.invalidate(_suppliersProvider),
                    ),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('خطأ في التحميل: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSupplierDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مورد'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _showSupplierDialog(
      BuildContext context, Map<String, dynamic>? existing) {
    showDialog(
      context: context,
      builder: (_) => _SupplierDialog(
        existing: existing,
        onSaved: () => ref.invalidate(_suppliersProvider),
      ),
    );
  }
}

// ── Supplier Card ─────────────────────────────────────────────────

class _SupplierCard extends ConsumerWidget {
  final Map<String, dynamic> supplier;
  final VoidCallback onChanged;
  const _SupplierCard({required this.supplier, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = supplier['is_active'] as bool? ?? true;
    final name = supplier['name'] as String? ?? '';
    final phone = supplier['phone'] as String?;
    final email = supplier['email'] as String?;
    final category = supplier['category'] as String?;
    final address = supplier['address'] as String?;
    final notes = supplier['notes'] as String?;
    final id = supplier['id'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isActive ? 1 : 0,
      color: isActive ? null : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.teal.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.business,
                    color: isActive ? Colors.teal : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isActive ? null : Colors.grey,
                        ),
                      ),
                      if (category?.isNotEmpty == true)
                        Text(
                          category!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.teal[700]),
                        ),
                    ],
                  ),
                ),
                if (!isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('غير نشط',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 11)),
                  ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      showDialog(
                        context: context,
                        builder: (_) => _SupplierDialog(
                          existing: supplier,
                          onSaved: onChanged,
                        ),
                      );
                    } else if (action == 'toggle') {
                      _toggleActive(context, ref, id, !isActive);
                    } else if (action == 'delete') {
                      _confirmDelete(context, ref, id, name);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('تعديل'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(children: [
                        Icon(
                          isActive
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                          color: isActive ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(isActive ? 'تعطيل' : 'تفعيل'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('حذف',
                            style: TextStyle(color: Colors.red)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            if (phone?.isNotEmpty == true ||
                email?.isNotEmpty == true ||
                address?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (phone?.isNotEmpty == true)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.phone_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(phone!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700])),
                    ]),
                  if (email?.isNotEmpty == true)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.email_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(email!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700])),
                    ]),
                  if (address?.isNotEmpty == true)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(address!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700])),
                    ]),
                ],
              ),
            ],
            if (notes?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                notes!,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(
      BuildContext context, WidgetRef ref, String id, bool active) async {
    try {
      await ref
          .read(dataSourceProvider)
          .updateSupplier(id, {'is_active': active});
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.red),
          SizedBox(width: 8),
          Text('تأكيد الحذف'),
        ]),
        content: Text('هل تريد حذف المورد "$name" نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dataSourceProvider).deleteSupplier(id);
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حذف المورد'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ── Supplier Dialog (Add / Edit) ──────────────────────────────────

class _SupplierDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _SupplierDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  String? _category;
  bool _isActive = true;
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl =
        TextEditingController(text: s?['name']?.toString() ?? '');
    _phoneCtrl =
        TextEditingController(text: s?['phone']?.toString() ?? '');
    _emailCtrl =
        TextEditingController(text: s?['email']?.toString() ?? '');
    _addressCtrl =
        TextEditingController(text: s?['address']?.toString() ?? '');
    _notesCtrl =
        TextEditingController(text: s?['notes']?.toString() ?? '');
    _category = s?['category']?.toString();
    _isActive = s?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ds = ref.read(dataSourceProvider);
      final body = {
        'name': _nameCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty)
          'phone': _phoneCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty)
          'address': _addressCtrl.text.trim(),
        if (_category != null) 'category': _category,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
        'is_active': _isActive,
      };
      if (_isEdit) {
        await ds.updateSupplier(widget.existing!['id'] as String, body);
      } else {
        await ds.createSupplier(body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isEdit ? 'تم تحديث بيانات المورد' : 'تم إضافة المورد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(_isEdit ? Icons.edit_outlined : Icons.add_business_outlined,
            color: Colors.teal),
        const SizedBox(width: 8),
        Text(_isEdit ? 'تعديل بيانات المورد' : 'إضافة مورد جديد'),
      ]),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد *',
                    prefixIcon: Icon(Icons.business_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                // Phone
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Category dropdown
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'تصنيف المورد',
                    prefixIcon: Icon(Icons.category_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— بدون تصنيف —')),
                    ..._categories.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 12),
                // Address
                TextFormField(
                  controller: _addressCtrl,
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Active toggle
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('مورد نشط'),
                  subtitle: Text(_isActive
                      ? 'يظهر في قوائم الاختيار'
                      : 'مُعطَّل مؤقتاً'),
                  secondary: Icon(
                    _isActive
                        ? Icons.check_circle_outline
                        : Icons.block_outlined,
                    color: _isActive ? Colors.green : Colors.grey,
                  ),
                  activeColor: Colors.teal,
                  contentPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal, foregroundColor: Colors.white),
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
    );
  }
}

// ── Standalone page wrapper (for warehouse keeper access) ─────────

class SuppliersStandalonePage extends StatelessWidget {
  const SuppliersStandalonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموردون'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: const SuppliersPage(),
    );
  }
}
