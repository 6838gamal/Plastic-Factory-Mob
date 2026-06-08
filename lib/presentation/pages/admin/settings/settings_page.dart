import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/reference_models.dart';
import '../../../../data/models/raw_material_model.dart';
import '../../../providers/auth_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isSeeding = false;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('المظهر'),
        Card(
          child: SwitchListTile(
            title: const Text('الوضع الداكن'),
            subtitle: const Text('تبديل بين الوضع الفاتح والداكن'),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (v) => ref.read(themeProvider.notifier).setTheme(v ? ThemeMode.dark : ThemeMode.light),
          ),
        ),

        const SizedBox(height: 16),
        _SectionTitle('إعداد البيانات المرجعية'),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.science),
                title: const Text('المواد الخام الافتراضية'),
                subtitle: const Text('إنشاء المواد الخام الأساسية للمصنع'),
                trailing: _isSeeding
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: _seedMaterials,
                        child: const Text('إنشاء'),
                      ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('إضافة عمال'),
                subtitle: const Text('إضافة عمال المصنع'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddWorkerDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: const Text('إضافة ماكينات'),
                subtitle: const Text('إضافة ماكينات الإنتاج'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddMachineDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.blender),
                title: const Text('إضافة خلاطات'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddMixerDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('أنواع الخلطات'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddMixtureTypeDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.shopping_bag),
                title: const Text('المنتجات'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddProductDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _SectionTitle('معلومات التطبيق'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('اسم النظام'),
                trailing: Text('نظام ERP مصنع البلاستيك'),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.verified),
                title: Text('الإصدار'),
                trailing: Text('1.0.0'),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.storage),
                title: Text('قاعدة البيانات'),
                trailing: Text('PostgreSQL'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _seedMaterials() async {
    setState(() => _isSeeding = true);
    final ds = ref.read(dataSourceProvider);
    try {
      for (final mat in RawMaterialModel.defaultMaterials) {
        await ds.upsertRawMaterial({...mat, 'is_active': true});
      }
      ref.invalidate(rawMaterialsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء المواد الخام بنجاح'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isSeeding = false);
  }

  void _showAddWorkerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة عامل'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertWorker({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(workersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAddMachineDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ماكينة'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الماكينة *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertMachine({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(machinesProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAddMixerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة خلاط'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الخلاط *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertMixer({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(mixersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAddMixtureTypeDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة نوع خلطة'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الخلطة *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertMixtureType({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(mixtureTypesProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة منتج'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنتج *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref.read(dataSourceProvider).upsertProduct({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(productsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).primaryColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
