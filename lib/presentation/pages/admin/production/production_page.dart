import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/machine_production_model.dart';
import '../../../../core/utils/helpers.dart';

class ProductionPage extends ConsumerStatefulWidget {
  const ProductionPage({super.key});

  @override
  ConsumerState<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends ConsumerState<ProductionPage> {
  DateTime? _from;
  DateTime? _to;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final productions = ref.watch(machineProductionsProvider({'from': _from, 'to': _to}));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  hintText: 'بحث برقم الطبخة أو الماكينة...',
                  leading: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range),
              ),
            ],
          ),
        ),
        if (_from != null || _to != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              label: Text(
                '${_from != null ? Helpers.formatDate(_from!) : '...'} → ${_to != null ? Helpers.formatDate(_to!) : '...'}',
              ),
              onDeleted: () => setState(() { _from = null; _to = null; }),
            ),
          ),
        Expanded(
          child: productions.when(
            data: (list) {
              final filtered = _search.isEmpty
                  ? list
                  : list.where((p) =>
                      p.batchNumber.contains(_search) ||
                      p.machineName.contains(_search)).toList();

              if (filtered.isEmpty) {
                return const EmptyWidget(message: 'لا توجد سجلات إنتاج', icon: Icons.precision_manufacturing_outlined);
              }

              // Summary card
              final totalProduced = filtered.fold(0.0, (s, p) => s + p.producedQuantity);
              final totalScrap = filtered.fold(0.0, (s, p) => s + p.scrapQuantity);
              final totalWaste = filtered.fold(0.0, (s, p) => s + p.wasteQuantity);

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(machineProductionsProvider({'from': _from, 'to': _to})),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _SummaryCard(produced: totalProduced, scrap: totalScrap, waste: totalWaste),
                    const SizedBox(height: 8),
                    ...filtered.map((p) => _ProductionCard(production: p)),
                  ],
                ),
              );
            },
            loading: () => const ShimmerList(),
            error: (e, _) => ErrorWidget2(message: 'خطأ: $e'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (range != null) {
      setState(() { _from = range.start; _to = range.end; });
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final double produced;
  final double scrap;
  final double waste;
  const _SummaryCard({required this.produced, required this.scrap, required this.waste});

  @override
  Widget build(BuildContext context) {
    final total = produced + scrap + waste;
    final efficiency = total > 0 ? (produced / total) * 100 : 0.0;

    return Card(
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SumItem('الإنتاج', '${produced.toStringAsFixed(1)} كجم', Colors.green),
            _SumItem('السكراب', '${scrap.toStringAsFixed(1)} كجم', Colors.orange),
            _SumItem('الهالك', '${waste.toStringAsFixed(1)} كجم', Colors.red),
            _SumItem('الكفاءة', '${efficiency.toStringAsFixed(1)}%',
                efficiency >= 90 ? Colors.green : efficiency >= 75 ? Colors.orange : Colors.red),
          ],
        ),
      ),
    );
  }
}

class _SumItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SumItem(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _ProductionCard extends StatelessWidget {
  final MachineProductionModel production;
  const _ProductionCard({required this.production});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.1),
          child: const Icon(Icons.precision_manufacturing, color: Colors.orange, size: 22),
        ),
        title: Text('ماكينة: ${production.machineName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          'طبخة #${production.batchNumber} • ${Helpers.formatDateTime(production.createdAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row('المنتج', production.productName),
                _Row('الإنتاج', '${production.producedQuantity.toStringAsFixed(2)} كجم'),
                _Row('السكراب', '${production.scrapQuantity.toStringAsFixed(2)} كجم'),
                _Row('الهالك', '${production.wasteQuantity.toStringAsFixed(2)} كجم'),
                _Row('وقت التوقف', '${production.stopTimeMinutes.toStringAsFixed(0)} دقيقة'),
                _Row('الكفاءة', '${production.efficiency.toStringAsFixed(1)}%'),
                if (production.notes != null && production.notes!.isNotEmpty)
                  _Row('ملاحظات', production.notes!),
                if (production.productionImageUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(production.productionImageUrl!, height: 150, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}
