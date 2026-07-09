import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/batch_model.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/utils/helpers.dart';

class BatchesAdminPage extends ConsumerStatefulWidget {
  const BatchesAdminPage({super.key});

  @override
  ConsumerState<BatchesAdminPage> createState() => _BatchesAdminPageState();
}

class _BatchesAdminPageState extends ConsumerState<BatchesAdminPage> {
  DateTime? _from;
  DateTime? _to;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(batchesProvider(BatchFilters(from: _from, to: _to)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  hintText: 'بحث برقم الطبخة...',
                  leading: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range),
                tooltip: 'تصفية بالتاريخ',
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
          child: batches.when(
            data: (list) {
              final filtered = _search.isEmpty
                  ? list
                  : list.where((b) => b.batchNumber.contains(_search)).toList();

              if (filtered.isEmpty) {
                return const EmptyWidget(
                  message: 'لا توجد طبخات',
                  icon: Icons.blender_outlined,
                );
              }

              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(batchesProvider(BatchFilters(from: _from, to: _to))),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _BatchCard(
                    batch: filtered[i],
                    onDelete: () => _deleteBatch(filtered[i]),
                  ),
                ),
              );
            },
            loading: () => const ShimmerList(),
            error: (e, _) => ErrorWidget2(
              message: Helpers.friendlyError(e),
              onRetry: () => ref.invalidate(batchesProvider(BatchFilters(from: _from, to: _to))),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteBatch(BatchModel batch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف الطبخة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طبخة #${batch.batchNumber}'),
            const SizedBox(height: 4),
            Text('${batch.workerName} • ${Helpers.formatDate(batch.date)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'تنبيه: لن تُعاد كميات المواد الخام المستهلكة إلى المخزون تلقائياً.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final ds = ref.read(dataSourceProvider);
        await ds.deleteBatch(batch.id);
        ref.invalidate(batchesProvider(BatchFilters(from: _from, to: _to)));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حذف طبخة #${batch.batchNumber}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('خطأ في الحذف: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }
}

class _BatchCard extends StatelessWidget {
  final BatchModel batch;
  final VoidCallback onDelete;
  const _BatchCard({required this.batch, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
          child: Icon(Icons.blender, color: Theme.of(context).primaryColor, size: 22),
        ),
        title: Text(
          'طبخة #${batch.batchNumber}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${batch.workerName} • ${batch.shift} • ${Helpers.formatDate(batch.date)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: onDelete,
              tooltip: 'حذف الطبخة',
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('الخلاط', batch.mixerName),
                _DetailRow('المنتج', batch.productName),
                _DetailRow('نوع الخلطة', batch.mixtureTypeName),
                const Divider(),
                Text('المواد الخام:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 4),
                if (batch.pvcQty > 0) _MaterialRow('PVC', batch.pvcQty),
                if (batch.dopQty > 0) _MaterialRow('DOP', batch.dopQty),
                if (batch.scrapQty > 0) _MaterialRow('سكراب', batch.scrapQty),
                if (batch.calciumQty > 0) _MaterialRow('كالسيوم', batch.calciumQty),
                if (batch.waxQty > 0) _MaterialRow('شمع', batch.waxQty),
                if (batch.stabilizerQty > 0) _MaterialRow('مثبت', batch.stabilizerQty),
                if (batch.titaniumQty > 0) _MaterialRow('تيتانيوم', batch.titaniumQty),
                const Divider(),
                _DetailRow('إجمالي المدخلات', '${batch.totalInput.toStringAsFixed(2)} كجم'),
                if (batch.notes != null && batch.notes!.isNotEmpty)
                  _DetailRow('ملاحظات', batch.notes!),
                if (batch.scaleImageUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      batch.scaleImageUrl!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    ),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  final String name;
  final double qty;
  const _MaterialRow(this.name, this.qty);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, size: 8, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          Text('${qty.toStringAsFixed(2)} كجم',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
