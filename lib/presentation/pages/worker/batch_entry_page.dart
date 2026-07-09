import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/reference_data_provider.dart';
import '../../providers/batch_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/helpers.dart';
import '../../../data/models/reference_models.dart';
import '../../../data/models/raw_material_model.dart';
import '../../providers/auth_provider.dart';

// ── نوع رصيد مادة: الرصيد + الوحدة الأصلية من المخزن ───────────────────────
typedef _BalInfo = ({double balance, String unit});

// ── رصيد مخزن الخلاط: معرّف المادة → رصيد + وحدة ───────────────────────────
//
// مبني حسب material_id (وليس اسم المادة) حتى يبقى صحيحاً بغض النظر عن كيفية
// كتابة الاسم — ويتوافق تلقائياً مع أي مادة جديدة تُضاف من شاشة الإدارة.
// مبني فوق inventorySummaryProvider المشترك (وليس نسخة محلية منفصلة) حتى يتحدّث
// تلقائياً عند أي عملية تُغيّر المخزون من شاشات أخرى (ترحيل سند، تحويل، إلخ)
final _mixerBalanceProvider =
    FutureProvider.autoDispose<Map<String, _BalInfo>>((ref) async {
  final items = await ref.watch(inventorySummaryProvider.future);
  return {
    for (final item in items)
      if (item.warehouseType == AppConstants.warehouseMixer)
        item.materialId: (
          balance: item.currentBalance,
          unit: item.unit,
        ),
  };
});

// ── أسماء المواد ذات الأعمدة الثابتة تاريخياً (لمؤشرات لوحة التحكم/التقارير) ──
//
// هذه الأسماء يجب أن تطابق raw_materials.name تماماً. إن أعاد الإدمن تسمية
// إحدى هذه المواد أو حذفها، سيصبح المؤشر المقابل صفراً في التقارير القديمة
// (الخصم من المخزون نفسه لا يتأثر، لأنه يعتمد على القائمة العامة materials).
const String _kNamePvc = 'مواد خام PVC صيني';
const String _kNameDop = 'DOP زيت';
const List<String> _kScrapNames = [
  'سكراب اسود ناعم',
  'سكراب ازرق ناعم',
  'سكراب ازرق سكري',
];
const String _kNameCalcium = 'كالسيوم باودر عبوة 25 كيلو';
const String _kNameWax = 'شمع باودر عبوة 25 كيلو';
const String _kNameStabilizer = 'مثبت استبليزر باودر عبوة 25 كيلو';
const String _kNameTitanium = 'تيتانيوم';

// ── ترتيب وأيقونات الأقسام حسب فئة المادة ──────────────────────────────────
const List<String> _kCategoryOrder = ['مواد أساسية', 'أصباغ', 'إضافات'];

IconData _iconForCategory(String category) {
  switch (category) {
    case 'مواد أساسية':
      return Icons.inventory_2_outlined;
    case 'أصباغ':
      return Icons.color_lens_outlined;
    case 'إضافات':
      return Icons.add_circle_outline;
    default:
      return Icons.category_outlined;
  }
}

class BatchEntryPage extends ConsumerStatefulWidget {
  const BatchEntryPage({super.key});

  @override
  ConsumerState<BatchEntryPage> createState() => _BatchEntryPageState();
}

class _BatchEntryPageState extends ConsumerState<BatchEntryPage> {
  final _formKey = GlobalKey<FormState>();

  final _batchNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ── حقول إدخال المواد الخام — تُبنى ديناميكياً حسب قائمة raw_materials ──
  // مفتاح الخريطة هو material_id، وليس اسماً ثابتاً؛ بذلك تظهر أي مادة جديدة
  // يضيفها الإدمن أو أمين المخزن تلقائياً دون أي تعديل على هذه الشاشة.
  final Map<String, TextEditingController> _matCtrls = {};

  TextEditingController _ctrlFor(String materialId) =>
      _matCtrls.putIfAbsent(materialId, () => TextEditingController());

