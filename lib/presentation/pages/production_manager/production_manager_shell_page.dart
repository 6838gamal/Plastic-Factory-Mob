import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/offline_banner.dart';

Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: const Text(
          'هل تريد تسجيل الخروج من لوحة مدير الإنتاج؟\nستحتاج إلى كلمة المرور للدخول مجدداً.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('تسجيل الخروج',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(authProvider.notifier).signOut();
  }
}

class ProductionManagerShellPage extends ConsumerWidget {
  final Widget child;
  const ProductionManagerShellPage({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة مدير الإنتاج'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'تسجيل الخروج',
              onPressed: () => _confirmAndSignOut(context, ref),
            ),
          ],
        ),
        drawer: _ProductionManagerDrawer(scaffoldContext: context),
        body: OfflineBannerWrapper(child: child),
      ),
    );
  }
}

class _ProductionManagerDrawer extends ConsumerWidget {
  final BuildContext scaffoldContext;
  const _ProductionManagerDrawer({required this.scaffoldContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepOrange, Color(0xFFBF360C)],
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
                  child: Icon(Icons.engineering, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'مدير الإنتاج',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
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
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  title: 'الرئيسية',
                  route: '/production-manager',
                  currentRoute: currentRoute,
                ),
                const Divider(),
                _DrawerItem(
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                  title: 'المخزون',
                  route: '/production-manager/inventory',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.science_outlined,
                  selectedIcon: Icons.science,
                  title: 'المواد الخام',
                  route: '/production-manager/materials',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.account_balance_wallet_outlined,
                  selectedIcon: Icons.account_balance_wallet,
                  title: 'الأرصدة الافتتاحية',
                  route: '/production-manager/opening-balances',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.fact_check_outlined,
                  selectedIcon: Icons.fact_check,
                  title: 'الجرد الدوري',
                  route: '/production-manager/stock-take',
                  currentRoute: currentRoute,
                ),
                const Divider(),
                _DrawerItem(
                  icon: Icons.warehouse_outlined,
                  selectedIcon: Icons.warehouse,
                  title: 'المخزن الرئيسي (عاصم)',
                  route: '/production-manager/warehouse-manager',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.swap_horiz_outlined,
                  selectedIcon: Icons.swap_horiz,
                  title: 'المخزن المرحلي',
                  route: '/production-manager/staging-warehouse',
                  currentRoute: currentRoute,
                ),
                _DrawerItem(
                  icon: Icons.blender_outlined,
                  selectedIcon: Icons.blender,
                  title: 'مخزن الخلطات',
                  route: '/production-manager/mixing-warehouse',
                  currentRoute: currentRoute,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.red.withOpacity(0.08),
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('تسجيل الخروج',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () => _confirmAndSignOut(scaffoldContext, ref),
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

  bool get _isSelected =>
      currentRoute == route ||
      (route != '/production-manager' && currentRoute.startsWith(route));

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: _isSelected,
      selectedTileColor: Colors.deepOrange.withOpacity(0.1),
      selectedColor: Colors.deepOrange,
      leading: Icon(_isSelected ? selectedIcon : icon),
      title: Text(title),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.go(route);
      },
    );
  }
}
