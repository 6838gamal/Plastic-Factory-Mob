import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/reference_data_provider.dart';
import '../../providers/batch_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/reference_models.dart';
import '../../../data/datasources/api_datasource.dart';
import '../../providers/auth_provider.dart';

class BatchEntryPage extends ConsumerStatefulWidget {
  const BatchEntryPage({super.key});

  @override
  ConsumerState<BatchEntryPage> createState() => _BatchEntryPageState();
}

class _BatchEntryPageState extends ConsumerState<BatchEntryPage> {
  final _formKey = GlobalKey<FormState>();

  final _batchNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ── المواد الرئيسية ─────────────────────────────────────────
  final _pvcCtrl             = TextEditingController();
  final _dopCtrl             = TextEditingController();
  final _scrapBlackCtrl      = TextEditingController(); // سكراب اسود ناعم
  final _scrapBlueCtrl       = TextEditingController(); // سكراب ازرق ناعم
  final _scrapBlueSugarCtrl  = TextEditingController(); // سكراب ازرق سكري
  final _calciumCtrl         = TextEditingController();
  final _waxCtrl             = TextEditingController();
  final _stabilizerCtrl      = TextEditingController();
  final _titaniumCtrl        = TextEditingController();
  final _citricAcidCtrl      = TextEditingController(); // سيتريك اسيد
  final _bicarYellowCtrl     = TextEditingController(); // بيكربونات اصفر
  final _bicarWhiteCtrl      = TextEditingController(); // بيكربونات ابيض

  // ── الأصباغ (ثابتة) ─────────────────────────────────────────
  final _pig1Ctrl  = TextEditingController(); // صبغة سوداء باودر
  final _pig2Ctrl  = TextEditingController(); // صبغة زرقاء باودر رقم-١٠٢٧
  final _pig3Ctrl  = TextEditingController(); // صبغة زرقاء فاتح رقم-١٢٥٦
  final _pig4Ctrl  = TextEditingController(); // صبغة ارجواني رقم-F٤٠٩
  final _pig5Ctrl  = TextEditingController(); // صبغة احمر زهري رقم-F٣٥٨
  final _pig6Ctrl  = TextEditingController(); // صبغة كاكي بيج رقم-١٠٣٥
  final _pig7Ctrl  = TextEditingController(); // صبغه خضراء طاووس محلي
  final _pig8Ctrl  = TextEditingController(); // صبغه برتقالي محلي
  final _pig9Ctrl  = TextEditingController(); // صبغه زرقاء طاووس محلي
  final _pig10Ctrl = TextEditingController(); // صبغه سوداء طاووس محلي

