import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/machine_production_model.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../data/models/production_standard_model.dart';

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
    final productions = ref.watch(machineProductionsProvider(ProductionFilters(from: _from, to: _to)));

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
              onDeleted: () => setState(() {
                _from = null;
                _to = null;
              }),
            ),
          ),
        Expanded(
          child: productions.when(
            data: (list) {
              final filtered = _search.isEmpty
                  ? list
                  : list
                      .where((p) =>
                          p.batchNumber.contains(_search) ||
                          p.machineName.contains(_search))
                      .toList();

              if (filtered.isEmpty) {
                return const EmptyWidget(
                    message: 'لا توجد سجلات إنتاج',
                    icon: Icons.precision_manufacturing_outlined);
              }

              final totalProduced = filtered.fold(0.0, (s, p) => s + p.producedQuantity);
              final totalScrap = filtered.fold(0.0, (s, p) => s + p.scrapQuantity);
              final totalWaste = filtered.fold(0.0, (s, p) => s + p.wasteQuantity);

              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(machineProductionsProvider(ProductionFilters(from: _from, to: _to))),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _SummaryCard(
                        produced: totalProduced, scrap: totalScrap, waste: totalWaste),
                    const SizedBox(height: 8),
                    ...filtered.map((p) => _ProductionCard(
                          production: p,
                          onEdit: () => _showEditDialog(p),
                          onDelete: () => _deleteProduction(p),
                        )),
                  ],
                ),
              );
            },
            loading: () => const ShimmerList(),
            error: (e, _) => ErrorWidget2(
              message: Helpers.friendlyError(e),
              onRetry: () => ref.invalidate(machineProductionsProvider(ProductionFilters(from: _from, to: _to))),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditDialog(MachineProductionModel p) {
    final producedCtrl = TextEditingController(text: p.producedQuantity.toString());
    final scrapCtrl = TextEditingController(text: p.scrapQuantity.toString());
    final wasteCtrl = TextEditingController(text: p.wasteQuantity.toString());
    final stopCtrl = TextEditingController(text: p.stopTimeMinutes.toString());
    final notesCtrl = TextEditingController(text: p.notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.edit_outlined, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text('تعديل إنتاج: ${p.machineName}',
              style: const TextStyle(fontSize: 15))),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: producedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الإنتاج (كجم)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: scrapCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'السكراب (كجم)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: wasteCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الهالك (كجم)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: stopCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'وقت التوقف (دقيقة)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final ds = ref.read(dataSourceProvider);
              try {
                await ds.updateMachineProduction(p.id, {
                  'produced_quantity': double.tryParse(producedCtrl.text) ?? p.producedQuantity,
                  'scrap_quantity': double.tryParse(scrapCtrl.text) ?? p.scrapQuantity,
                  'waste_quantity': double.tryParse(wasteCtrl.text) ?? p.wasteQuantity,
                  'stop_time_minutes': double.tryParse(stopCtrl.text) ?? p.stopTimeMinutes,
                  'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  'status': p.status,
                  // Round-trip yield inputs so the backend preserves/recomputes stats
                  'standard_id': p.standardId,
                  'pairs_produced': p.pairsProduced > 0 ? p.pairsProduced : null,
                });
                ref.invalidate(machineProductionsProvider(ProductionFilters(from: _from, to: _to)));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تم تحديث سجل الإنتاج')));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduction(MachineProductionModel p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف سجل إنتاج ماكينة ${p.machineName} للطبخة #${p.batchNumber}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final ds = ref.read(dataSourceProvider);
        await ds.deleteMachineProduction(p.id);
        ref.invalidate(machineProductionsProvider(ProductionFilters(from: _from, to: _to)));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('تم حذف السجل')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
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
            _SumItem(
                'الكفاءة',
                '${efficiency.toStringAsFixed(1)}%',
                efficiency >= 90
                    ? Colors.green
                    : efficiency >= 75
                        ? Colors.orange
                        : Colors.red),
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
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _ProductionCard extends StatelessWidget {
  final MachineProductionModel production;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductionCard(
      {required this.production, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.1),
          child: const Icon(Icons.precision_manufacturing, color: Colors.orange, size: 22),
        ),
        title:
            Text('ماكينة: ${production.machineName}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          'طبخة #${production.batchNumber} • ${Helpers.formatDateTime(production.createdAt)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
              onPressed: onEdit,
              tooltip: 'تعديل',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: onDelete,
              tooltip: 'حذف',
            ),
            const Icon(Icons.expand_more),
          ],
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
                // ── Yield standard rows ──────────────────────────
                if (production.pairsProduced > 0)
                  _Row('عدد الأزواج', '${production.pairsProduced} زوج'),
                if (production.standardGramPerPair != null)
                  _Row('معيار الإنتاج', '${production.standardGramPerPair!.toStringAsFixed(0)} جم/زوج'),
                if (production.actualGramPerPair != null)
                  _Row('الفعلي', '${production.actualGramPerPair!.toStringAsFixed(0)} جم/زوج'),
                if (production.deviationFromStandardPct != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('الانحراف:',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey)),
                        const Spacer(),
                        _WasteBadge(
                          deviation: production.deviationFromStandardPct!,
                          indicator: production.wasteIndicatorStr,
                        ),
                      ],
                    ),
                  ),
                ],
                if (production.notes != null && production.notes!.isNotEmpty)
                  _Row('ملاحظات', production.notes!),
                if (production.productionImageUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(production.productionImageUrl!,
                        height: 150,
                        fit: BoxFit.cover,
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

// ── Waste Indicator Badge ──────────────────────────────────────────────────────

class _WasteBadge extends StatelessWidget {
  final double deviation;
  final String? indicator;

  const _WasteBadge({required this.deviation, required this.indicator});

  @override
  Widget build(BuildContext context) {
    final ind = wasteIndicatorFromString(indicator);
    final color = Color(ind.colorValue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        deviation <= 0
            ? '✓ ضمن المعيار'
            : '+${deviation.toStringAsFixed(1)}% — ${ind.label}',
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

// ── Simple label–value row ─────────────────────────────────────────────────────

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
          Expanded(
              child:
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}
