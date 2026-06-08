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

            TextFormField(
              controller: _batchNumberCtrl,
              decoration: const InputDecoration(labelText: '${AppStrings.batchNumber} *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'رقم الطبخة مطلوب' : null,
            ),
            const SizedBox(height: 12),

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
                labelText: AppStrings.stopTime,
                suffixText: 'دقيقة',
              ),
            ),

            const SizedBox(height: 20),
            _buildSection('ملاحظات وصورة', Icons.notes),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: AppStrings.notes,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _productionImage == null
                  ? ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text(AppStrings.productionImage),
                      subtitle: const Text('اضغط لالتقاط صورة الإنتاج (اختياري)'),
                      onTap: _pickImage,
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _productionImage!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _productionImage = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.delete, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 32),

            // Summary preview
            if (_producedQtyCtrl.text.isNotEmpty ||
                _scrapQtyCtrl.text.isNotEmpty ||
                _wasteQtyCtrl.text.isNotEmpty) ...[
              _buildSummaryCard(),
              const SizedBox(height: 16),
            ],

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

  Widget _buildSection(String title, IconData icon) {
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

  Widget _buildQuantityRow(String label, TextEditingController ctrl, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          suffixText: 'كجم',
        ),
        validator: required
            ? (v) {
                if (v == null || v.trim().isEmpty) return '$label مطلوب';
                if (double.tryParse(v) == null) return 'أدخل رقماً صحيحاً';
                return null;
              }
            : null,
      ),
    );
  }

  Widget _buildSummaryCard() {
    final produced = double.tryParse(_producedQtyCtrl.text) ?? 0;
    final scrap = double.tryParse(_scrapQtyCtrl.text) ?? 0;
    final waste = double.tryParse(_wasteQtyCtrl.text) ?? 0;
    final total = produced + scrap + waste;
    final efficiency = total > 0 ? (produced / total) * 100 : 0;

    return Card(
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ملخص الإنتاج', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
            const SizedBox(height: 8),
            _SummaryRow('الإنتاج', '${produced.toStringAsFixed(2)} كجم', Colors.green),
            _SummaryRow('السكراب', '${scrap.toStringAsFixed(2)} كجم', Colors.orange),
            _SummaryRow('الهالك', '${waste.toStringAsFixed(2)} كجم', Colors.red),
            const Divider(),
            _SummaryRow('الكفاءة', '${efficiency.toStringAsFixed(1)}%',
                efficiency >= 90 ? Colors.green : efficiency >= 75 ? Colors.orange : Colors.red),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