  // ── إضافات أخرى (ثابتة) ─────────────────────────────────────
  final _add1Ctrl = TextEditingController(); // لواصق موديل ۷۰۳
  final _add2Ctrl = TextEditingController(); // لواصق موديل ۸۰۳۱-٦٠٣١
  final _add3Ctrl = TextEditingController(); // لواصق موديل ٦٠٢٦-٨٠٢٦
  final _add4Ctrl = TextEditingController(); // لواصق موديل ٦٠٢٢-٨٠٢٢
  final _add5Ctrl = TextEditingController(); // خلطه ازرق
  final _add6Ctrl = TextEditingController(); // راجع مكينه ازرق

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
    _pvcCtrl.dispose();
    _dopCtrl.dispose();
    _scrapBlackCtrl.dispose();
    _scrapBlueCtrl.dispose();
    _scrapBlueSugarCtrl.dispose();
    _calciumCtrl.dispose();
    _waxCtrl.dispose();
    _stabilizerCtrl.dispose();
    _titaniumCtrl.dispose();
    _citricAcidCtrl.dispose();
    _bicarYellowCtrl.dispose();
    _bicarWhiteCtrl.dispose();
    _pig1Ctrl.dispose();  _pig2Ctrl.dispose();  _pig3Ctrl.dispose();
    _pig4Ctrl.dispose();  _pig5Ctrl.dispose();  _pig6Ctrl.dispose();
    _pig7Ctrl.dispose();  _pig8Ctrl.dispose();  _pig9Ctrl.dispose();
    _pig10Ctrl.dispose();
    _add1Ctrl.dispose();  _add2Ctrl.dispose();  _add3Ctrl.dispose();
    _add4Ctrl.dispose();  _add5Ctrl.dispose();  _add6Ctrl.dispose();
    super.dispose();
  }

  // ── خريطة الحقول الثابتة بالاسم الكامل ────────────────────────
  Map<String, TextEditingController> get _fieldByName => {
    'مواد خام PVC صيني':                         _pvcCtrl,
    'DOP زيت':                                    _dopCtrl,
    'سكراب اسود ناعم':                            _scrapBlackCtrl,
    'سكراب ازرق ناعم':                            _scrapBlueCtrl,
    'سكراب ازرق سكري':                            _scrapBlueSugarCtrl,
    'كالسيوم باودر عبوة 25 كيلو':                 _calciumCtrl,
    'شمع باودر عبوة 25 كيلو':                     _waxCtrl,
    'مثبت استبليزر باودر عبوة 25 كيلو':           _stabilizerCtrl,
    'تيتانيوم':                                   _titaniumCtrl,
    'سيتريك اسيد (ملح الليمون) 490 عبوة 25 كجم': _citricAcidCtrl,
    'بيكربونات اصفر محلي':                        _bicarYellowCtrl,
    'بيكربونات ابيض محلي':                        _bicarWhiteCtrl,
    'صبغة سوداء باودر عبوة 10 كيلو':             _pig1Ctrl,
    'صبغة زرقاء باودر عبوة 20 كيلو رقم-١٠٢٧':    _pig2Ctrl,
    'صبغة زرقاء فاتح عبوة 20 كيلو رقم-١٢٥٦':     _pig3Ctrl,
    'صبغة ارجواني عبوة 25 كيلو رقم-F٤٠٩':        _pig4Ctrl,
    'صبغة احمر زهري عبوة 25 كيلو رقم-F٣٥٨':      _pig5Ctrl,
    'صبغة كاكي بيج عبوة 25 كيلو رقم-١٠٣٥':       _pig6Ctrl,
    'صبغه خضراء طاووس محلي':                     _pig7Ctrl,
    'صبغه برتقالي محلي':                         _pig8Ctrl,
    'صبغه زرقاء طاووس محلي':                     _pig9Ctrl,
    'صبغه سوداء طاووس محلي':                     _pig10Ctrl,
    'لواصق موديل ۷۰۳ بالحبه':                    _add1Ctrl,
    'لواصق موديل ۸۰۳۱-٦٠٣١ بالحبه':             _add2Ctrl,
    'لواصق موديل ٦٠٢٦-٨٠٢٦ بالحبه':             _add3Ctrl,
    'لواصق موديل ٦٠٢٢-٨٠٢٢ بالحبه':             _add4Ctrl,
    'خلطه ازرق':                                  _add5Ctrl,
    'راجع مكينه ازرق':                            _add6Ctrl,
  };

  Future<void> _applyRecipe(MixtureTypeModel mixtureType) async {
    setState(() { _loadingRecipe = true; _recipeApplied = false; });
    try {
      final ds = ref.read(dataSourceProvider);
      final recipe = await ds.getRecipeByMixtureType(mixtureType.id);
      if (recipe == null || !mounted) return;
      final qtyMap = recipe.qtyMap;
      final fieldMap = _fieldByName;
      bool anyFilled = false;
      for (final entry in qtyMap.entries) {
        final ctrl = fieldMap[entry.key];
        if (ctrl != null && entry.value > 0) {
          final qty = entry.value;
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

  double _kg(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double _gToKg(TextEditingController c) {
    final g = double.tryParse(c.text.trim()) ?? 0;
    return g / 1000.0;
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

    // ── مجموع السكراب للحقل المخصص ─────────────────────────
    final totalScrap = _kg(_scrapBlackCtrl) + _kg(_scrapBlueCtrl) + _kg(_scrapBlueSugarCtrl);

    // ── قائمة الأصباغ ─────────────────────────────────────────
    final pigmentDefs = [
      ('صبغة سوداء باودر عبوة 10 كيلو',           _pig1Ctrl,  'جرام'),
      ('صبغة زرقاء باودر عبوة 20 كيلو رقم-١٠٢٧',  _pig2Ctrl,  'جرام'),
      ('صبغة زرقاء فاتح عبوة 20 كيلو رقم-١٢٥٦',   _pig3Ctrl,  'جرام'),
      ('صبغة ارجواني عبوة 25 كيلو رقم-F٤٠٩',       _pig4Ctrl,  'جرام'),
      ('صبغة احمر زهري عبوة 25 كيلو رقم-F٣٥٨',     _pig5Ctrl,  'جرام'),
      ('صبغة كاكي بيج عبوة 25 كيلو رقم-١٠٣٥',      _pig6Ctrl,  'جرام'),
      ('صبغه خضراء طاووس محلي',                     _pig7Ctrl,  'جرام'),
      ('صبغه برتقالي محلي',                         _pig8Ctrl,  'جرام'),
      ('صبغه زرقاء طاووس محلي',                     _pig9Ctrl,  'جرام'),
      ('صبغه سوداء طاووس محلي',                     _pig10Ctrl, 'جرام'),
    ];

    // ── قائمة الإضافات ─────────────────────────────────────────
    final additiveDefs = [
      ('لواصق موديل ۷۰۳ بالحبه',        _add1Ctrl, 'قطعة'),
      ('لواصق موديل ۸۰۳۱-٦٠٣١ بالحبه', _add2Ctrl, 'قطعة'),
      ('لواصق موديل ٦٠٢٦-٨٠٢٦ بالحبه', _add3Ctrl, 'قطعة'),
      ('لواصق موديل ٦٠٢٢-٨٠٢٢ بالحبه', _add4Ctrl, 'قطعة'),
      ('خلطه ازرق',                      _add5Ctrl, 'كجم'),
      ('راجع مكينه ازرق',                _add6Ctrl, 'كجم'),
    ];

    // ── بناء قائمة المواد للخصم من المخزن ──────────────────────
    final materials = <Map<String, dynamic>>[];

    void addKg(String name, TextEditingController c) {
      final qty = _kg(c);
      if (qty > 0) materials.add({'material_name': name, 'quantity': qty, 'unit': 'كجم'});
    }

    addKg('مواد خام pvc صيني', _pvcCtrl);
    addKg('DOP زيت', _dopCtrl);
    if (_kg(_scrapBlackCtrl) > 0)
      materials.add({'material_name': 'سكراب اسود ناعم', 'quantity': _kg(_scrapBlackCtrl), 'unit': 'كجم'});
    if (_kg(_scrapBlueCtrl) > 0)
      materials.add({'material_name': 'سكراب ازرق ناعم', 'quantity': _kg(_scrapBlueCtrl), 'unit': 'كجم'});
    if (_kg(_scrapBlueSugarCtrl) > 0)
      materials.add({'material_name': 'سكراب ازرق سكري', 'quantity': _kg(_scrapBlueSugarCtrl), 'unit': 'كجم'});
    addKg('كالسيوم باودر عبوة 25 كيلو', _calciumCtrl);
    addKg('شمع باودر عبوة 25 كيلو', _waxCtrl);
    addKg('مثبت استبليزر باودر عبوة 25 كيلو', _stabilizerCtrl);
    addKg('تيتانيوم', _titaniumCtrl);
    addKg('سيتريك اسيد - ملح الليمون - 490 عبوة 25 كجم', _citricAcidCtrl);
    addKg('بيكربونات اصفر محلي', _bicarYellowCtrl);
    addKg('بيكربونات ابيض محلي', _bicarWhiteCtrl);

    // الأصباغ — القيم بالجرام تُحوّل لكجم عند الخصم
    final pigmentsList = <Map<String, dynamic>>[];
    for (final (name, ctrl, unit) in pigmentDefs) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0;
      if (val > 0) {
        pigmentsList.add({'name': name, 'quantity': val, 'unit': unit});
        materials.add({'material_name': name, 'quantity': val, 'unit': unit});
      }
    }

    // الإضافات الأخرى
    final additivesList = <Map<String, dynamic>>[];
    for (final (name, ctrl, unit) in additiveDefs) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0;
      if (val > 0) {
        additivesList.add({'name': name, 'quantity': val, 'unit': unit});
        materials.add({'material_name': name, 'quantity': val, 'unit': unit});
      }
    }

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
      'pvc_qty':           _kg(_pvcCtrl),
      'dop_qty':           _kg(_dopCtrl),
      'scrap_qty':         totalScrap,
      'calcium_qty':       _kg(_calciumCtrl),
      'wax_qty':           _kg(_waxCtrl),
      'stabilizer_qty':    _kg(_stabilizerCtrl),
      'titanium_qty':      _kg(_titaniumCtrl),
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
    for (final c in [
      _notesCtrl, _pvcCtrl, _dopCtrl, _scrapBlackCtrl, _scrapBlueCtrl,
      _scrapBlueSugarCtrl, _calciumCtrl, _waxCtrl, _stabilizerCtrl, _titaniumCtrl,
      _citricAcidCtrl, _bicarYellowCtrl, _bicarWhiteCtrl,
      _pig1Ctrl, _pig2Ctrl, _pig3Ctrl, _pig4Ctrl, _pig5Ctrl,
      _pig6Ctrl, _pig7Ctrl, _pig8Ctrl, _pig9Ctrl, _pig10Ctrl,
      _add1Ctrl, _add2Ctrl, _add3Ctrl, _add4Ctrl, _add5Ctrl, _add6Ctrl,
    ]) {
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
    final opsState = ref.watch(batchOperationsProvider);

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

            // ── المواد الخام ─────────────────────────────────────
            _SectionHeader(title: 'المواد الخام', icon: Icons.inventory_2_outlined),
            const SizedBox(height: 12),

            _MatRow(label: 'مواد خام PVC صيني',                    ctrl: _pvcCtrl),
            _MatRow(label: 'DOP زيت',                               ctrl: _dopCtrl),
            _MatRow(label: 'سكراب اسود ناعم',                       ctrl: _scrapBlackCtrl),
            _MatRow(label: 'سكراب ازرق ناعم',                       ctrl: _scrapBlueCtrl),
            _MatRow(label: 'سكراب ازرق سكري',                       ctrl: _scrapBlueSugarCtrl),
            _MatRow(label: 'كالسيوم باودر عبوة 25 كيلو',            ctrl: _calciumCtrl),
            _MatRow(label: 'شمع باودر عبوة 25 كيلو',                ctrl: _waxCtrl),
            _MatRow(label: 'مثبت استبليزر باودر عبوة 25 كيلو',      ctrl: _stabilizerCtrl),
            _MatRow(label: 'تيتانيوم',                              ctrl: _titaniumCtrl),
            _MatRow(label: 'سيتريك اسيد (ملح الليمون) 490 عبوة 25 كجم', ctrl: _citricAcidCtrl),
            _MatRow(label: 'بيكربونات اصفر محلي',                   ctrl: _bicarYellowCtrl),
            _MatRow(label: 'بيكربونات ابيض محلي',                   ctrl: _bicarWhiteCtrl),

            const SizedBox(height: 20),

            // ── الأصباغ ──────────────────────────────────────────
            _SectionHeader(title: 'الأصباغ', icon: Icons.color_lens_outlined),
            const SizedBox(height: 12),

            _MatRow(label: 'صبغة سوداء باودر عبوة 10 كيلو',          ctrl: _pig1Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغة زرقاء باودر عبوة 20 كيلو رقم-١٠٢٧', ctrl: _pig2Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغة زرقاء فاتح عبوة 20 كيلو رقم-١٢٥٦',  ctrl: _pig3Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغة ارجواني عبوة 25 كيلو رقم-F٤٠٩',      ctrl: _pig4Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغة احمر زهري عبوة 25 كيلو رقم-F٣٥٨',    ctrl: _pig5Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغة كاكي بيج عبوة 25 كيلو رقم-١٠٣٥',     ctrl: _pig6Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغه خضراء طاووس محلي',                   ctrl: _pig7Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغه برتقالي محلي',                       ctrl: _pig8Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغه زرقاء طاووس محلي',                   ctrl: _pig9Ctrl,  unit: 'جرام'),
            _MatRow(label: 'صبغه سوداء طاووس محلي',                   ctrl: _pig10Ctrl, unit: 'جرام'),

            const SizedBox(height: 20),

            // ── إضافات أخرى ─────────────────────────────────────
            _SectionHeader(title: 'إضافات أخرى', icon: Icons.add_circle_outline),
            const SizedBox(height: 12),

            _MatRow(label: 'لواصق موديل ۷۰۳ بالحبه',        ctrl: _add1Ctrl, unit: 'قطعة'),
            _MatRow(label: 'لواصق موديل ۸۰۳۱-٦٠٣١ بالحبه', ctrl: _add2Ctrl, unit: 'قطعة'),
            _MatRow(label: 'لواصق موديل ٦٠٢٦-٨٠٢٦ بالحبه', ctrl: _add3Ctrl, unit: 'قطعة'),
            _MatRow(label: 'لواصق موديل ٦٠٢٢-٨٠٢٢ بالحبه', ctrl: _add4Ctrl, unit: 'قطعة'),
            _MatRow(label: 'خلطه ازرق',                      ctrl: _add5Ctrl),
            _MatRow(label: 'راجع مكينه ازرق',                ctrl: _add6Ctrl),

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

// ── Material Row (fixed label + qty input) ─────────────────────
class _MatRow extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String unit;

  const _MatRow({
    required this.label,
    required this.ctrl,
    this.unit = 'كجم',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          const SizedBox(width: 8),
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
