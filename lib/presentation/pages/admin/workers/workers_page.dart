import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/reference_models.dart';
import '../../../../data/datasources/supabase_datasource.dart';
import '../../../providers/auth_provider.dart';

class WorkersPage extends ConsumerWidget {
  const WorkersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      body: workers.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyWidget(message: 'لا يوجد عمال', icon: Icons.people_outline);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(workersProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) => _WorkerCard(worker: list[i]),
            ),
          );
        },
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorWidget2(message: 'خطأ: $e'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة عامل'),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, [WorkerModel? worker]) {
    final nameCtrl = TextEditingController(text: worker?.name);
    final phoneCtrl = TextEditingController(text: worker?.phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(worker == null ? 'إضافة عامل' : 'تعديل عامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم *'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final ds = ref.read(dataSourceProvider);
              await ds.upsertWorker({
                if (worker != null) 'id': worker.id,
                'name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                'is_active': true,
              });
              ref.invalidate(workersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _WorkerCard extends ConsumerWidget {
  final WorkerModel worker;
  const _WorkerCard({required this.worker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(worker.name.isNotEmpty ? worker.name[0] : '?'),
        ),
        title: Text(worker.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: worker.phone != null ? Text(worker.phone!) : null,
        trailing: PopupMenuButton(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('تعديل')),
            const PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Colors.red))),
          ],
          onSelected: (v) async {
            final ds = ref.read(dataSourceProvider);
            if (v == 'edit') {
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (_) => _EditWorkerDialog(worker: worker, ref: ref),
                );
              }
            } else if (v == 'delete') {
              await ds.deleteWorker(worker.id);
              ref.invalidate(workersProvider);
            }
          },
        ),
      ),
    );
  }
}

class _EditWorkerDialog extends StatefulWidget {
  final WorkerModel worker;
  final WidgetRef ref;
  const _EditWorkerDialog({required this.worker, required this.ref});

  @override
  State<_EditWorkerDialog> createState() => _EditWorkerDialogState();
}

class _EditWorkerDialogState extends State<_EditWorkerDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.worker.name);
    _phoneCtrl = TextEditingController(text: widget.worker.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل عامل'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 12),
          TextFormField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'الهاتف')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            final ds = widget.ref.read(dataSourceProvider);
            await ds.upsertWorker({
              'id': widget.worker.id,
              'name': _nameCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
              'is_active': true,
            });
            widget.ref.invalidate(workersProvider);
            if (mounted) Navigator.pop(context);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
