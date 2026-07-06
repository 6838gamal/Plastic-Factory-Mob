import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          child:
              const Text('تسجيل الخروج', style: TextStyle(color: Colors.white)),
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
              onPressed: () =>
                  _confirmAndSignOutWarehouse(context, ref),
            ),
          ],
        ),
        body: OfflineBannerWrapper(child: child),
      ),
    );
  }
}
