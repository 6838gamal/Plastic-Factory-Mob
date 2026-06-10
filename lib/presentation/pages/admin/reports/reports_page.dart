import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../data/models/machine_production_model.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _period = 'daily';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      final periods = ['daily', 'weekly', 'monthly'];
      setState(() => _period = periods[_tabController.index]);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTimeRange get _dateRange {
    switch (_period) {
      case 'daily':
        return DateTimeRange(start: _selectedDate, end: _selectedDate);
      case 'weekly':
        final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        return DateTimeRange(start: startOfWeek, end: startOfWeek.add(const Duration(days: 6)));
      case 'monthly':
        return DateTimeRange(
          start: DateTime(_selectedDate.year, _selectedDate.month, 1),
          end: DateTime(_selectedDate.year, _selectedDate.month + 1, 0),
        );
      default:
        return DateTimeRange(start: _selectedDate, end: _selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _dateRange;
    final productions = ref.watch(machineProductionsProvider({'from': range.start, 'to': range.end.add(const Duration(days: 1))}));
    final batches = ref.watch(batchesProvider({'from': range.start, 'to': range.end}));

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'يومي'), Tab(text: 'أسبوعي'), Tab(text: 'شهري')],
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${Helpers.formatDate(range.start)} → ${Helpers.formatDate(range.end)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: List.generate(3, (_) {
              return productions.when(
                data: (prodList) => batches.when(
                  data: (batchList) => _ReportContent(productions: prodList, batchCount: batchList.length),
                  loading: () => const ShimmerList(),
                  error: (e, _) => ErrorWidget2(
                    message: Helpers.friendlyError(e),
                    onRetry: () => ref.invalidate(batchesProvider),
                  ),
                ),
                loading: () => const ShimmerList(),
                error: (e, _) => ErrorWidget2(
                  message: Helpers.friendlyError(e),
                  onRetry: () => ref.invalidate(machineProductionsProvider),
                ),
              );
            }),
          ),
        ),
      ],
    );
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
}

class _ReportContent extends StatelessWidget {
  final List<MachineProductionModel> productions;
  final int batchCount;
  const _ReportContent({required this.productions, required this.batchCount});

  @override
  Widget build(BuildContext context) {
    final totalProduced = productions.fold(0.0, (s, p) => s + p.producedQuantity);
    final totalScrap = productions.fold(0.0, (s, p) => s + p.scrapQuantity);
    final totalWaste = productions.fold(0.0, (s, p) => s + p.wasteQuantity);
    final totalStop = productions.fold(0.0, (s, p) => s + p.stopTimeMinutes);
    final total = totalProduced + totalScrap + totalWaste;
    final efficiency = total > 0 ? (totalProduced / total) * 100 : 0.0;
    final wastePercent = total > 0 ? (totalWaste / total) * 100 : 0.0;

    if (productions.isEmpty && batchCount == 0) {
      return const EmptyWidget(message: 'لا توجد بيانات في هذه الفترة', icon: Icons.bar_chart_outlined);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // KPI Cards
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            _KpiTile('الطبخات', '$batchCount', Colors.blue, Icons.blender),
            _KpiTile('الإنتاج', '${totalProduced.toStringAsFixed(1)} كجم', Colors.green, Icons.precision_manufacturing),
            _KpiTile('السكراب', '${totalScrap.toStringAsFixed(1)} كجم', Colors.orange, Icons.recycling),
            _KpiTile('الهالك', '${totalWaste.toStringAsFixed(1)} كجم', Colors.red, Icons.delete_sweep),
            _KpiTile('الكفاءة', '${efficiency.toStringAsFixed(1)}%',
                efficiency >= 90 ? Colors.green : Colors.orange, Icons.speed),
            _KpiTile('نسبة الهالك', '${wastePercent.toStringAsFixed(1)}%',
                wastePercent > 5 ? Colors.red : Colors.green, Icons.percent),
          ],
        ),
        const SizedBox(height: 16),
        if (productions.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('توزيع الإنتاج', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            value: totalProduced,
                            color: Colors.green,
                            title: 'إنتاج\n${totalProduced.toStringAsFixed(0)}',
                            titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            radius: 80,
                          ),
                          if (totalScrap > 0)
                            PieChartSectionData(
                              value: totalScrap,
                              color: Colors.orange,
                              title: 'سكراب\n${totalScrap.toStringAsFixed(0)}',
                              titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              radius: 80,
                            ),
                          if (totalWaste > 0)
                            PieChartSectionData(
                              value: totalWaste,
                              color: Colors.red,
                              title: 'هالك\n${totalWaste.toStringAsFixed(0)}',
                              titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              radius: 80,
                            ),
                        ],
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Machine efficiency table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('أداء الماكينات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...productions.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(p.machineName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text('${p.efficiency.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: p.efficiency >= 90 ? Colors.green : p.efficiency >= 75 ? Colors.orange : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: p.efficiency / 100,
                                backgroundColor: Colors.grey[200],
                                color: p.efficiency >= 90 ? Colors.green : p.efficiency >= 75 ? Colors.orange : Colors.red,
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiTile(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
