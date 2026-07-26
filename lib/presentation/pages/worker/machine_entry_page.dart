import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../providers/reference_data_provider.dart';
import '../../providers/batch_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/reference_models.dart';
import '../../../data/models/production_standard_model.dart';
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
  final _pairsCtrl = TextEditingController();

  final List<MachineModel> _selectedMachines = [];
  ProductModel? _selectedProduct;
  ProductionStandardModel? _selectedStandard;
  File? _productionImage;

  // Recent batch numbers for autocomplete
  List<String> _recentBatchNumbers = [];
  bool _loadingBatchNums = false;

  @override
  void initState() {
    super.initState();
    // Listen to quantity fields to refresh waste indicator live
    _producedQtyCtrl.addListener(() => setState(() {}));
    _scrapQtyCtrl.addListener(() => setState(() {}));
    _wasteQtyCtrl.addListener(() => setState(() {}));
    _pairsCtrl.addListener(() => setState(() {}));
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
    _pairsCtrl.dispose();
    super.dispose();
  }

  // ── Yield stats (computed live from form values) ─────────────────
  YieldStats? get _yieldStats {
    final pairs = int.tryParse(_pairsCtrl.text.trim()) ?? 0;
    if (pairs <= 0 || _selectedStandard == null) return null;
    final totalKg = (double.tryParse(_producedQtyCtrl.text) ?? 0) +
        (double.tryParse(_scrapQtyCtrl.text) ?? 0) +
        (double.tryParse(_wasteQtyCtrl.text) ?? 0);
    if (totalKg <= 0) return null;
    final actualGram = (totalKg * 1000) / pairs;
    final standardGram = _selectedStandard!.standardGramPerPair;
    final deviation = ((actualGram - standardGram) / standardGram) * 100;
    return YieldStats(
      actualGramPerPair: actualGram,
      standardGramPerPair: standardGram,
      deviationPct: deviation,
      indicator: wasteIndicatorFromDeviation(deviation),
    );
  }

  // ── Auto-match standard when product is selected ─────────────────
  void _onProductSelected(ProductModel? product) {
    setState(() {
      _selectedProduct = product;
      _selectedStandard = null;
    });
    if (product == null) return;
    // Try to find a matching standard by product name
    final standards = ref.read(productionStandardsProvider).value ?? [];
    final match = standards.where((s) =>
        s.productName.toLowerCase() == product.name.toLowerCase()).firstOrNull;
    if (match != null && mounted) {
      setState(() => _selectedStandard = match);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _productionImage = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMachines.isEmpty || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ماكينة واحدة على الأقل والمنتج'), backgroundColor: Colors.red),
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

    final now = DateTime.now().toIso8601String();
    int successCount = 0;
    String? lastError;

    for (final machine in _selectedMachines) {
      final data = {
        'batch_number': _batchNumberCtrl.text.trim(),
        'machine_id': machine.id,
        'machine_name': machine.name,
        'product_id': _selectedProduct!.id,
        'product_name': _selectedProduct!.name,
        'produced_quantity': double.tryParse(_producedQtyCtrl.text) ?? 0,
        'scrap_quantity': double.tryParse(_scrapQtyCtrl.text) ?? 0,
        'waste_quantity': double.tryParse(_wasteQtyCtrl.text) ?? 0,
        'stop_time_minutes': double.tryParse(_stopTimeCtrl.text) ?? 0,
        'notes': _notesCtrl.text.trim(),
        'production_image_url': imageUrl,
        'recorded_at': now,
        'standard_id': _selectedStandard?.id,
        'pairs_produced': int.tryParse(_pairsCtrl.text.trim()) ?? 0,
      };
      final result = await ref.read(batchOperationsProvider.notifier).saveProduction(data);
      if (result.success) {
        successCount++;
      } else {
        lastError = result.error;
      }
    }

    if (!mounted) return;

    if (successCount == _selectedMachines.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedMachines.length == 1
                ? AppStrings.saveSuccess
                : 'تم الحفظ بنجاح لـ $successCount ماكينة',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _resetForm();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successCount > 0
                ? 'تم الحفظ لـ $successCount ماكينة، وفشل ${_selectedMachines.length - successCount} (${lastError ?? AppStrings.saveFailed})'
                : (lastError ?? AppStrings.saveFailed),
          ),
          backgroundColor: successCount > 0 ? Colors.orange : Colors.red,
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
    _pairsCtrl.clear();
    setState(() {
      _selectedMachines.clear();
      _selectedProduct = null;
      _selectedStandard = null;
      _productionImage = null;
    });
    _loadRecentBatchNumbers();
  }

  @override
  Widget build(BuildContext context) {
    final machines = ref.watch(machinesProvider);
    final products = ref.watch(productsProvider);
    final standards = ref.watch(productionStandardsProvider);
    final opsState = ref.watch(batchOperationsProvider);
    final stats = _yieldStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('بيانات الإنتاج', Icons.precision_manufacturing),
            const SizedBox(height: 12),

            // ── Batch Number ─────────────────────────────────────────
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

            // ── Machines (multi-select) ──────────────────────────────
            machines.when(
              data: (list) => _buildMachineMultiSelect(list),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // ── Product ──────────────────────────────────────────────
            products.when(
              data: (list) => DropdownButtonFormField<ProductModel>(
                value: _selectedProduct,
                decoration: const InputDecoration(labelText: '${AppStrings.product} *'),
                isExpanded: true,
                items: list.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                onChanged: _onProductSelected,
                validator: (v) => v == null ? 'المنتج مطلوب' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('خطأ: $e'),
            ),
            const SizedBox(height: 12),

            // ── Production Standard (required) ───────────────────────
            standards.when(
              data: (list) {
                if (list.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_outlined, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لا توجد معايير إنتاج مفعّلة — أضف معياراً أولاً من إدارة معايير الإنتاج',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ]),
                  );
                }
                return DropdownButtonFormField<ProductionStandardModel>(
                  value: _selectedStandard,
                  decoration: InputDecoration(
                    labelText: 'معيار الإنتاج *',
                    prefixIcon: const Icon(Icons.straighten, color: Colors.indigo),
                    helperText: _selectedStandard != null
                        ? 'المعيار: ${_selectedStandard!.standardGramPerPair.toStringAsFixed(0)} جرام/زوج'
                        : 'يجب اختيار معيار الإنتاج للصنف',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  isExpanded: true,
                  items: list.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                            '${s.productName} — ${s.standardGramPerPair.toStringAsFixed(0)} جم/زوج'),
                      )).toList(),
                  onChanged: (v) => setState(() => _selectedStandard = v),
                  validator: (v) => v == null ? 'معيار الإنتاج مطلوب' : null,
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            _buildSection('الكميات (كجم)', Icons.scale_outlined),
            const SizedBox(height: 12),

            _buildQuantityRow(AppStrings.producedQuantity, _producedQtyCtrl, required: true),
            _buildQuantityRow(AppStrings.scrap, _scrapQtyCtrl),
            _buildQuantityRow(AppStrings.waste, _wasteQtyCtrl),

            // ── Pairs Produced ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _pairsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'عدد الأزواج المنتجة *',
                  prefixIcon: Icon(Icons.people_outline),
                  suffixText: 'زوج',
                  helperText: 'مطلوب لحساب مؤشر الهدر والانحراف عن المعيار',
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'عدد الأزواج مطلوب ويجب أن يكون أكبر من صفر';
                  return null;
                },
              ),
            ),

            // ── Waste Indicator (live) ───────────────────────────────
            if (stats != null) ...[
              _WasteIndicatorCard(stats: stats),
              const SizedBox(height: 12),
            ] else if (_selectedStandard != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade500, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'أدخل الكميات وعدد الأزواج لحساب مؤشر الهدر',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 4),
            TextFormField(
              controller: _stopTimeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'وقت الوقوف (دقيقة)',
                prefixIcon: Icon(Icons.timer_off_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // ── Production image ─────────────────────────────────────
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

            // ── Submit ───────────────────────────────────────────────
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

  Widget _buildMachineMultiSelect(List<MachineModel> list) {
    final hasError = _selectedMachines.isEmpty;
    final borderColor = hasError ? Colors.red.shade300 : Colors.grey.shade400;
    final labelColor = hasError ? Colors.red : Colors.grey.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${AppStrings.machine} *',
              style: TextStyle(fontSize: 13, color: labelColor, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            if (_selectedMachines.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'تم اختيار ${_selectedMachines.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Spacer(),
            if (_selectedMachines.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _selectedMachines.clear()),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade50,
          ),
          child: list.isEmpty
              ? Text(
                  'لا توجد ماكينات — أضف ماكينات أولاً من الإدارة',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: list.map((machine) {
                    final selected = _selectedMachines.any((m) => m.id == machine.id);
                    return FilterChip(
                      label: Text(machine.name),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedMachines.add(machine);
                          } else {
                            _selectedMachines.removeWhere((m) => m.id == machine.id);
                          }
                        });
                      },
                      selectedColor: Theme.of(context).primaryColor.withOpacity(0.15),
                      checkmarkColor: Theme.of(context).primaryColor,
                      labelStyle: TextStyle(
                        color: selected ? Theme.of(context).primaryColor : Colors.grey.shade800,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: selected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (hasError && list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 12),
            child: Text(
              'يرجى اختيار ماكينة واحدة على الأقل',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
      ],
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

// ── Waste Indicator Card ───────────────────────────────────────────────────────

class _WasteIndicatorCard extends StatelessWidget {
  final YieldStats stats;
  const _WasteIndicatorCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final color = Color(stats.indicator.colorValue);
    final deviation = stats.deviationPct;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_indicatorIcon(stats.indicator), color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'مؤشر الهدر — ${stats.indicator.label}',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  deviation <= 0
                      ? '✓ ضمن المعيار'
                      : '+${deviation.toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'المعيار',
                  value:
                      '${stats.standardGramPerPair.toStringAsFixed(0)} جم/زوج',
                  color: Colors.grey.shade700,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'الفعلي',
                  value:
                      '${stats.actualGramPerPair.toStringAsFixed(0)} جم/زوج',
                  color: color,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'الفرق',
                  value:
                      '${(stats.actualGramPerPair - stats.standardGramPerPair).toStringAsFixed(0)} جم',
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _indicatorIcon(WasteIndicator ind) {
    switch (ind) {
      case WasteIndicator.normal:
        return Icons.check_circle_outline;
      case WasteIndicator.warning:
        return Icons.warning_amber_outlined;
      case WasteIndicator.critical:
        return Icons.error_outline;
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      ],
    );
  }
}
