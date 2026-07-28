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
import '../../presentation/pages/admin/suppliers/suppliers_page.dart';
import '../../presentation/pages/admin/production_standards/production_standards_page.dart';
import '../../presentation/pages/admin/waste_monitoring/waste_monitoring_page.dart';
import '../../presentation/pages/warehouse/warehouse_shell_page.dart';
import '../../presentation/pages/warehouse/warehouse_home_page.dart';
import '../../presentation/pages/production_manager/production_manager_shell_page.dart';
import '../../presentation/pages/production_manager/production_manager_home_page.dart';
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

      final auth = ref.read(authProvider);
      final isAdmin = auth.isAdmin;
      final isWarehouseManager = auth.isWarehouseManager;
      final isProductionManager = auth.isProductionManager;
      final onAdmin = path.startsWith('/admin');
      final onWarehouse = path.startsWith('/warehouse');
      final onProductionManager = path.startsWith('/production-manager');

      // Protect admin routes
      if (onAdmin && !isAdmin) {
        if (isWarehouseManager) return '/warehouse';
        if (isProductionManager) return '/production-manager';
        return '/worker';
      }
      // Protect warehouse routes
      if (onWarehouse && !isWarehouseManager) {
        if (isAdmin) return '/admin';
        if (isProductionManager) return '/production-manager';
        return '/worker';
      }
      // Protect production manager routes
      if (onProductionManager && !isProductionManager) {
        if (isAdmin) return '/admin';
        if (isWarehouseManager) return '/warehouse';
        return '/worker';
      }
      // Redirect authenticated users away from /worker
      if (isAdmin && !onAdmin) return '/admin';
      if (isWarehouseManager && !onWarehouse) return '/warehouse';
      if (isProductionManager && !onProductionManager) return '/production-manager';

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
      // ── Warehouse manager section ────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            WarehouseShellPage(child: child),
        routes: [
          GoRoute(
            path: '/warehouse',
            builder: (_, __) => const WarehouseHomePage(),
          ),
          GoRoute(
            path: '/warehouse/materials',
            builder: (_, __) => Scaffold(
              appBar: AppBar(
                title: const Text('المواد الخام'),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                leading: BackButton(onPressed: () => _.go('/warehouse')),
              ),
              body: const MaterialsPage(),
            ),
          ),
        ],
      ),
      // ── Production manager section ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            ProductionManagerShellPage(child: child),
        routes: [
          GoRoute(
            path: '/production-manager',
            builder: (_, __) => const ProductionManagerHomePage(),
          ),
          GoRoute(
            path: '/production-manager/inventory',
            builder: (_, __) => const InventoryPage(),
          ),
          GoRoute(
            path: '/production-manager/materials',
            builder: (_, __) => const MaterialsPage(),
          ),
          GoRoute(
            path: '/production-manager/opening-balances',
            builder: (_, __) => const OpeningBalancesPage(),
          ),
          GoRoute(
            path: '/production-manager/stock-take',
            builder: (_, __) => const StockTakePage(),
          ),
          GoRoute(
            path: '/production-manager/warehouse-manager',
            builder: (_, __) => const WarehouseManagerPage(),
          ),
          GoRoute(
            path: '/production-manager/mixing-warehouse',
            builder: (_, __) => const MixingWarehousePage(),
          ),
        ],
      ),
      // ── Admin section ────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AdminShellPage(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardPage()),
          GoRoute(path: '/admin/workers', builder: (_, __) => const WorkersPage()),
          GoRoute(path: '/admin/machines', builder: (_, __) => const MachinesPage()),
          GoRoute(path: '/admin/batches', builder: (_, __) => const BatchesAdminPage()),
          GoRoute(path: '/admin/production', builder: (_, __) => const ProductionPage()),
          GoRoute(path: '/admin/alerts', builder: (_, __) => const AlertsPage()),
          GoRoute(path: '/admin/audit', builder: (_, __) => const AuditLogPage()),
          GoRoute(path: '/admin/reports', builder: (_, __) => const ReportsPage()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const SettingsPage()),
          GoRoute(path: '/admin/recipes', builder: (_, __) => const RecipeManagementPage()),
          GoRoute(path: '/admin/shift-handover', builder: (_, __) => const ShiftHandoversAdminPage()),
          GoRoute(
            path: '/admin/suppliers',
            builder: (_, __) => Scaffold(
              appBar: AppBar(
                title: const Text('الموردون'),
                leading: BackButton(onPressed: () => _.go('/admin')),
              ),
              body: const SuppliersPage(),
            ),
          ),
          GoRoute(
            path: '/admin/production-standards',
            builder: (_, __) => const ProductionStandardsPage(),
          ),
          GoRoute(
            path: '/admin/waste-monitoring',
            builder: (_, __) => const WasteMonitoringPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('الصفحة غير موجودة: ${state.error}')),
    ),
  );

  return router;
});
