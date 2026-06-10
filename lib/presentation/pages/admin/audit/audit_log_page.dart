import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/audit_log_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../core/constants/app_constants.dart';

final auditLogProvider = FutureProvider<List<AuditLogModel>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getAuditLogs();
});

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  String _search = '';
  String? _selectedAction;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(auditLogProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  hintText: 'بحث في السجل...',
                  leading: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _selectedAction,
                hint: const Text('الإجراء'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('الكل')),
                  ...['create', 'update', 'delete', 'deduct', 'failed'].map(
                    (a) => DropdownMenuItem(value: a, child: Text(_actionLabel(a))),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedAction = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.when(
            data: (list) {
              var filtered = list;
              if (_search.isNotEmpty) {
                filtered = filtered
                    .where((l) =>
                        l.tableName.contains(_search) ||
                        (l.description?.contains(_search) ?? false) ||
                        (l.userEmail?.contains(_search) ?? false))
                    .toList();
              }
              if (_selectedAction != null) {
                filtered = filtered.where((l) => l.action == _selectedAction).toList();
              }

              if (filtered.isEmpty) {
                return const EmptyWidget(message: 'لا توجد سجلات', icon: Icons.history_outlined);
              }

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(auditLogProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _AuditCard(log: filtered[i]),
                ),
              );
            },
            loading: () => const ShimmerList(),
            error: (e, _) => ErrorWidget2(
              message: Helpers.friendlyError(e),
              onRetry: () => ref.invalidate(auditLogProvider),
            ),
          ),
        ),
      ],
    );
  }

  String _actionLabel(String action) {
    const map = {
      'create': 'إنشاء',
      'update': 'تعديل',
      'delete': 'حذف',
      'deduct': 'خصم',
      'transfer': 'تحويل',
      'failed': 'فشل',
    };
    return map[action] ?? action;
  }
}

class _AuditCard extends StatelessWidget {
  final AuditLogModel log;
  const _AuditCard({required this.log});

  @override
  Widget build(BuildContext context) {
    Color actionColor;
    IconData actionIcon;
    switch (log.action) {
      case 'create':
        actionColor = Colors.green;
        actionIcon = Icons.add_circle_outline;
        break;
      case 'update':
        actionColor = Colors.blue;
        actionIcon = Icons.edit_outlined;
        break;
      case 'delete':
        actionColor = Colors.red;
        actionIcon = Icons.delete_outline;
        break;
      case 'failed':
        actionColor = Colors.red;
        actionIcon = Icons.error_outline;
        break;
      default:
        actionColor = Colors.grey;
        actionIcon = Icons.history;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: actionColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(actionIcon, color: actionColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        log.tableName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          log.action,
                          style: TextStyle(color: actionColor, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  if (log.description != null) ...[
                    const SizedBox(height: 4),
                    Text(log.description!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        log.userEmail ?? log.userId,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        Helpers.formatDateTime(log.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
