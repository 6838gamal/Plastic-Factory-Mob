import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../data/models/reference_models.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/utils/helpers.dart';

class MachinesPage extends ConsumerWidget {
  const MachinesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machines = ref.watch(machinesProvider);
    final mixers = ref.watch(mixersProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: 'الماكينات'), Tab(text: 'الخلاطات')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Machines
                machines.when(
                  data: (list) => _ReferenceList(
                    items: list.map((m) => _Item(id: m.id, name: m.name, sub: m.description)).toList(),
                    emptyMessage: 'لا توجد ماكينات',
                    onAdd: () => _showMachineDialog(context, ref),
                    onEdit: (item) => _showMachineDialog(context, ref, id: item.id, name: item.name, desc: item.sub),
                    onDelete: (id) async {
                      await ref.read(dataSourceProvider).upsertMachine({'id': id, 'is_active': false});
                      ref.invalidate(machinesProvider);
                    },
                  ),
                  loading: () => const ShimmerList(),
                  error: (e, _) => ErrorWidget2(
                    message: Helpers.friendlyError(e),
                    onRetry: () => ref.invalidate(machinesProvider),
                  ),
                ),
                // Mixers
                mixers.when(
                  data: (list) => _ReferenceList(
                    items: list.map((m) => _Item(id: m.id, name: m.name, sub: m.capacity != null ? 'السعة: ${m.capacity} كجم' : null)).toList(),
                    emptyMessage: 'لا توجد خلاطات',
                    onAdd: () => _showMixerDialog(context, ref),
                    onEdit: (item) => _showMixerDialog(context, ref, id: item.id, name: item.name),
                    onDelete: (id) async {
                      await ref.read(dataSourceProvider).upsertMixer({'id': id, 'is_active': false});
                      ref.invalidate(mixersProvider);
                    },
                  ),
                  loading: () => const ShimmerList(),
                  error: (e, _) => ErrorWidget2(
                    message: Helpers.friendlyError(e),
                    onRetry: () => ref.invalidate(mixersProvider),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMachineDialog(BuildContext context, WidgetRef ref, {String? id, String? name, String? desc}) {
    final nameCtrl = TextEditingController(text: name);
    final descCtrl = TextEditingController(text: desc);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'إضافة ماكينة' : 'تعديل ماكينة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم *')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'الوصف')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertMachine({
                if (id != null) 'id': id,
                'name': nameCtrl.text.trim(),
                'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                'is_active': true,
              });
              ref.invalidate(machinesProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showMixerDialog(BuildContext context, WidgetRef ref, {String? id, String? name}) {
    final nameCtrl = TextEditingController(text: name);
    final capCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? 'إضافة خلاط' : 'تعديل خلاط'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم *')),
            const SizedBox(height: 12),
            TextField(controller: capCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعة (كجم)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertMixer({
                if (id != null) 'id': id,
                'name': nameCtrl.text.trim(),
                'capacity': double.tryParse(capCtrl.text),
                'is_active': true,
              });
              ref.invalidate(mixersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String id;
  final String name;
  final String? sub;
  const _Item({required this.id, required this.name, this.sub});
}

class _ReferenceList extends StatelessWidget {
  final List<_Item> items;
  final String emptyMessage;
  final VoidCallback onAdd;
  final void Function(_Item) onEdit;
  final void Function(String) onDelete;

  const _ReferenceList({
    required this.items,
    required this.emptyMessage,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: items.isEmpty
          ? EmptyWidget(message: emptyMessage, icon: Icons.settings_input_component_outlined)
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.settings)),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: item.sub != null ? Text(item.sub!) : null,
                    trailing: PopupMenuButton(
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Colors.red))),
                      ],
                      onSelected: (v) {
                        if (v == 'edit') onEdit(item);
                        if (v == 'delete') onDelete(item.id);
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: onAdd,
        child: const Icon(Icons.add),
      ),
    );
  }
}
