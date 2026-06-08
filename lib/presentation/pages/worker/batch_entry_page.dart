import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/reference_data_provider.dart';
import '../../providers/batch_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/reference_models.dart';
import '../../../data/datasources/supabase_datasource.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class BatchEntryPage extends ConsumerStatefulWidget {
  const BatchEntryPage({super.key});

  @override
  ConsumerState<BatchEntryPage> createState() => _BatchEntryPageState();
}

class _BatchEntryPageState extends ConsumerState<BatchEntryPage> {
  final _formKey = GlobalKey<FormState>();

  final _batchNumberCtrl = TextEditingController();
  final _pvcCtrl = TextEditingController();
  final _dopCtrl = TextEditingController();
  final _scrapCtrl = TextEditingController();
  final _calciumCtrl = TextEditingController();
  final _waxCtrl = TextEditingController();
  final _stabilizerCtrl = TextEditingController();
  final _titaniumCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedShift;
  WorkerModel? _selectedWorker;
  MixerModel? _selectedMixer;
  ProductModel? _selectedProduct;
  MixtureTypeModel? _selectedMixtureType;
  File? _scaleImage;

  // Dynamic pigment/additive rows
  final List<Map<String, dynamic>> _pigmentRows = [];
  final List<Map<String, dynamic>> _additiveRows = [];

