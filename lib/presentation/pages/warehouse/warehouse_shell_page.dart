import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/common/offline_banner.dart';

Future<void> _confirmAndSignOutWarehouse(
    BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: const Text(
          'هل تريد تسجيل الخروج من لوحة أمين المخزن؟\nستحتاج إلى كلمة المرور للدخول مجدداً.'),
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
  }
}

class WarehouseShellPage extends ConsumerWidget {
  final Widget child;
  const WarehouseShellPage({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final location = GoRouterState.of(context).uri.toString();

    final displayName =
        (auth.user?.name != null && auth.user!.name!.isNotEmpty)
            ? auth.user!.name!
            : auth.user?.email ?? 'أمين المخزن';

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'لوحة أمين المخزن',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                displayName,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
              tooltip: 'تغيير المظهر',
              onPressed: () =>
                  ref.read(themeProvider.notifier).toggleTheme(),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'تسجيل الخروج',
              onPressed: () => _confirmAndSignOutWarehouse(context, ref),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────
                Container(
                  color: Colors.teal,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.warehouse_outlined,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const Text(
                        'أمين المخزن',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Nav items ────────────────────────────────────
                _DrawerItem(
                  icon: Icons.dashboard_outlined,
                  label: 'لوحة المخزن',
                  selected: location == '/warehouse',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/warehouse');
                  },
                ),
                _DrawerItem(
                  icon: Icons.science_outlined,
                  label: 'المواد الخام',
                  selected: location == '/warehouse/materials',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/warehouse/materials');
                  },
                ),
                const Spacer(),
                const Divider(),
                // ── Sign out ─────────────────────────────────────
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('تسجيل الخروج',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmAndSignOutWarehouse(context, ref);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        body: OfflineBannerWrapper(child: child),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? Colors.teal : null),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.teal : null,
          fontWeight: selected ? FontWeight.bold : null,
        ),
      ),
      selected: selected,
      selectedTileColor: Colors.teal.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap,
    );
  }
}
