import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/reference_data_provider.dart';
import '../../providers/batch_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/reference_models.dart';
import '../../../data/datasources/api_datasource.dart';

class MachineEntryPage extends ConsumerStatefulWidget {
  const MachineEntryPage({super.key});

  @override
  ConsumerState<MachineEntryPage> createState() => _MachineEntryPageState();
}

class _MachineEntryPageState extends ConsumerState<MachineEntryPage> {
  final _formKey = GlobalKey<FormState>();
  final _batchNumberCtrl = TextEditingController();
  final _producedQtyCtrl = TextEditingController();
  final _scrapQtyCtrl = TextEditingController();
  final _wasteQtyCtrl = TextEditingController();
  final _stopTimeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  MachineModel? _selectedMachine;
  ProductModel? _selectedProduct;
  File? _productionImage;

  // Recent batch numbers for autocomplete
  List<String> _recentBatchNumbers = [];
  bool _loadingBatchNums = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecentBatchNumbers());
  }

  Future<void> _loadRecentBatchNumbers() async {
    if (!mounted) return;
    setState(() => _loadingBatchNums = true);
    try {
      final ds = ref.read(dataSourceProvider);
      final nums = await ds.getRecentBatchNumbers();
      if (mounted) setState(() => _recentBatchNumbers = nums);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBatchNums = false);
    }
  }

  @override
  void dispose() {
    _batchNumberCtrl.dispose();
    _producedQtyCtrl.dispose();
    _scrapQtyCtrl.dispose();
    _wasteQtyCtrl.dispose();
    _stopTimeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _productionImage = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMachine == null || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الماكينة والمنتج'), backgroundColor: Colors.red),
      );
      return;
    }

    String? imageUrl;
    if (_productionImage != null) {
      try {
        final bytes = await _productionImage!.readAsBytes();
        final ds = ref.read(dataSourceProvider);
        imageUrl = await ds.uploadImage(
          'production-images',
          'production/${_batchNumberCtrl.text}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes,
        );
      } catch (_) {}
    }

    final data = {
      'batch_number': _batchNumberCtrl.text.trim(),
      'machine_id': _selectedMachine!.id,
      'machine_name': _selectedMachine!.name,
      'product_id': _selectedProduct!.id,
      'product_name': _selectedProduct!.name,
      'produced_quantity': double.tryParse(_producedQtyCtrl.text) ?? 0,
      'scrap_quantity': double.tryParse(_scrapQtyCtrl.text) ?? 0,
      'waste_quantity': double.tryParse(_wasteQtyCtrl.text) ?? 0,
      'stop_time_minutes': double.tryParse(_stopTimeCtrl.text) ?? 0,
      'notes': _notesCtrl.text.trim(),
      'production_image_url': imageUrl,
      'recorded_at': DateTime.now().toIso8601String(),
    };

    final result = await ref.read(batchOperationsProvider.notifier).saveProduction(data);
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
        ),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _batchNumberCtrl.clear();
    _producedQtyCtrl.clear();
    _scrapQtyCtrl.clear();
    _wasteQtyCtrl.clear();
    _stopTimeCtrl.clear();
    _notesCtrl.clear();
    setState(() {
      _selectedMachine = null;
      _selectedProduct = null;
      _productionImage = null;
    });
    _loadRecentBatchNumbers();
  }

  @override
  Widget build(BuildContext context) {
    final machines = ref.watch(machinesProvider);
    final products = ref.watch(productsProvider);
    final opsState = ref.watch(batchOperationsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('بيانات الإنتاج', Icons.precision_manufacturing),
            const SizedBox(height: 12),

            // ── Batch Number — autocomplete from saved batches ───────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رقم الطبخة *',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _batchNumberCtrl.text),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (_recentBatchNumbers.isEmpty) return const Iterable<String>.empty();
                    if (textEditingValue.text.isEmpty) return _recentBatchNumbers;
                    return _recentBatchNumbers.where((b) => b
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
                  },
                  onSelected: (String value) {
                    setState(() => _batchNumberCtrl.text = value);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    // Sync our controller text to autocomplete's controller
                    controller.text = _batchNumberCtrl.text;
                    controller.addListener(() {
                      _batchNumberCtrl.text = controller.text;
                    });
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: _loadingBatchNums
                            ? 'جاري تحميل الطبخات...'
                            : 'اكتب أو اختر رقم الطبخة',
                        prefixIcon: const Icon(Icons.tag),
                        suffixIcon: _loadingBatchNums
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh, size: 18),
                                tooltip: 'تحديث القائمة',
                                onPressed: _loadRecentBatchNumbers,
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'رقم الطبخة مطلوب' : null,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (_, i) {
                              final opt = options.elementAt(i);
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.blender_outlined, size: 18),
                                title: Text(opt),
                                onTap: () => onSelected(opt),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Machine dropdown ─────────────────────────────────────────
            machines.when(
              data: (list) => DropdownButtonFormField<MachineModel>(
                value: _selectedMachine,
                decoration: const InputDecoration(labelText: '${AppStrings.machine} *'),
                isExpanded: true,
                items: list.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: (v) => setState(() => _selectedMachine = v),
                validator: (v) => v == null ? 'الماكينة مطلوبة' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // ── Product dropdown ─────────────────────────────────────────
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
            const SizedBox(height: 20),

            _buildSection('الكميات (كجم)', Icons.scale_outlined),
            const SizedBox(height: 12),

            _buildQuantityRow(AppStrings.producedQuantity, _producedQtyCtrl, required: true),
            _buildQuantityRow(AppStrings.scrap, _scrapQtyCtrl),
            _buildQuantityRow(AppStrings.waste, _wasteQtyCtrl),

            const SizedBox(height: 12),
            TextFormField(
              controller: _stopTimeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'وقت الوقوف (دقيقة)',
                prefixIcon: Icon(Icons.timer_off_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // ── Production image ─────────────────────────────────────────
            _buildSection('صورة الإنتاج', Icons.camera_alt_outlined),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickImage,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _productionImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_productionImage!, fit: BoxFit.cover, width: double.infinity),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 36, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('اضغط لالتقاط صورة (اختياري)',
                              style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: AppStrings.notes,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 24),

            // ── Submit ───────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: opsState.isLoading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  opsState.isLoading ? 'جاري الحفظ...' : AppStrings.save,
                  style: const TextStyle(fontSize: 16),
                ),
                onPressed: opsState.isLoading ? null : _submit,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 18, color: Theme.of(context).primaryColor),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
    ]);
  }

  Widget _buildQuantityRow(String label, TextEditingController ctrl, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          suffixText: 'كجم',
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label مطلوب' : null
            : null,
      ),
    );
  }
}
