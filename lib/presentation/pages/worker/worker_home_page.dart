import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../widgets/admin/admin_login_dialog.dart';
import '../../providers/theme_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../widgets/common/offline_banner.dart';
import 'batch_entry_page.dart';
import 'machine_entry_page.dart';
import 'shift_handover_page.dart';
import '../admin/warehouse/warehouse_manager_page.dart';

class WorkerHomePage extends ConsumerStatefulWidget {
  const WorkerHomePage({super.key});

  @override
  ConsumerState<WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends ConsumerState<WorkerHomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    BatchEntryPage(),
    MachineEntryPage(),
    ShiftHandoverPage(),
    _AppInfoPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
            tooltip: 'تغيير المظهر',
          ),
        ],
      ),
      drawer: _WorkerDrawer(
        selectedIndex: _selectedIndex,
        onNavigate: (index) {
          Navigator.pop(context); // أغلق الدرج أولاً
          setState(() => _selectedIndex = index);
        },
        onAdminAccess: () => _showAdminLogin(),
      ),
      body: OfflineBannerWrapper(child: _pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.blender_outlined),
            selectedIcon: Icon(Icons.blender),
            label: AppStrings.batchEntry,
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: AppStrings.machineEntry,
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'تسليم الوردية',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outlined),
            selectedIcon: Icon(Icons.info),
            label: AppStrings.appInfo,
          ),
        ],
      ),
    );
  }

  void _showAdminLogin() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdminLoginDialog(
        onSuccess: () {
          // Close the dialog — the router's refreshListenable
          // detects isAdmin=true and redirects to /admin automatically.
          Navigator.of(ctx, rootNavigator: true).pop();
        },
      ),
    );
  }
}

class _WorkerDrawer extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onNavigate;
  final VoidCallback onAdminAccess;

  const _WorkerDrawer({
    required this.selectedIndex,
    required this.onNavigate,
    required this.onAdminAccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: Column(
        children: [
          // ── رأس الدرج ─────────────────────────────────────────
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
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.factory, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  AppStrings.appName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // ── عناصر التنقل ──────────────────────────────────────
          _DrawerItem(
            icon: Icons.blender_outlined,
            selectedIcon: Icons.blender,
            label: AppStrings.batchEntry,
            selected: selectedIndex == 0,
            onTap: () => onNavigate(0),
          ),
          _DrawerItem(
            icon: Icons.precision_manufacturing_outlined,
            selectedIcon: Icons.precision_manufacturing,
            label: AppStrings.machineEntry,
            selected: selectedIndex == 1,
            onTap: () => onNavigate(1),
          ),
          _DrawerItem(
            icon: Icons.swap_horiz_outlined,
            selectedIcon: Icons.swap_horiz,
            label: 'تسليم الوردية',
            selected: selectedIndex == 2,
            onTap: () => onNavigate(2),
          ),
          _DrawerItem(
            icon: Icons.info_outline,
            selectedIcon: Icons.info,
            label: AppStrings.appInfo,
            selected: selectedIndex == 3,
            onTap: () => onNavigate(3),
          ),
          const Spacer(),
          const Divider(),
          // ── أمين المخزن ────────────────────────────────────────
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warehouse, color: Colors.teal, size: 22),
            ),
            title: const Text(
              'لوحة أمين المخزن',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal),
            ),
            subtitle: const Text('سندات الاستلام والتحويل', style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: const Text('المخزن الرئيسي — أمين المخزن'),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    body: const WarehouseManagerPage(),
                  ),
                ),
              );
            },
          ),
          const Divider(),
          // ── لوحة الإدارة ──────────────────────────────────────
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings,
                  color: Color(0xFF1565C0), size: 22),
            ),
            title: const Text(
              'لوحة الإدارة',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
            ),
            subtitle: const Text('تسجيل الدخول كمسؤول',
                style: TextStyle(fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              onAdminAccess();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              AppStrings.appVersion,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── عنصر درج مع تمييز المحدد ──────────────────────────────────────────────
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : null;
    return ListTile(
      leading: Icon(selected ? selectedIcon : icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          color: color,
        ),
      ),
      selected: selected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}

class _AppInfoPage extends StatelessWidget {
  const _AppInfoPage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.factory,
              size: 70,
              color: Theme.of(context).primaryColor,
            ),
          ).animate().scale(duration: 500.ms),
          const SizedBox(height: 24),
          Text(
            AppStrings.appName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'نظام ERP متكامل لإدارة مصنع البلاستيك',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _InfoCard(
            icon: Icons.blender,
            title: 'إدخال الطبخات',
            description: 'تسجيل كميات المواد الخام لكل طبخة مع صورة الميزان',
          ),
          _InfoCard(
            icon: Icons.precision_manufacturing,
            title: 'إدخال الماكينات',
            description: 'تسجيل الإنتاج اليومي للماكينات مع السكراب والهالك',
          ),
          _InfoCard(
            icon: Icons.lock_outline,
            title: 'بيانات محمية',
            description: 'السجلات لا يمكن تعديلها بعد الحفظ',
          ),
          const SizedBox(height: 24),
          Text(
            AppStrings.appVersion,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ].animate(interval: 100.ms).fadeIn().slideY(begin: 0.1, end: 0),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _InfoCard({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Theme.of(context).primaryColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description),
      ),
    );
  }
}
