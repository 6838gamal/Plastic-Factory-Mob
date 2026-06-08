import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/pages/worker/worker_home_page.dart';
import '../../presentation/pages/admin/admin_shell_page.dart';
import '../../presentation/pages/admin/dashboard/admin_dashboard_page.dart';
import '../../presentation/pages/admin/inventory/inventory_page.dart';
import '../../presentation/pages/admin/materials/materials_page.dart';
import '../../presentation/pages/admin/workers/workers_page.dart';
import '../../presentation/pages/admin/machines/machines_page.dart';
import '../../presentation/pages/admin/batches/batches_admin_page.dart';
import '../../presentation/pages/admin/alerts/alerts_page.dart';
import '../../presentation/pages/admin/audit/audit_log_page.dart';
import '../../presentation/pages/admin/reports/reports_page.dart';
import '../../presentation/pages/admin/settings/settings_page.dart';
import '../../presentation/pages/admin/production/production_page.dart';
import '../../presentation/providers/auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/worker',
    redirect: (context, state) {
      final isAdmin = authState.isAdmin;
      final onAdmin = state.uri.toString().startsWith('/admin');
      if (onAdmin && !isAdmin) return '/worker';
      return null;
    },
    routes: [
      GoRoute(
        path: '/worker',
        builder: (context, state) => const WorkerHomePage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShellPage(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardPage()),
          GoRoute(path: '/admin/inventory', builder: (_, __) => const InventoryPage()),
          GoRoute(path: '/admin/materials', builder: (_, __) => const MaterialsPage()),
          GoRoute(path: '/admin/workers', builder: (_, __) => const WorkersPage()),
          GoRoute(path: '/admin/machines', builder: (_, __) => const MachinesPage()),
          GoRoute(path: '/admin/batches', builder: (_, __) => const BatchesAdminPage()),
          GoRoute(path: '/admin/production', builder: (_, __) => const ProductionPage()),
          GoRoute(path: '/admin/alerts', builder: (_, __) => const AlertsPage()),
          GoRoute(path: '/admin/audit', builder: (_, __) => const AuditLogPage()),
          GoRoute(path: '/admin/reports', builder: (_, __) => const ReportsPage()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const SettingsPage()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('الصفحة غير موجودة: ${state.error}')),
    ),
  );
});
