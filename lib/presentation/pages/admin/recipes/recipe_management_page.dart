import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/models/raw_material_model.dart';
import '../../../../data/models/reference_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/reference_data_provider.dart';

// ── تصنيف المواد إلى أقسام العرض في محرر الوصفة ──────────────────────────
// القسم يُحدَّد تلقائياً من فئة (category) المادة نفسها بدل قائمة ثابتة، لذا
// أي مادة جديدة يضيفها الأدمن في شاشة "المواد" تظهر فوراً هنا بدون تعديل كود.
const _pigmentCategories = {'أصباغ'};
const _additiveCategories = {'إضافات', 'لواصق', 'خلطات'};

String _sectionOf(RawMaterialModel m) {
  if (_pigmentCategories.contains(m.category)) return 'pigments';
  if (_additiveCategories.contains(m.category)) return 'additives';
  return 'raw';
}

// ── Main Page ─────────────────────────────────────────────────────────────
class RecipeManagementPage extends ConsumerStatefulWidget {
  const RecipeManagementPage({super.key});

  @override
  ConsumerState<RecipeManagementPage> createState() =>
      _RecipeManagementPageState();
}

class _RecipeManagementPageState extends ConsumerState<RecipeManagementPage> {
  List<RecipeModel> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final list = await ds.getRecipes();  
      if (mounted) setState(() => _recipes = list);
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

  Future<void> _openEditor({RecipeModel? existing}) async {
    // نجلب كلاً من أنواع الخلطات وقائمة المواد الخام مباشرة من الخادم عند كل
    // فتح للمحرر (rawMaterialsProvider هو autoDispose) — بذلك تظهر أي مادة
    // أُضيفت أو عُدِّلت حديثاً من شاشة "المواد" فوراً هنا دون إعادة تشغيل التطبيق.
    final mixtureTypes =
        await ref.read(mixtureTypesProvider.future).catchError((_) => <MixtureTypeModel>[]);
    final materials =
        await ref.read(rawMaterialsProvider.future).catchError((_) => <RawMaterialModel>[]);
    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _RecipeEditor(
        existingRecipes: _recipes,
        mixtureTypes: mixtureTypes,
        materials: materials,
        existing: existing,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(RecipeModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الوصفة'),
        content: Text('هل تريد حذف وصفة "${r.name}"؟'),
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
    if (ok != true) return;
    try {
      await ref.read(dataSourceProvider).deleteRecipe(r.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recipes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('لا توجد وصفات بعد',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _openEditor,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة وصفة جديدة'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _recipes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _recipes[i];
                      return Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).primaryColor.withOpacity(0.12),
                            child: Icon(Icons.menu_book,
                                color: Theme.of(context).primaryColor),
                          ),
                          title: Text(r.name,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${r.mixtureTypeName ?? ''} — ${r.items.length} مادة',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'تعديل',
                                onPressed: () => _openEditor(existing: r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: 'حذف',
                                onPressed: () => _delete(r),
                              ),
                            ],
                          ),
                          onTap: () => _openEditor(existing: r),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: _recipes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('وصفة جديدة'),
            )
          : null,
    );
  }
}

// ── Recipe Editor Bottom Sheet ────────────────────────────────────────────
class _RecipeEditor extends ConsumerStatefulWidget {
  final List<RecipeModel> existingRecipes;
  final List<MixtureTypeModel> mixtureTypes;
  final List<RawMaterialModel> materials;
  final RecipeModel? existing;

  const _RecipeEditor({
    required this.existingRecipes,
    required this.mixtureTypes,
    required this.materials,
    this.existing,
  });

  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  MixtureTypeModel? _selectedType;
  bool _saving = false;

  // Controllers for each مادة (مفتاحة بالاسم — نفس المفتاح المستخدم في qtyMap)
  final Map<String, TextEditingController> _ctrls = {};

  late List<(String, String)> _rawFields;
  late List<(String, String)> _pigmentFields;
  late List<(String, String)> _additiveFields;
  late List<(String, String)> _allFields;

