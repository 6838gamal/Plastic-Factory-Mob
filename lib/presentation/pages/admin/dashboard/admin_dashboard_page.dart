import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../providers/batch_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/stat_card.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/helpers.dart';

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final alerts = ref.watch(alertsProvider({'status': 'pending'}));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(alertsProvider({'status': 'pending'}));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WelcomeBanner(),
            const SizedBox(height: 20),

            Text(
              'مؤشرات اليوم',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),

            stats.when(
              data: (data) => _buildKpiGrid(context, data),
              loading: () => const ShimmerList(count: 4),
              error: (e, _) => ErrorWidget2(message: 'خطأ في تحميل البيانات: $e'),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('التحذيرات المعلقة', style: Theme.of(context).textTheme.headlineSmall),
                TextButton(
                  onPressed: () => context.go('/admin/alerts'),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            alerts.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('لا توجد تحذيرات معلقة'),
                    ),
                  );
                }
                return Column(
                  children: list
                      .take(5)
                      .map((a) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Helpers.getSeverityColor(a.severity).withOpacity(0.2),
                                child: Icon(
                                  Icons.warning_amber,
                                  color: Helpers.getSeverityColor(a.severity),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                Helpers.getAlertTypeText(a.alertType),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                a.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Helpers.getSeverityColor(a.severity).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  Helpers.getSeverityText(a.severity),
                                  style: TextStyle(
                                    color: Helpers.getSeverityColor(a.severity),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                );
              },
              loading: () => const ShimmerList(count: 3),
              error: (e, _) => ErrorWidget2(message: 'خطأ في تحميل التحذيرات'),
            ),

            const SizedBox(height: 20),
            Text('روابط سريعة', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            _QuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid(BuildContext context, Map<String, dynamic> data) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        StatCard(
          title: AppStrings.todayProduction,
          value: '${(data['production_today'] as num).toStringAsFixed(0)} كجم',
          icon: Icons.precision_manufacturing,
          color: Colors.blue,
          onTap: () => context.go('/admin/production'),
        ),
        StatCard(
          title: AppStrings.alertsCount,
          value: '${data['pending_alerts']}',
          icon: Icons.warning_amber,
          color: (data['pending_alerts'] as int) > 0 ? Colors.red : Colors.green,
          onTap: () => context.go('/admin/alerts'),
        ),
        StatCard(
          title: AppStrings.wastePercentage,
          value: '${(data['waste_percentage'] as num).toStringAsFixed(2)}%',
          icon: Icons.delete_sweep,
          color: (data['waste_percentage'] as num) > 5 ? Colors.red : Colors.green,
        ),
        StatCard(
          title: 'طبخات اليوم',
          value: '${data['batches_today']}',
          icon: Icons.blender,
          color: Colors.teal,
        ),
      ],
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String greeting;
    if (now.hour < 12) {
      greeting = 'صباح الخير';
    } else if (now.hour < 17) {
      greeting = 'مساء الخير';
    } else {
      greeting = 'مساء النور';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'مرحباً بك في لوحة الإدارة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Helpers.formatDateTime(now),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.factory, size: 64, color: Colors.white30),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0);
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      {'icon': Icons.inventory_2, 'label': 'المخزون', 'route': '/admin/inventory', 'color': Colors.blue},
      {'icon': Icons.blender, 'label': 'الطبخات', 'route': '/admin/batches', 'color': Colors.teal},
      {'icon': Icons.precision_manufacturing, 'label': 'الإنتاج', 'route': '/admin/production', 'color': Colors.orange},
      {'icon': Icons.bar_chart, 'label': 'التقارير', 'route': '/admin/reports', 'color': Colors.purple},
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: actions
          .map((a) => InkWell(
                onTap: () => context.go(a['route'] as String),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: (a['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (a['color'] as Color).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(a['icon'] as IconData, color: a['color'] as Color),
                      const SizedBox(width: 8),
                      Text(
                        a['label'] as String,
                        style: TextStyle(
                          color: a['color'] as Color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
