import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/datasources/api_datasource.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';

class ShiftHandoverPage extends ConsumerStatefulWidget {
  const ShiftHandoverPage({super.key});

  @override
  ConsumerState<ShiftHandoverPage> createState() => _ShiftHandoverPageState();
}

class _ShiftHandoverPageState extends ConsumerState<ShiftHandoverPage> {
  final _formKey = GlobalKey<FormState>();

  final _supervisorCtrl  = TextEditingController();
  final _actualStockCtrl = TextEditingController();
  final _flashingCtrl    = TextEditingController(text: '0');
  final _rejectedCtrl    = TextEditingController(text: '0');
  final _wasteCtrl       = TextEditingController(text: '0');
  final _notesCtrl       = TextEditingController();

  String? _selectedShift;
  DateTime _selectedDate = DateTime.now();
  bool _loading = false;
  bool _loadingBalance = false;
  Map<String, dynamic>? _balanceInfo;
  Map<String, dynamic>? _result;

  ApiDataSource get _ds => ref.read(dataSourceProvider);

  @override
  void initState() {
    super.initState();
    _fetchExpectedBalance();
  }

  @override
  void dispose() {
    _supervisorCtrl.dispose();
    _actualStockCtrl.dispose();
    _flashingCtrl.dispose();
    _rejectedCtrl.dispose();
    _wasteCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExpectedBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final dateStr = _selectedDate.toIso8601String().substring(0, 10);
      final data = await _ds.getRaw(
        '/api/shift-handover/current-balance',
        query: {'handover_date': dateStr},
      );
      setState(() => _balanceInfo = data as Map<String, dynamic>?);
    } catch (_) {
      setState(() => _balanceInfo = null);
    } finally {
      setState(() => _loadingBalance = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShift == null) {
      _showError('يرجى اختيار الوردية');
      return;
    }

    setState(() { _loading = true; _result = null; });
    try {
      final body = {
        'shift_name': _selectedShift!,
        'supervisor_name': _supervisorCtrl.text.trim(),
        'handover_date': _selectedDate.toIso8601String().substring(0, 10),
        'flashing_kg': double.tryParse(_flashingCtrl.text) ?? 0.0,
        'rejected_kg': double.tryParse(_rejectedCtrl.text) ?? 0.0,
        'waste_kg': double.tryParse(_wasteCtrl.text) ?? 0.0,
        'actual_stock_kg': double.parse(_actualStockCtrl.text),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      };
      final res = await _ds.postRaw('/api/shift-handover/close', body);
      setState(() => _result = res as Map<String, dynamic>?);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Widget _balanceCard() {
    if (_loadingBalance) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_balanceInfo == null) {
      return Card(
        color: Colors.orange.shade50,
        child: ListTile(
          leading: const Icon(Icons.warning_amber, color: Colors.orange),
          title: const Text('تعذّر تحميل الرصيد المتوقع'),
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchExpectedBalance),
        ),
      );
    }

    final expected = (_balanceInfo!['expected_stock_kg'] as num?)?.toStringAsFixed(3) ?? '---';
    final received = (_balanceInfo!['received_from_main_kg'] as num?)?.toStringAsFixed(3) ?? '---';
    final consumed = (_balanceInfo!['total_batch_inputs_kg'] as num?)?.toStringAsFixed(3) ?? '---';
    final batches  = _balanceInfo!['batch_count_today'] ?? 0;

    return Card(
      color: const Color(0xFF1565C0).withOpacity(0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: const Color(0xFF1565C0).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.analytics, color: Color(0xFF1565C0)),
              const SizedBox(width: 8),
              const Text('بيانات الوردية الحالية',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _fetchExpectedBalance),
            ]),
            const Divider(),
            _infoRow('الطبخات اليوم', '$batches طبخة'),
            _infoRow('المستلم من الرئيسي', '$received كجم'),
            _infoRow('مجموع مدخلات الطبخات', '$consumed كجم'),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الرصيد المتوقع في الصالة',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$expected كجم',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _resultCard() {
    if (_result == null) return const SizedBox.shrink();
    final hasDeficit = _result!['has_deficit'] == true;
    final deficit    = (_result!['deficit_kg'] as num?)?.toStringAsFixed(3) ?? '0';
    final expected   = (_result!['expected_stock_kg'] as num?)?.toStringAsFixed(3) ?? '0';
    final actual     = (_result!['actual_stock_kg'] as num?)?.toStringAsFixed(3) ?? '0';
    final msg        = _result!['message'] as String? ?? '';

    return Card(
      color: hasDeficit ? Colors.red.shade50 : Colors.green.shade50,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: hasDeficit ? Colors.red : Colors.green),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              hasDeficit ? Icons.error_outline : Icons.check_circle_outline,
              color: hasDeficit ? Colors.red : Colors.green,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              hasDeficit ? 'تم تجميد الوردية — عجز مُسجَّل' : 'تم إغلاق الوردية بنجاح',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: hasDeficit ? Colors.red[800] : Colors.green[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _infoRow('الرصيد المتوقع', '$expected كجم'),
            _infoRow('الرصيد الفعلي', '$actual كجم'),
            if (hasDeficit) _infoRow('العجز', '$deficit كجم'),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _kgField(TextEditingController ctrl, String label, IconData icon) =>
      TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          suffixText: 'كجم',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header card
              Card(
                color: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.swap_horiz, color: Colors.white, size: 40),
                      const SizedBox(height: 8),
                      const Text('إغلاق وتسليم الوردية',
                          style: TextStyle(color: Colors.white, fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      Text(
                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Expected balance
              _balanceCard(),
              const SizedBox(height: 16),

              // Shift info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('بيانات الوردية',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedShift,
                        decoration: const InputDecoration(
                          labelText: 'الوردية *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time),
                        ),
                        items: AppConstants.defaultShifts
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedShift = v),
                        validator: (v) => v == null ? 'اختر الوردية' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _supervisorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم المشرف *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'أدخل اسم المشرف' : null,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          'التاريخ: ${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) {
                            setState(() => _selectedDate = d);
                            _fetchExpectedBalance();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Scrap inputs
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.recycling, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text('مخلفات تضاف لمستودع السكراب',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ]),
                      const SizedBox(height: 12),
                      _kgField(_flashingCtrl, 'الرايش (Flashing) كجم', Icons.layers),
                      const SizedBox(height: 10),
                      _kgField(_rejectedCtrl, 'التالف (Rejected) كجم', Icons.cancel_outlined),
                      const SizedBox(height: 10),
                      _kgField(_wasteCtrl, 'الهدر العام كجم', Icons.delete_outline),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actual weight — highlighted
              Card(
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFF1565C0), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.scale, color: Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        const Text('جرد الميزان الفعلي',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1565C0))),
                      ]),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _actualStockCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                        ],
                        decoration: const InputDecoration(
                          labelText: 'الوزن الفعلي على الميزان (كجم) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.scale),
                          suffixText: 'كجم',
                        ),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'أدخل الوزن الفعلي';
                          if (double.tryParse(v) == null) return 'قيمة غير صحيحة';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Submit
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_outline),
                label: const Text('إغلاق وتسليم الوردية',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // Result
              _resultCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
