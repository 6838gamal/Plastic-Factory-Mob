import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProductionManagerHomePage extends StatelessWidget {
  const ProductionManagerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
        icon: Icons.inventory_2,
        title: 'المخزون',
        subtitle: 'عرض وإدارة المخزون الحالي',
        route: '/production-manager/inventory',
        color: Colors.deepOrange,
      ),
      _MenuItem(
        icon: Icons.science,
        title: 'المواد الخام',
        subtitle: 'قائمة المواد الخام وبياناتها',
        route: '/production-manager/materials',
        color: Colors.orange,
      ),
      _MenuItem(
        icon: Icons.account_balance_wallet,
        title: 'الأرصدة الافتتاحية',
        subtitle: 'تسجيل وعرض الأرصدة الافتتاحية',
        route: '/production-manager/opening-balances',
        color: Colors.amber.shade700,
      ),
      _MenuItem(
        icon: Icons.fact_check,
        title: 'الجرد الدوري',
        subtitle: 'تسجيل جرد المواد والمنتجات',
        route: '/production-manager/stock-take',
        color: Colors.brown,
      ),
      _MenuItem(
        icon: Icons.warehouse,
        title: 'المخزن الرئيسي',
        subtitle: 'إدارة حركة المخزن الرئيسي',
        route: '/production-manager/warehouse-manager',
        color: Colors.deepOrange.shade800,
      ),
      _MenuItem(
        icon: Icons.blender,
        title: 'مخزن الخلطات',
        subtitle: 'إدارة مخزن الخلطات والتحويلات',
        route: '/production-manager/mixing-warehouse',
        color: Colors.red.shade700,
      ),
    ];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'إدارة المخزون',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر القسم الذي تريد إدارته',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 120,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _MenuCard(item: item);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color color;
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
  });
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
