import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/production_standard_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';

class WasteMonitoringPage extends ConsumerStatefulWidget {
  const WasteMonitoringPage({super.key});

  @override
  ConsumerState<WasteMonitoringPage> createState() =>
      _WasteMonitoringPageState();
}

class _WasteMonitoringPageState extends ConsumerState<WasteMonitoringPage> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ds = ref.read(dataSourceProvider);
      final result = await ds.getWasteMonitoringDashboard(
        from: _from,
        to: _to,
      );
      setState(() => _data = result);
    } catch (e) {
      setState(() => _error = Helpers.friendlyError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراقبة الهدر والانحراف'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: 'اختيار الفترة',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Date range chip ───────────────────────────────────
          Container(
            color: Colors.deepOrange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Text(
                  '${Helpers.formatDate(_from)} → ${Helpers.formatDate(_to)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.deepOrange),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _from = DateTime.now();
                      _to = DateTime.now();
                    });
                    _load();
                  },
                  child: const Text('اليوم'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _from = DateTime.now().subtract(const Duration(days: 6));
                      _to = DateTime.now();
                    });
                    _load();
                  },
                  child: const Text('7 أيام'),
                ),
              ],
            ),
          ),
          // ── Content ───────────────────────────────────────────
          Expanded(
            child: _loading
                ? const ShimmerList()
                : _error != null
                    ? ErrorWidget2(
                        message: _error!,
                        onRetry: _load,
                      )
                    : _data == null
                        ? const EmptyWidget(
                            message: 'لا توجد بيانات',
                            icon: Icons.analytics_outlined,
                          )
                        : _buildContent(_data!),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final byProduct =
        (data['by_product'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final topWaste =
        (data['top_waste_operations'] as List?)
            ?.cast<Map<String, dynamic>>() ??
            [];
    final byMachine =
        (data['by_machine'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final bySupervisor =
        (data['by_supervisor'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final totalOps = (summary['total_operations'] as num?)?.toInt() ?? 0;
    final totalPairs = (summary['total_pairs'] as num?)?.toInt() ?? 0;
    final normalCount = (summary['normal_count'] as num?)?.toInt() ?? 0;
    final warningCount = (summary['warning_count'] as num?)?.toInt() ?? 0;
    final criticalCount = (summary['critical_count'] as num?)?.toInt() ?? 0;
    final avgDeviation =
        (summary['avg_deviation'] as num?)?.toDouble() ?? 0.0;
    final totalExcessKg =
        (summary['total_excess_kg'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary Cards ──────────────────────────────
          if (totalOps == 0)
            Card(
              color: Colors.blue.shade50,
              child: const ListTile(
                leading: Icon(Icons.info_outline, color: Colors.blue),
                title: Text(
                    'لا توجد عمليات إنتاج مرتبطة بمعايير في الفترة المحددة'),
                subtitle: Text(
                    'أضف معايير الإنتاج أولاً ثم استخدمها عند تسجيل الإنتاج'),
              ),
            )
          else ...[
            _sectionTitle('ملخص الفترة'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _SummaryCard(
                  label: 'العمليات',
                  value: '$totalOps',
                  icon: Icons.factory_outlined,
                  color: Colors.indigo,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _SummaryCard(
                  label: 'إجمالي الأزواج',
                  value: '$totalPairs',
                  icon: Icons.people_outlined,
                  color: Colors.teal,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _SummaryCard(
                  label: 'ضمن المعيار',
                  value: '$normalCount',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _SummaryCard(
                  label: 'تحذير',
                  value: '$warningCount',
                  icon: Icons.warning_amber_outlined,
                  color: Colors.orange,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _SummaryCard(
                  label: 'هدر حرج',
                  value: '$criticalCount',
                  icon: Icons.error_outline,
                  color: Colors.red,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: avgDeviation > 5
                  ? Colors.red.shade50
                  : avgDeviation > 0
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('متوسط الانحراف عن المعيار',
                              style: TextStyle(fontSize: 13)),
                          Text(
                            '${avgDeviation > 0 ? "+" : ""}${avgDeviation.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: avgDeviation > 5
                                  ? Colors.red
                                  : avgDeviation > 0
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (totalExcessKg > 0) ...[
                      const VerticalDivider(),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إجمالي الهدر الزائد',
                                style: TextStyle(fontSize: 13)),
                            Text(
                              '${totalExcessKg.toStringAsFixed(2)} كجم',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Top Waste Operations ───────────────────────
          if (topWaste.isNotEmpty) ...[
            _sectionTitle('أعلى العمليات هدراً'),
            const SizedBox(height: 8),
            ...topWaste.map((op) => _WasteOperationCard(op: op)),
            const SizedBox(height: 20),
          ],

          // ── By Product Type ────────────────────────────
          if (byProduct.isNotEmpty) ...[
            _sectionTitle('الأصناف — كفاءة الاستهلاك'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _TableHeader(
                      cols: ['الصنف', 'المعيار\n(جرام/زوج)', 'الفعلي\n(متوسط)', 'الانحراف', 'عمليات']),
                  const Divider(height: 1),
                  ...byProduct.map((r) {
                    final deviation =
                        (r['avg_deviation'] as num?)?.toDouble() ?? 0;
                    final standard =
                        (r['standard_gram_per_pair'] as num?)?.toDouble() ?? 0;
                    final actual =
                        (r['avg_actual_gram'] as num?)?.toDouble() ?? 0;
                    return _TableRow(
                      cols: [
                        r['product_name'] as String? ?? '',
                        standard.toStringAsFixed(0),
                        actual.toStringAsFixed(0),
                        '${deviation > 0 ? "+" : ""}${deviation.toStringAsFixed(1)}%',
                        '${r['operation_count']}',
                      ],
                      deviationIndex: 3,
                      deviationValue: deviation,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── By Machine ─────────────────────────────────
          if (byMachine.isNotEmpty) ...[
            _sectionTitle('الماكينات — نسبة الهدر'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _TableHeader(cols: ['الماكينة', 'متوسط الانحراف', 'الهدر الزائد\n(كجم)', 'حرج', 'عمليات']),
                  const Divider(height: 1),
                  ...byMachine.map((r) {
                    final deviation =
                        (r['avg_deviation'] as num?)?.toDouble() ?? 0;
                    final excessKg =
                        (r['total_excess_kg'] as num?)?.toDouble() ?? 0;
                    return _TableRow(
                      cols: [
                        r['machine_name'] as String? ?? '',
                        '${deviation > 0 ? "+" : ""}${deviation.toStringAsFixed(1)}%',
                        excessKg.toStringAsFixed(2),
                        '${r['critical_count']}',
                        '${r['operation_count']}',
                      ],
                      deviationIndex: 1,
                      deviationValue: deviation,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── By Supervisor ──────────────────────────────
          if (bySupervisor.isNotEmpty) ...[
            _sectionTitle('المشرفون — انحراف الهدر'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _TableHeader(
                      cols: ['المشرف', 'متوسط الانحراف', 'حرج', 'تحذير', 'عمليات']),
                  const Divider(height: 1),
                  ...bySupervisor.map((r) {
                    final deviation =
                        (r['avg_deviation'] as num?)?.toDouble() ?? 0;
                    return _TableRow(
                      cols: [
                        r['worker_name'] as String? ?? 'غير محدد',
                        '${deviation > 0 ? "+" : ""}${deviation.toStringAsFixed(1)}%',
                        '${r['critical_count']}',
                        '${r['warning_count']}',
                        '${r['operation_count']}',
                      ],
                      deviationIndex: 1,
                      deviationValue: deviation,
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Row(
        children: [
          const Icon(Icons.analytics_outlined,
              size: 18, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.deepOrange),
          ),
        ],
      );
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _WasteOperationCard extends StatelessWidget {
  final Map<String, dynamic> op;
  const _WasteOperationCard({required this.op});

  @override
  Widget build(BuildContext context) {
    final indicator = wasteIndicatorFromString(op['waste_indicator'] as String?);
    final actual = (op['actual_gram_per_pair'] as num?)?.toDouble() ?? 0;
    final standard = (op['standard_gram_per_pair'] as num?)?.toDouble() ?? 0;
    final deviation = (op['deviation_from_standard_pct'] as num?)?.toDouble() ?? 0;
    final color = Color(indicator.colorValue);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(Icons.warning_amber_rounded, color: color, size: 22),
        ),
        title: Text(
          '${op['machine_name']} — ${op['product_name']}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          'مشرف: ${op['worker_name'] ?? "-"} | '
          'أزواج: ${op['pairs_produced']} | '
          'فعلي: ${actual.toStringAsFixed(0)} جم/زوج | '
          'معيار: ${standard.toStringAsFixed(0)} جم/زوج',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '+${deviation.toStringAsFixed(1)}%',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final List<String> cols;
  const _TableHeader({required this.cols});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: cols
            .map((c) => Expanded(
                  child: Text(
                    c,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final List<String> cols;
  final int deviationIndex;
  final double deviationValue;

  const _TableRow({
    required this.cols,
    required this.deviationIndex,
    required this.deviationValue,
  });

  @override
  Widget build(BuildContext context) {
    final indicator = wasteIndicatorFromDeviation(deviationValue);
    final devColor = Color(indicator.colorValue);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: cols.asMap().entries.map((e) {
            final isDeviation = e.key == deviationIndex;
            return Expanded(
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isDeviation && deviationValue > 0
                      ? FontWeight.bold
                      : null,
                  color: isDeviation && deviationValue > 0 ? devColor : null,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
