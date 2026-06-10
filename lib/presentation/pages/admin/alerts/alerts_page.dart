import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/severity_chip.dart';
import '../../../../data/models/alert_model.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../core/utils/helpers.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/constants/app_strings.dart';

class AlertsPage extends ConsumerStatefulWidget {
  const AlertsPage({super.key});

  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'معلقة'),
            Tab(text: 'مؤكدة'),
            Tab(text: 'محلولة'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _AlertsList(status: 'pending'),
              _AlertsList(status: 'acknowledged'),
              _AlertsList(status: 'resolved'),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertsList extends ConsumerWidget {
  final String status;
  const _AlertsList({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider({'status': status}));

    return alerts.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyWidget(
            message: 'لا توجد تحذيرات ${_statusLabel(status)}',
            icon: Icons.check_circle_outline,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(alertsProvider({'status': status})),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) => _AlertCard(alert: list[i]),
          ),
        );
      },
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorWidget2(
        message: Helpers.friendlyError(e),
        onRetry: () => ref.invalidate(alertsProvider),
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'معلقة';
      case 'acknowledged':
        return 'مؤكدة';
      case 'resolved':
        return 'محلولة';
      default:
        return '';
    }
  }
}

class _AlertCard extends ConsumerWidget {
  final AlertModel alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = Helpers.getSeverityColor(alert.severity);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: severityColor.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: severityColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Helpers.getAlertTypeText(alert.alertType),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: severityColor,
                    ),
                  ),
                ),
                SeverityChip(severity: alert.severity),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.description, style: TextStyle(color: Colors.grey[700])),
            if (alert.materialName != null) ...[
              const SizedBox(height: 6),
              _InfoRow(Icons.science_outlined, 'المادة:', alert.materialName!),
            ],
            if (alert.batchNumber != null)
              _InfoRow(Icons.blender_outlined, 'الطبخة:', alert.batchNumber!),
            if (alert.machineName != null)
              _InfoRow(Icons.precision_manufacturing_outlined, 'الماكينة:', alert.machineName!),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  Helpers.formatDateTime(alert.createdAt),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const Spacer(),
                if (alert.status == 'pending')
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _updateStatus(context, ref, 'acknowledged'),
                        child: const Text('تأكيد', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => _updateStatus(context, ref, 'resolved'),
                        child: const Text(
                          'حل',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                if (alert.status == 'acknowledged')
                  TextButton(
                    onPressed: () => _updateStatus(context, ref, 'resolved'),
                    child: const Text('تم الحل', style: TextStyle(color: Colors.green)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, String status) async {
    final ds = ref.read(dataSourceProvider);
    await ds.updateAlertStatus(alert.id, status);
    ref.invalidate(alertsProvider({'status': 'pending'}));
    ref.invalidate(alertsProvider({'status': 'acknowledged'}));
    ref.invalidate(alertsProvider({'status': 'resolved'}));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}