  @override
  void dispose() {
    _batchNumberCtrl.dispose();
    _pvcCtrl.dispose();
    _dopCtrl.dispose();
    _scrapCtrl.dispose();
    _calciumCtrl.dispose();
    _waxCtrl.dispose();
    _stabilizerCtrl.dispose();
    _titaniumCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
    if (_scaleImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.scaleImageRequired),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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

    // Upload image
    String? imageUrl;
    try {
      final bytes = await _scaleImage!.readAsBytes();
      final ds = ref.read(dataSourceProvider);
      imageUrl = await ds.uploadImage(
        'batch-images',
        'scale/${_batchNumberCtrl.text}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes,
      );
    } catch (_) {}

    // Build materials list
    final materials = <Map<String, dynamic>>[];
    void addMat(String ctrl, String name) {
      final qty = double.tryParse(ctrl) ?? 0;
      if (qty > 0) {
        materials.add({'material_name': name, 'quantity': qty, 'unit': 'كجم'});
      }
    }

    addMat(_pvcCtrl.text, 'PVC');
    addMat(_dopCtrl.text, 'DOP زيت');
    addMat(_scrapCtrl.text, 'سكراب');
    addMat(_calciumCtrl.text, 'كالسيوم');
    addMat(_waxCtrl.text, 'شمع');
    addMat(_stabilizerCtrl.text, 'مثبت');
    addMat(_titaniumCtrl.text, 'تيتانيوم');

    for (final p in _pigmentRows) {
      final qty = double.tryParse((p['qty'] as TextEditingController).text) ?? 0;
      if (qty > 0 && p['name'] != null) {
        materials.add({'material_name': p['name'], 'quantity': qty, 'unit': 'كجم'});
      }
    }

    final batchData = {
      'batch_number': _batchNumberCtrl.text.trim(),
      'date': _selectedDate.toIso8601String().split('T').first,
      'shift': _selectedShift,
      'worker_id': _selectedWorker!.id,
      'worker_name': _selectedWorker!.name,
      'mixer_id': _selectedMixer!.id,
      'mixer_name': _selectedMixer!.name,
      'product_id': _selectedProduct!.id,
      'product_name': _selectedProduct!.name,
      'mixture_type_id': _selectedMixtureType!.id,
      'mixture_type_name': _selectedMixtureType!.name,
      'pvc_qty': double.tryParse(_pvcCtrl.text) ?? 0,
      'dop_qty': double.tryParse(_dopCtrl.text) ?? 0,
      'scrap_qty': double.tryParse(_scrapCtrl.text) ?? 0,
      'calcium_qty': double.tryParse(_calciumCtrl.text) ?? 0,
      'wax_qty': double.tryParse(_waxCtrl.text) ?? 0,
      'stabilizer_qty': double.tryParse(_stabilizerCtrl.text) ?? 0,
      'titanium_qty': double.tryParse(_titaniumCtrl.text) ?? 0,
      'pigments': _pigmentRows
          .map((p) => {
                'name': p['name'],
                'quantity': double.tryParse((p['qty'] as TextEditingController).text) ?? 0,
              })
          .toList(),
      'additives': _additiveRows
          .map((a) => {
                'name': a['name'],
                'quantity': double.tryParse((a['qty'] as TextEditingController).text) ?? 0,
              })
          .toList(),
      'notes': _notesCtrl.text.trim(),
      'scale_image_url': imageUrl,
      'materials': materials,
    };

    final result = await ref.read(batchOperationsProvider.notifier).saveBatch(batchData);

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.saveSuccess),
          backgroundColor: Colors.green,
        ),
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
    _batchNumberCtrl.clear();
    _pvcCtrl.clear();
    _dopCtrl.clear();
    _scrapCtrl.clear();
    _calciumCtrl.clear();
    _waxCtrl.clear();
    _stabilizerCtrl.clear();
    _titaniumCtrl.clear();
    _notesCtrl.clear();
    setState(() {
      _selectedDate = DateTime.now();
      _selectedShift = null;
      _selectedWorker = null;
      _selectedMixer = null;
      _selectedProduct = null;
      _selectedMixtureType = null;
      _scaleImage = null;
      _pigmentRows.clear();
      _additiveRows.clear();
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'معلومات الطبخة', icon: Icons.info_outline),
            const SizedBox(height: 12),

            // Batch Number
            CustomTextField(
              label: AppStrings.batchNumber,
              controller: _batchNumberCtrl,
              required: true,
            ),
            const SizedBox(height: 12),

            // Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: AppStrings.date,
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Shift
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

            // Worker
            workers.when(
              data: (list) => DropdownButtonFormField<WorkerModel>(
                value: _selectedWorker,
                decoration: const InputDecoration(labelText: '${AppStrings.worker} *'),
                isExpanded: true,
                items: list.map((w) => DropdownMenuItem(value: w, child: Text(w.name))).toList(),
                onChanged: (v) => setState(() => _selectedWorker = v),
                validator: (v) => v == null ? 'العامل مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // Mixer
            mixers.when(
              data: (list) => DropdownButtonFormField<MixerModel>(
                value: _selectedMixer,
                decoration: const InputDecoration(labelText: '${AppStrings.mixer} *'),
                isExpanded: true,
                items: list.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: (v) => setState(() => _selectedMixer = v),
                validator: (v) => v == null ? 'الخلاط مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // Product
            products.when(
              data: (list) => DropdownButtonFormField<ProductModel>(
                value: _selectedProduct,
                decoration: const InputDecoration(labelText: '${AppStrings.product} *'),
                isExpanded: true,
                items: list.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                onChanged: (v) => setState(() => _selectedProduct = v),
                validator: (v) => v == null ? 'المنتج مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // Mixture Type
            mixtureTypes.when(
              data: (list) => DropdownButtonFormField<MixtureTypeModel>(
                value: _selectedMixtureType,
                decoration: const InputDecoration(labelText: '${AppStrings.mixtureType} *'),
                isExpanded: true,
                items: list.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: (v) => setState(() => _selectedMixtureType = v),
                validator: (v) => v == null ? 'نوع الخلطة مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 20),

            _SectionHeader(title: 'المواد الخام (كجم)', icon: Icons.inventory_2_outlined),
            const SizedBox(height: 12),

            _MaterialRow(label: AppStrings.pvc, controller: _pvcCtrl),
            _MaterialRow(label: AppStrings.dop, controller: _dopCtrl),
            _MaterialRow(label: AppStrings.scrap, controller: _scrapCtrl),
            _MaterialRow(label: AppStrings.calcium, controller: _calciumCtrl),
            _MaterialRow(label: AppStrings.wax, controller: _waxCtrl),
            _MaterialRow(label: AppStrings.stabilizer, controller: _stabilizerCtrl),
            _MaterialRow(label: AppStrings.titanium, controller: _titaniumCtrl),

            const SizedBox(height: 16),
            _SectionHeader(title: 'الأصباغ', icon: Icons.color_lens_outlined),
            const SizedBox(height: 8),

            ..._pigmentRows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return rawMaterials.when(
                data: (mats) {
                  final pigments = mats.where((m) => m.category == 'أصباغ').toList();
                  return _DynamicMaterialRow(
                    index: i,
                    options: pigments.map((p) => p.name).toList(),
                    selectedName: row['name'] as String?,
                    qtyController: row['qty'] as TextEditingController,
                    onNameChanged: (v) => setState(() => _pigmentRows[i]['name'] = v),
                    onRemove: () => setState(() {
                      (row['qty'] as TextEditingController).dispose();
                      _pigmentRows.removeAt(i);
                    }),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => const SizedBox.shrink(),
              );
            }),

            TextButton.icon(
              onPressed: () => setState(() {
                _pigmentRows.add({'name': null, 'qty': TextEditingController()});
              }),
              icon: const Icon(Icons.add),
              label: const Text('إضافة صبغة'),
            ),

            const SizedBox(height: 16),
            _SectionHeader(title: 'إضافات أخرى', icon: Icons.add_circle_outline),
            const SizedBox(height: 8),

            ..._additiveRows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return _DynamicMaterialRow(
                index: i,
                options: const [],
                selectedName: row['name'] as String?,
                qtyController: row['qty'] as TextEditingController,
                onNameChanged: (v) => setState(() => _additiveRows[i]['name'] = v),
                onRemove: () => setState(() {
                  (row['qty'] as TextEditingController).dispose();
                  _additiveRows.removeAt(i);
                }),
                freeText: true,
              );
            }),

            TextButton.icon(
              onPressed: () => setState(() {
                _additiveRows.add({'name': null, 'qty': TextEditingController()});
              }),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مادة'),
            ),

            const SizedBox(height: 20),
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

            // Scale image
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _scaleImage == null ? Colors.red : Colors.green,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _scaleImage == null
                  ? ListTile(
                      leading: const Icon(Icons.camera_alt, color: Colors.red),
                      title: const Text('${AppStrings.scaleImage} *'),
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
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
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
                              child: const Icon(Icons.delete, color: Colors.white, size: 20),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text(AppStrings.saveAndSend, style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

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
        Expanded(child: Divider(color: Theme.of(context).primaryColor.withOpacity(0.3))),
      ],
    );
  }
}

class _MaterialRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _MaterialRow({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                suffixText: 'كجم',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DynamicMaterialRow extends StatelessWidget {
  final int index;
  final List<String> options;
  final String? selectedName;
  final TextEditingController qtyController;
  final void Function(String?) onNameChanged;
  final VoidCallback onRemove;
  final bool freeText;

  const _DynamicMaterialRow({
    required this.index,
    required this.options,
    required this.selectedName,
    required this.qtyController,
    required this.onNameChanged,
    required this.onRemove,
    this.freeText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: freeText
                ? TextFormField(
                    initialValue: selectedName,
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: onNameChanged,
                  )
                : DropdownButtonFormField<String>(
                    value: selectedName,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الصبغة',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: options
                        .map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: onNameChanged,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                suffixText: 'كجم',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