  @override
  void initState() {
    super.initState();

    final active = widget.materials.where((m) => m.isActive).toList();
    _rawFields = [];
    _pigmentFields = [];
    _additiveFields = [];
    for (final m in active) {
      final field = (m.name, m.unit);
      switch (_sectionOf(m)) {
        case 'pigments':
          _pigmentFields.add(field);
          break;
        case 'additives':
          _additiveFields.add(field);
          break;
        default:
          _rawFields.add(field);
      }
    }
    _allFields = [..._rawFields, ..._pigmentFields, ..._additiveFields];

    for (final (name, _) in _allFields) {
      _ctrls[name] = TextEditingController();
    }

    // إذا كانت الوصفة الحالية (عند التعديل) تحتوي مادة غير موجودة الآن في
    // القائمة (مثلاً عُطِّلت)، أضفها كحقل إضافي حتى لا تُفقد قيمتها المحفوظة.
    if (widget.existing != null) {
      final qtyMap = widget.existing!.qtyMap;
      for (final name in qtyMap.keys) {
        if (!_ctrls.containsKey(name)) {
          _ctrls[name] = TextEditingController();
          _additiveFields.add((name, ''));
          _allFields.add((name, ''));
        }
      }
    }

    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _notesCtrl.text = widget.existing!.notes ?? '';
      _selectedType = widget.mixtureTypes.firstWhere(
        (m) => m.id == widget.existing!.mixtureTypeId,
        orElse: () => widget.mixtureTypes.first,
      );
      final qtyMap = widget.existing!.qtyMap;
      for (final (name, _) in _allFields) {
        final qty = qtyMap[name];
        if (qty != null && qty > 0) {
          _ctrls[name]!.text =
              qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString();
        }
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر نوع الخلطة')));
      return;
    }
    setState(() => _saving = true);
    try {
      final items = <Map<String, dynamic>>[];
      for (final (name, unit) in _allFields) {
        final qty = double.tryParse(_ctrls[name]!.text.trim()) ?? 0;
        if (qty > 0) {
          items.add({'material_name': name, 'standard_qty': qty, 'unit': unit});
        }
      }
      await ref.read(dataSourceProvider).upsertRecipe({
        'mixture_type_id': _selectedType!.id,
        'name': _nameCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'items': items,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, IconData icon, List<(String, String)> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor)),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(
                  color: Theme.of(context).primaryColor.withOpacity(0.3))),
        ]),
        const SizedBox(height: 10),
        ...fields.map((f) {
          final (name, unit) = f;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _ctrls[name],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    suffixText: unit,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    hintText: '0',
                  ),
                ),
              ),
            ]),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    // Mixture types already used (exclude current one if editing)
    final usedIds = widget.existingRecipes
        .where((r) => widget.existing == null || r.id != widget.existing!.id)
        .map((r) => r.mixtureTypeId)
        .toSet();
    final availableTypes = widget.mixtureTypes
        .where((m) => m.isActive && !usedIds.contains(m.id))
        .toList();
    if (_selectedType != null &&
        !availableTypes.any((m) => m.id == _selectedType!.id)) {
      availableTypes.insert(0, _selectedType!);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 0.98,
      expand: false,
      builder: (ctx, scrollCtrl) => Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'تعديل الوصفة' : 'وصفة جديدة'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(ctx),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              )
            else
              TextButton(
                onPressed: _save,
                child: const Text('حفظ',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              // ── Header fields ──────────────────────────────────
              DropdownButtonFormField<MixtureTypeModel>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'نوع الخلطة *'),
                isExpanded: true,
                items: availableTypes
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedType = v;
                    if (_nameCtrl.text.isEmpty && v != null) {
                      _nameCtrl.text = 'وصفة ${v.name}';
                    }
                  });
                },
                validator: (v) => v == null ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الوصفة *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
                maxLines: 2,
              ),

              // ── Material sections (تُبنى تلقائياً من قائمة المواد الحالية) ──
              if (_rawFields.isNotEmpty)
                _section('المواد الخام', Icons.inventory_2_outlined, _rawFields),
              if (_pigmentFields.isNotEmpty)
                _section('الأصباغ', Icons.color_lens_outlined, _pigmentFields),
              if (_additiveFields.isNotEmpty)
                _section('إضافات أخرى', Icons.add_circle_outline, _additiveFields),
              if (_allFields.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    'لا توجد مواد نشطة — أضف موادًا من شاشة "المواد" أولاً',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ الوصفة',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
