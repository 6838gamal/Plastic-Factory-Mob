import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../providers/batch_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/stat_card.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/helpers.dart';

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final alerts = ref.watch(alertsProvider(const AlertFilters(status: 'pending')));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(alertsProvider(const AlertFilters(status: 'pending')));
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
              data: (data) => _KpiGrid(data: data),
              loading: () => const ShimmerList(count: 4),
              error: (e, _) => ErrorWidget2(
                message: Helpers.friendlyError(e),
                onRetry: () => ref.invalidate(dashboardStatsProvider),
              ),
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
              error: (e, _) => ErrorWidget2(
                message: Helpers.friendlyError(e),
                onRetry: () => ref.invalidate(alertsProvider(const AlertFilters(status: 'pending'))),
              ),
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
}

// ─── KPI Grid (StatefulWidget to handle reset loading state) ──────────────────

class _KpiGrid extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  const _KpiGrid({required this.data});

  @override
  ConsumerState<_KpiGrid> createState() => _KpiGridState();
}

class _KpiGridState extends ConsumerState<_KpiGrid> {
  final Set<String> _resetting = {};

  Future<void> _doReset(BuildContext ctx, String counter, String label) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.restart_alt_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('تأكيد التصفير'),
        ]),
        content: Text('هل تريد تصفير عداد "$label"؟\nسيُحسب العداد من الصفر اعتباراً من الآن، ولن تُحذف البيانات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تصفير', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _resetting.add(counter));
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.resetDashboardCounter(counter);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(alertsProvider(const AlertFilters(status: 'pending')));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('✅ تم تصفير "$label" بنجاح'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التصفير: ${Helpers.friendlyError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resetting.remove(counter));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final frozenShifts   = (data['frozen_shifts_today'] as num?)?.toInt() ?? 0;
    final custodyDebts   = (data['custody_debts_count'] as num?)?.toInt() ?? 0;
    final custodyTotalKg = (data['custody_debts_total_kg'] as num?)?.toDouble() ?? 0.0;
    final scrapBalance   = (data['scrap_balance_kg'] as num?)?.toDouble() ?? 0.0;
    final pendingAlerts  = (data['pending_alerts'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        // ── تنبيه أحمر فوري إذا وجدت ورديات مجمَّدة أو مديونيات ──
        if (frozenShifts > 0 || custodyDebts > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade400, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                  const SizedBox(width: 8),
                  const Text('⚠️ تنبيهات العهدة — تحتاج اتخاذ إجراء',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
                const SizedBox(height: 8),
                if (frozenShifts > 0)
                  _alertRow(Icons.ac_unit, Colors.red,
                      '$frozenShifts وردية مجمَّدة اليوم',
                      onTap: () => context.go('/admin/shift-handover')),
                if (custodyDebts > 0)
                  _alertRow(Icons.person_off, Colors.orange,
                      '$custodyDebts مديونية عهدة معلقة — ${custodyTotalKg.toStringAsFixed(1)} كجم إجمالي',
                      onTap: () => context.go('/admin/shift-handover')),
              ],
            ),
          ),

        // ── KPIs شبكة ─────────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _resetting.contains('production')
                ? _loadingCard()
                : StatCard(
                    title: AppStrings.todayProduction,
                    value: '${(data['production_today'] as num).toStringAsFixed(0)} كجم',
                    icon: Icons.precision_manufacturing,
                    color: Colors.blue,
                    onTap: () => context.go('/admin/production'),
                    onReset: () => _doReset(context, 'production', 'الإنتاج'),
                  ),
            _resetting.contains('alerts')
                ? _loadingCard()
                : StatCard(
                    title: 'التحذيرات',
                    value: '$pendingAlerts',
                    icon: Icons.warning_amber,
                    color: pendingAlerts > 0 ? Colors.red : Colors.green,
                    onTap: () => context.go('/admin/alerts'),
                    onReset: () => _doReset(context, 'alerts', 'التحذيرات'),
                  ),
            _resetting.contains('production')
                ? _loadingCard()
                : StatCard(
                    title: 'نسبة الهدر',
                    value: '${(data['waste_percentage'] as num).toStringAsFixed(2)}%',
                    icon: Icons.delete_sweep,
                    color: (data['waste_percentage'] as num) > 5 ? Colors.red : Colors.green,
                    onReset: () => _doReset(context, 'production', 'الهدر'),
                  ),
            _resetting.contains('batches')
                ? _loadingCard()
                : StatCard(
                    title: 'طبخات اليوم',
                    value: '${data['batches_today']}',
                    icon: Icons.blender,
                    color: Colors.teal,
                    onReset: () => _doReset(context, 'batches', 'الطبخات'),
                  ),
            _resetting.contains('scrap_balance')
                ? _loadingCard()
                : StatCard(
                    title: '♻️ رصيد السكراب',
                    value: '${scrapBalance.toStringAsFixed(1)} كجم',
                    icon: Icons.recycling,
                    color: Colors.orange,
                    onReset: () => _doReset(context, 'scrap_balance', 'رصيد السكراب'),
                  ),
            StatCard(
              title: 'الكفاءة',
              value: '${(data['efficiency_pct'] as num?)?.toStringAsFixed(1) ?? 0}%',
              icon: Icons.speed,
              color: Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _loadingCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _alertRow(IconData icon, Color color, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 13))),
          if (onTap != null) Icon(Icons.arrow_forward_ios, color: color, size: 12),
        ]),
      ),
    );
  }
}

// ─── Welcome Banner ────────────────────────────────────────────────────────────

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
                Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                const Text(
                  'مرحباً بك في لوحة الإدارة',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(Helpers.formatDateTime(now), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.factory, size: 64, color: Colors.white30),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0);
  }
}

// ─── Quick Actions ─────────────────────────────────────────────────────────────

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
                        style: TextStyle(color: a['color'] as Color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
