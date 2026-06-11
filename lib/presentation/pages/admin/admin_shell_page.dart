import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../widgets/common/offline_banner.dart';

Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: const Text('هل تريد تسجيل الخروج من لوحة الإدارة؟\nستحتاج إلى كلمة المرور للدخول مجدداً.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await ref.read(authProvider.notifier).signOut();
    // Explicit navigation as safety net — GoRouter redirect also fires.
    if (context.mounted) context.go('/worker');
  }
}

class AdminShellPage extends ConsumerWidget {
  final Widget child;
  const AdminShellPage({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return PopScope(
      // Prevent Android/browser back button from returning to admin pages.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الإدارة'),
          actions: [
            IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: AppStrings.logout,
              onPressed: () => _confirmAndSignOut(context, ref),
            ),
          ],
        ),
        drawer: _AdminDrawer(),
        body: OfflineBannerWrapper(child: child),
      ),
    );
  }
}

class _AdminDrawer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.admin_panel_settings, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لوحة الإدارة',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  ref.watch(authProvider).user?.email ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DrawerItem(
                  icon: Icons.dashboard_outlined,
                  selectedIcon: Icons.dashboard,
                  title: AppStrings.dashboard,
                  route: '/admin',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                  title: AppStrings.inventory,
                  route: '/admin/inventory',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.science_outlined,
                  selectedIcon: Icons.science,
                  title: AppStrings.rawMaterials,
                  route: '/admin/materials',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.blender_outlined,
                  selectedIcon: Icons.blender,
                  title: AppStrings.batches,
                  route: '/admin/batches',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.precision_manufacturing_outlined,
                  selectedIcon: Icons.precision_manufacturing,
                  title: AppStrings.production,
                  route: '/admin/production',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.people_outline,
                  selectedIcon: Icons.people,
                  title: AppStrings.workers,
                  route: '/admin/workers',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.settings_input_component_outlined,
                  selectedIcon: Icons.settings_input_component,
                  title: AppStrings.machines,
                  route: '/admin/machines',
                  currentRoute: currentRoute,
                ),
                const Divider(),
                _DrawerItem(
                  icon: Icons.fact_check_outlined,
                  selectedIcon: Icons.fact_check,
                  title: 'الجرد الدوري',
                  route: '/admin/stock-take',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.menu_book_outlined,
                  selectedIcon: Icons.menu_book,
                  title: 'وصفات الخلطات',
                  route: '/admin/recipes',
                  currentRoute: currentRoute,
                ),
                const Divider(),
                _DrawerItem(
                  icon: Icons.warning_amber_outlined,
                  selectedIcon: Icons.warning_amber,
                  title: AppStrings.alerts,
                  route: '/admin/alerts',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.history_outlined,
                  selectedIcon: Icons.history,
                  title: AppStrings.auditLog,
                  route: '/admin/audit',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.bar_chart_outlined,
                  selectedIcon: Icons.bar_chart,
                  title: AppStrings.reports,
                  route: '/admin/reports',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  title: AppStrings.settings,
                  route: '/admin/settings',
                  currentRoute: currentRoute,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.red.withOpacity(0.08),
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text(AppStrings.logout, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(context); // close drawer first
                await _confirmAndSignOut(context, ref);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String route;
  final String currentRoute;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.route,
    required this.currentRoute,
  });

  bool get _isSelected => currentRoute == route || (route != '/admin' && currentRoute.startsWith(route));

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: _isSelected,
      selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
      selectedColor: Theme.of(context).primaryColor,
      leading: Icon(_isSelected ? selectedIcon : icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
    );
  }
}
