import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/pages/splash/splash_page.dart';
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
import '../../presentation/pages/admin/inventory/stock_take_page.dart';
import '../../presentation/pages/admin/recipes/recipe_management_page.dart';
import '../../presentation/pages/admin/shift_handover/shift_handovers_admin_page.dart';
import '../../presentation/pages/admin/inventory/opening_balances_page.dart';
import '../../presentation/pages/admin/warehouse/warehouse_manager_page.dart';
import '../../presentation/pages/admin/warehouse/mixing_warehouse_page.dart';
import '../../presentation/providers/auth_provider.dart';

/// A ChangeNotifier that fires whenever auth state changes,
/// so GoRouter re-evaluates its redirect without recreating the router.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final _authRefreshProvider = ChangeNotifierProvider<_AuthRefreshNotifier>(
  (ref) => _AuthRefreshNotifier(ref),
);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authRefreshProvider);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final path = state.uri.toString();
      // Never redirect away from the splash screen — it handles its own nav
      if (path.startsWith('/splash')) return null;

      final isAdmin = ref.read(authProvider).isAdmin;
      final onAdmin = path.startsWith('/admin');
      if (onAdmin && !isAdmin) return '/worker';
      if (isAdmin && !onAdmin) return '/admin';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
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
          GoRoute(path: '/admin/stock-take', builder: (_, __) => const StockTakePage()),
          GoRoute(path: '/admin/recipes', builder: (_, __) => const RecipeManagementPage()),
          GoRoute(path: '/admin/shift-handover', builder: (_, __) => const ShiftHandoversAdminPage()),
          GoRoute(path: '/admin/opening-balances', builder: (_, __) => const OpeningBalancesPage()),
          GoRoute(path: '/admin/warehouse-manager', builder: (_, __) => const WarehouseManagerPage()),
          GoRoute(path: '/admin/mixing-warehouse', builder: (_, __) => const MixingWarehousePage()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('الصفحة غير موجودة: ${state.error}')),
    ),
  );

  return router;
});