  DateTime _selectedDate = DateTime.now();
  String? _selectedShift;
  WorkerModel? _selectedWorker;
  MixerModel? _selectedMixer;
  ProductModel? _selectedProduct;
  MixtureTypeModel? _selectedMixtureType;
  File? _scaleImage;
  bool _loadingBatchNum = false;
  bool _loadingRecipe = false;
  bool _recipeApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextBatchNumber());
  }

  @override
  void dispose() {
    _batchNumberCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _matCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  RawMaterialModel? _findByName(List<RawMaterialModel> mats, String name) {
    for (final m in mats) {
      if (m.name == name) return m;
    }
    return null;
  }

  double _qtyKgOf(List<RawMaterialModel> mats, String name) {
    final m = _findByName(mats, name);
    if (m == null) return 0;
    final ctrl = _matCtrls[m.id];
    if (ctrl == null) return 0;
    final v = double.tryParse(ctrl.text.trim()) ?? 0;
    return _toKg(v, m.unit);
  }

  double _toKg(double qty, String unit) {
    final u = unit.trim();
    if (u == 'جرام' || u.toLowerCase() == 'gram') return qty / 1000.0;
    return qty;
  }

  Future<void> _applyRecipe(MixtureTypeModel mixtureType) async {
    setState(() { _loadingRecipe = true; _recipeApplied = false; });
    try {
      final ds = ref.read(dataSourceProvider);
      final recipe = await ds.getRecipeByMixtureType(mixtureType.id);
      if (recipe == null || !mounted) return;
      final mats = ref.read(rawMaterialsProvider).valueOrNull ?? [];
      final qtyMap = recipe.qtyMap;
      bool anyFilled = false;
      for (final entry in qtyMap.entries) {
        final mat = _findByName(mats, entry.key);
        if (mat != null && entry.value > 0) {
          final qty = entry.value;
          final ctrl = _ctrlFor(mat.id);
          ctrl.text = qty == qty.truncateToDouble()
              ? qty.toInt().toString()
              : qty.toString();
          anyFilled = true;
        }
      }
      if (anyFilled && mounted) {
        setState(() => _recipeApplied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعبئة الوصفة: ${recipe.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRecipe = false);
    }
  }

  Future<void> _loadNextBatchNumber() async {
    if (!mounted) return;
    setState(() => _loadingBatchNum = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final next = await ds.getNextBatchNumber();
      if (mounted) _batchNumberCtrl.text = next;
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBatchNum = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _scaleImage = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShift == null ||
        _selectedWorker == null ||
        _selectedMixer == null ||
        _selectedProduct == null ||
        _selectedMixtureType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى ملء جميع الحقول المطلوبة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final rawMaterialsState = ref.read(rawMaterialsProvider);
    if (rawMaterialsState.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يتم تحديث قائمة المواد الخام، حاول مرة أخرى بعد لحظة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final mats = rawMaterialsState.valueOrNull ?? [];

    // Upload image (optional on web)
    String? imageUrl;
    if (_scaleImage != null) {
      try {
        final bytes = await _scaleImage!.readAsBytes();
        final ds = ref.read(dataSourceProvider);
        imageUrl = await ds.uploadImage(
          'batch-images',
          'scale/${_batchNumberCtrl.text}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes,
        );
      } catch (_) {}
    }

    // ── بناء قائمة المواد للخصم من المخزن — من كل مادة نشطة تم إدخال كمية لها ──
    final materials = <Map<String, dynamic>>[];
    final pigmentsList = <Map<String, dynamic>>[];
    final additivesList = <Map<String, dynamic>>[];

    for (final m in mats) {
      final ctrl = _matCtrls[m.id];
      if (ctrl == null) continue;
      final qty = double.tryParse(ctrl.text.trim()) ?? 0;
      if (qty <= 0) continue;
      materials.add({
        'material_id': m.id,
        'material_name': m.name,
        'quantity': qty,
        'unit': m.unit,
      });
      if (m.category == 'أصباغ') {
        pigmentsList.add({'name': m.name, 'quantity': qty, 'unit': m.unit});
      } else if (m.category == 'إضافات') {
        additivesList.add({'name': m.name, 'quantity': qty, 'unit': m.unit});
      }
    }

    // ── مؤشرات ثابتة تاريخياً (تُستخدم في لوحة التحكم والتقارير) ─────────
    final scrapQty = _kScrapNames.fold<double>(
        0, (s, name) => s + _qtyKgOf(mats, name));

    final batchData = {
      'batch_number':      _batchNumberCtrl.text.trim(),
      'date':              _selectedDate.toIso8601String().split('T').first,
      'shift':             _selectedShift,
      'worker_id':         _selectedWorker!.id,
      'worker_name':       _selectedWorker!.name,
      'mixer_id':          _selectedMixer!.id,
      'mixer_name':        _selectedMixer!.name,
      'product_id':        _selectedProduct!.id,
      'product_name':      _selectedProduct!.name,
      'mixture_type_id':   _selectedMixtureType!.id,
      'mixture_type_name': _selectedMixtureType!.name,
      'pvc_qty':           _qtyKgOf(mats, _kNamePvc),
      'dop_qty':           _qtyKgOf(mats, _kNameDop),
      'scrap_qty':         scrapQty,
      'calcium_qty':       _qtyKgOf(mats, _kNameCalcium),
      'wax_qty':           _qtyKgOf(mats, _kNameWax),
      'stabilizer_qty':    _qtyKgOf(mats, _kNameStabilizer),
      'titanium_qty':      _qtyKgOf(mats, _kNameTitanium),
      'pigments':          pigmentsList,
      'additives':         additivesList,
      'notes':             _notesCtrl.text.trim(),
      'scale_image_url':   imageUrl,
      'materials':         materials,
    };

    final result = await ref.read(batchOperationsProvider.notifier).saveBatch(batchData);

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.saveSuccess), backgroundColor: Colors.green),
      );
      ref.invalidate(inventorySummaryProvider); // خصم من مخزن الخلاط — حدّث الكروت في كل الشاشات
      ref.invalidate(_mixerBalanceProvider); // تحديث رصيد مخزن الخلاط بعد الحفظ
      ref.invalidate(rawMaterialsProvider); // إعادة جلب قائمة المواد الخام من الخادم (تجنّب الكاش القديمة)
      _resetForm();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? AppStrings.saveFailed),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _loadNextBatchNumber();
    _notesCtrl.clear();
    for (final c in _matCtrls.values) {
      c.clear();
    }
    setState(() {
      _selectedDate = DateTime.now();
      _selectedShift = null;
      _selectedWorker = null;
      _selectedMixer = null;
      _selectedProduct = null;
      _selectedMixtureType = null;
      _scaleImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(workersProvider);
    final mixers = ref.watch(mixersProvider);
    final products = ref.watch(productsProvider);
    final mixtureTypes = ref.watch(mixtureTypesProvider);
    final rawMaterials = ref.watch(rawMaterialsProvider);
    final opsState = ref.watch(batchOperationsProvider);

    // رصيد مخزن الخلاط — Map<material_id, (balance, unit)>
    final mixerBal = ref.watch(_mixerBalanceProvider).value ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── معلومات الطبخة ──────────────────────────────────
            _SectionHeader(title: 'معلومات الطبخة', icon: Icons.info_outline),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _batchNumberCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.batchNumber,
                      prefixIcon: const Icon(Icons.tag),
                      suffixText: 'تلقائي',
                      suffixStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'رقم الطبخة مطلوب' : null,
                  ),
                ),
                if (_loadingBatchNum)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'توليد رقم جديد',
                    onPressed: _loadNextBatchNumber,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: AppStrings.date,
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDate.year}-'
                  '${_selectedDate.month.toString().padLeft(2, '0')}-'
                  '${_selectedDate.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedShift,
              decoration: const InputDecoration(labelText: '${AppStrings.shift} *'),
              items: AppConstants.defaultShifts
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedShift = v),
              validator: (v) => v == null ? 'الوردية مطلوبة' : null,
            ),
            const SizedBox(height: 12),

            workers.when(
              data: (list) => DropdownButtonFormField<WorkerModel>(
                value: _selectedWorker,
                decoration: const InputDecoration(labelText: '${AppStrings.worker} *'),
                isExpanded: true,
                items: list
                    .map((w) => DropdownMenuItem(value: w, child: Text(w.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedWorker = v),
                validator: (v) => v == null ? 'العامل مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            mixers.when(
              data: (list) => DropdownButtonFormField<MixerModel>(
                value: _selectedMixer,
                decoration: const InputDecoration(labelText: '${AppStrings.mixer} *'),
                isExpanded: true,
                items: list
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMixer = v),
                validator: (v) => v == null ? 'الخلاط مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            products.when(
              data: (list) => DropdownButtonFormField<ProductModel>(
                value: _selectedProduct,
                decoration: const InputDecoration(labelText: '${AppStrings.product} *'),
                isExpanded: true,
                items: list
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProduct = v),
                validator: (v) => v == null ? 'المنتج مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            mixtureTypes.when(
              data: (list) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<MixtureTypeModel>(
                    value: _selectedMixtureType,
                    decoration: InputDecoration(
                      labelText: '${AppStrings.mixtureType} *',
                      suffixIcon: _loadingRecipe
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : _recipeApplied
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                    ),
                    isExpanded: true,
                    items: list
                        .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedMixtureType = v;
                        _recipeApplied = false;
                      });
                      if (v != null) _applyRecipe(v);
                    },
                    validator: (v) => v == null ? 'نوع الخلطة مطلوب' : null,
                  ),
                  if (_recipeApplied)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      child: Text(
                        'تم تطبيق الوصفة القياسية — يمكنك تعديل أي قيمة',
                        style: TextStyle(
                            fontSize: 11, color: Colors.green.shade700),
                      ),
                    ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 20),

            // ── المواد الخام — تُبنى ديناميكياً من قائمة raw_materials ──────
            rawMaterials.when(
              data: (mats) => _buildMaterialSections(mats, mixerBal),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('تعذّر تحميل قائمة المواد الخام: $e',
                    style: const TextStyle(color: Colors.red)),
              ),
            ),

            const SizedBox(height: 20),

            // ── ملاحظات وصورة الميزان ─────────────────────────
            _SectionHeader(title: 'ملاحظات وصورة الميزان', icon: Icons.notes),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: AppStrings.notes,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _scaleImage == null ? Colors.grey : Colors.green,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _scaleImage == null
                  ? ListTile(
                      leading: const Icon(Icons.camera_alt, color: Colors.grey),
                      title: const Text('صورة الميزان (اختياري)'),
                      subtitle: const Text('اضغط لالتقاط صورة الميزان'),
                      onTap: _pickImage,
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _scaleImage!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _scaleImage = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: opsState.isLoading ? null : _submit,
                icon: opsState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text(AppStrings.saveAndSend,
                    style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── يبني قسماً لكل فئة مواد (مواد أساسية / أصباغ / إضافات / ...) ─────────
  Widget _buildMaterialSections(
      List<RawMaterialModel> mats, Map<String, _BalInfo> mixerBal) {
    if (mats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('لا توجد مواد خام مُعرّفة بعد — أضفها من شاشة إدارة المواد.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    // تجميع حسب الفئة مع الحفاظ على ترتيب معروف، ثم أي فئات إضافية أبجدياً
    final Map<String, List<RawMaterialModel>> grouped = {};
    for (final m in mats) {
      final cat = m.category.trim().isEmpty ? 'أخرى' : m.category.trim();
      grouped.putIfAbsent(cat, () => []).add(m);
    }
    final orderedCategories = <String>[
      ..._kCategoryOrder.where(grouped.containsKey),
      ...grouped.keys.where((c) => !_kCategoryOrder.contains(c)).toList()
        ..sort(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in orderedCategories) ...[
          _SectionHeader(title: cat, icon: _iconForCategory(cat)),
          const SizedBox(height: 12),
          for (final m in grouped[cat]!)
            _MatRow(
              label: m.name,
              ctrl: _ctrlFor(m.id),
              unit: m.unit,
              balance: mixerBal[m.id],
            ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

// ── Section Header ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
              color: Theme.of(context).primaryColor.withOpacity(0.3)),
        ),
      ],
    );
  }
}

// ── Material Row (dynamic label + qty input + mixer balance) ────────
class _MatRow extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String unit;

  /// رصيد مخزن الخلاط — null تعني المادة غير موجودة في مخزن الخلاط
  final _BalInfo? balance;

  const _MatRow({
    required this.label,
    required this.ctrl,
    this.unit = 'كجم',
    this.balance,
  });

  // ── بناء نص العرض للرصيد ────────────────────────────────────────────────
  String _buildBalText(double bal, String rawUnit) {
    return 'متاح: ${Helpers.formatQuantityInKg(bal, rawUnit)}';
  }

  @override
  Widget build(BuildContext context) {
    final info = balance;
    final hasBalance = info != null;
    final isEmpty = hasBalance && info.balance <= 0;
    final balColor =
        isEmpty ? Colors.red.shade600 : Colors.teal.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── اسم المادة + رصيد متاح ─────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13)),
                if (hasBalance) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isEmpty
                            ? Icons.warning_amber_rounded
                            : Icons.inventory_2_outlined,
                        size: 11,
                        color: balColor,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          _buildBalText(info.balance, info.unit),
                          style: TextStyle(
                              fontSize: 11,
                              color: balColor,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── حقل الإدخال ─────────────────────────────────────
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                suffixText: unit,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
