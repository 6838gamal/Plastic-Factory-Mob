import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/reference_data_provider.dart';
import '../../../../data/datasources/api_datasource.dart';
import '../../../../data/models/reference_models.dart';
import '../../../../data/models/raw_material_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/batch_provider.dart';
import '../audit/audit_log_page.dart' show auditLogProvider;

final _smsSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getSmsSettings();
});

final _warehouseAccountProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final ds = ref.read(dataSourceProvider);
  return ds.getWarehouseAccount();
});

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
    final authState = ref.watch(authProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── المظهر ──────────────────────────────────────────────
        _SectionTitle('المظهر'),
        Card(
          child: SwitchListTile(
            title: const Text('الوضع الداكن'),
            subtitle: const Text('تبديل بين الوضع الفاتح والداكن'),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (v) => ref.read(themeProvider.notifier).setTheme(
                v ? ThemeMode.dark : ThemeMode.light),
          ),
        ),

        const SizedBox(height: 16),

        // ── إدارة الحساب ────────────────────────────────────────
        _SectionTitle('إدارة الحساب'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.email_outlined, color: Colors.blue),
                title: const Text('تغيير البريد الإلكتروني'),
                subtitle: Text(authState.user?.email ?? '—',
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () => _showChangeEmailDialog(context),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.orange),
                title: const Text('تغيير كلمة المرور'),
                subtitle: const Text('يتطلب كلمة المرور الحالية'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () => _showChangePasswordDialog(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── حساب أمين المخزن ────────────────────────────────────
        _SectionTitle('حساب أمين المخزن'),
        ref.watch(_warehouseAccountProvider).when(
          data: (info) {
            final exists = info['exists'] as bool? ?? false;
            final email = info['email'] as String?;
            final name = info['name'] as String?;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warehouse, color: Colors.teal),
                    ),
                    title: const Text('أمين المخزن الرئيسي'),
                    subtitle: exists
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (name?.isNotEmpty == true)
                                Text(name!,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.teal,
                                        fontWeight: FontWeight.w600)),
                              Text(email ?? '—',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600])),
                            ],
                          )
                        : const Text('لم يُنشأ الحساب بعد',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange)),
                    trailing: exists
                        ? const Icon(Icons.verified_user,
                            color: Colors.teal, size: 18)
                        : const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 18),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.blue, size: 20),
                    title: Text(exists ? 'تعديل بيانات أمين المخزن' : 'إنشاء الحساب'),
                    subtitle: const Text('الاسم والبريد الإلكتروني'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => _showWarehouseEmailDialog(context, email ?? '', currentName: name ?? ''),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(Icons.lock_reset,
                        color: Colors.orange, size: 20),
                    title: const Text('تغيير كلمة المرور'),
                    subtitle: const Text('تعيين كلمة مرور جديدة لأمين المخزن'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () =>
                        _showWarehousePasswordDialog(context, email ?? ''),
                  ),
                ],
              ),
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text('خطأ في تحميل حساب أمين المخزن: $e'),
              trailing: ElevatedButton(
                onPressed: () => ref.invalidate(_warehouseAccountProvider),
                child: const Text('إعادة'),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── إشعارات SMS ─────────────────────────────────────────
        _SectionTitle('إشعارات SMS'),
        ref.watch(_smsSettingsProvider).when(
          data: (settings) => _SmsSettingsCard(
            settings: settings,
            onSaved: () => ref.invalidate(_smsSettingsProvider),
          ),
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text('خطأ في تحميل إعدادات SMS: $e'),
              trailing: ElevatedButton(
                onPressed: () => ref.invalidate(_smsSettingsProvider),
                child: const Text('إعادة'),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── البيانات المرجعية ────────────────────────────────────
        _SectionTitle('إعداد البيانات المرجعية'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.science),
                title: const Text('المواد الخام الافتراضية'),
                subtitle: const Text('إنشاء المواد الخام الأساسية للمصنع'),
                trailing: _isSeeding
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: _seedMaterials,
                        child: const Text('إنشاء'),
                      ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('إضافة عمال'),
                trailing: ElevatedButton(
                  onPressed: () => _showAddWorkerDialog(context),
                  child: const Text('إضافة'),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: const Text('إضافة ماكينات'),
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

        // ── منطقة الخطر ──────────────────────────────────────────
        _SectionTitle('منطقة الخطر'),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.red.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'هذه الإجراءات تحذف البيانات نهائيًا من قاعدة البيانات ولا يمكن التراجع عنها',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined, color: Colors.red),
                title: const Text('تصفير التحذيرات'),
                subtitle: const Text('حذف جميع التحذيرات (معلقة/مؤكدة/محلولة)'),
                trailing: TextButton(
                  onPressed: () => _confirmAndClear(
                    context: context,
                    title: 'تصفير التحذيرات',
                    message: 'سيتم حذف جميع التحذيرات نهائيًا من قاعدة البيانات. هل أنت متأكد؟',
                    action: () => ref.read(dataSourceProvider).deleteAllAlerts(),
                    onDone: () {
                      ref.invalidate(alertsProvider(const AlertFilters(status: 'pending')));
                      ref.invalidate(alertsProvider(const AlertFilters(status: 'acknowledged')));
                      ref.invalidate(alertsProvider(const AlertFilters(status: 'resolved')));
                    },
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('تصفير'),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.summarize_outlined, color: Colors.red),
                title: const Text('تصفير التقارير اليومية'),
                subtitle: const Text('حذف جميع التقارير اليومية المُنشأة'),
                trailing: TextButton(
                  onPressed: () => _confirmAndClear(
                    context: context,
                    title: 'تصفير التقارير',
                    message: 'سيتم حذف جميع التقارير اليومية نهائيًا من قاعدة البيانات. هل أنت متأكد؟',
                    action: () => ref.read(dataSourceProvider).deleteAllDailyReports(),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('تصفير'),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.history_toggle_off, color: Colors.red),
                title: const Text('تصفير سجل العمليات'),
                subtitle: const Text('حذف جميع سجلات التدقيق (Audit Log)'),
                trailing: TextButton(
                  onPressed: () => _confirmAndClear(
                    context: context,
                    title: 'تصفير سجل العمليات',
                    message: 'سيتم حذف جميع سجلات التدقيق نهائيًا من قاعدة البيانات. هل أنت متأكد؟',
                    action: () => ref.read(dataSourceProvider).deleteAuditLogs(),
                    onDone: () => ref.invalidate(auditLogProvider),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('تصفير'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── معلومات التطبيق ──────────────────────────────────────
        _SectionTitle('معلومات التطبيق'),
        Card(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('اسم النظام'),
                trailing: Text('نظام ERP مصنع البلاستيك'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.verified),
                title: Text('الإصدار'),
                trailing: Text('1.0.0'),
              ),
              Divider(),
              ListTile(
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

  // ── تغيير البريد ──────────────────────────────────────────────
  void _showChangeEmailDialog(BuildContext context) {
    final newEmailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.email_outlined, color: Colors.blue),
            SizedBox(width: 8),
            Text('تغيير البريد الإلكتروني'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني الجديد',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => ss(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (newEmailCtrl.text.trim().isEmpty ||
                    passwordCtrl.text.isEmpty) {
                  ss(() => errorMsg = 'يرجى ملء جميع الحقول');
                  return;
                }
                final success = await ref
                    .read(authProvider.notifier)
                    .changeEmail(passwordCtrl.text, newEmailCtrl.text.trim());
                if (success) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم تغيير البريد الإلكتروني بنجاح'),
                        backgroundColor: Colors.green));
                  }
                } else {
                  ss(() => errorMsg =
                      ref.read(authProvider).error ?? 'حدث خطأ');
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // ── تغيير كلمة المرور ─────────────────────────────────────────
  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.lock_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('تغيير كلمة المرور'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => ss(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  prefixIcon: const Icon(Icons.lock_open_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => ss(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور الجديدة',
                  prefixIcon: Icon(Icons.check_circle_outline),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (currentCtrl.text.isEmpty || newCtrl.text.isEmpty) {
                  ss(() => errorMsg = 'يرجى ملء جميع الحقول');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  ss(() => errorMsg = 'كلمة المرور الجديدة غير متطابقة');
                  return;
                }
                if (newCtrl.text.length < 6) {
                  ss(() => errorMsg = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
                  return;
                }
                final success = await ref
                    .read(authProvider.notifier)
                    .changePassword(currentCtrl.text, newCtrl.text);
                if (success) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم تغيير كلمة المرور بنجاح'),
                        backgroundColor: Colors.green));
                  }
                } else {
                  ss(() => errorMsg =
                      ref.read(authProvider).error ?? 'حدث خطأ');
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // ── حساب أمين المخزن — تعديل البريد والاسم ───────────────────
  void _showWarehouseEmailDialog(BuildContext context, String currentEmail, {String currentName = ''}) {
    final nameCtrl = TextEditingController(text: currentName);
    final emailCtrl = TextEditingController(text: currentEmail);
    final passCtrl = TextEditingController();
    bool obscure = true;
    String? errorMsg;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warehouse, color: Colors.teal),
            SizedBox(width: 8),
            Text('بيانات أمين المخزن'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل لأمين المخزن *',
                  prefixIcon: Icon(Icons.person_outlined),
                  border: OutlineInputBorder(),
                  helperText: 'يظهر في سندات الاستلام',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني *',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة *',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => ss(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: loading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final email = emailCtrl.text.trim();
                      final pass = passCtrl.text;
                      if (name.isEmpty || email.isEmpty || pass.isEmpty) {
                        ss(() => errorMsg = 'يرجى ملء جميع الحقول');
                        return;
                      }
                      if (pass.length < 6) {
                        ss(() => errorMsg =
                            'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
                        return;
                      }
                      ss(() { loading = true; errorMsg = null; });
                      try {
                        await ref
                            .read(dataSourceProvider)
                            .upsertWarehouseAccount(email, pass, name: name);
                        ref.invalidate(_warehouseAccountProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'تم حفظ بيانات أمين المخزن بنجاح'),
                                  backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        ss(() {
                          loading = false;
                          errorMsg = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // ── حساب أمين المخزن — تغيير كلمة المرور فقط ─────────────────
  void _showWarehousePasswordDialog(BuildContext context, String currentEmail) {
    if (currentEmail.isEmpty) {
      _showWarehouseEmailDialog(context, '');
      return;
    }
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    String? errorMsg;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.lock_reset, color: Colors.orange),
            SizedBox(width: 8),
            Text('تغيير كلمة مرور أمين المخزن'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.person_outline,
                      color: Colors.teal, size: 16),
                  const SizedBox(width: 6),
                  Text(currentEmail,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.teal)),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  prefixIcon: const Icon(Icons.lock_open_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => ss(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  prefixIcon: Icon(Icons.check_circle_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              onPressed: loading
                  ? null
                  : () async {
                      final pass = passCtrl.text;
                      final confirm = confirmCtrl.text;
                      if (pass.isEmpty || confirm.isEmpty) {
                        ss(() => errorMsg = 'يرجى ملء جميع الحقول');
                        return;
                      }
                      if (pass.length < 6) {
                        ss(() => errorMsg =
                            'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
                        return;
                      }
                      if (pass != confirm) {
                        ss(() => errorMsg = 'كلمة المرور غير متطابقة');
                        return;
                      }
                      ss(() { loading = true; errorMsg = null; });
                      try {
                        await ref
                            .read(dataSourceProvider)
                            .upsertWarehouseAccount(currentEmail, pass);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم تغيير كلمة المرور بنجاح'),
                                  backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        ss(() {
                          loading = false;
                          errorMsg = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // ── البيانات المرجعية ─────────────────────────────────────────
  Future<void> _seedMaterials() async {
    setState(() => _isSeeding = true);
    final ds = ref.read(dataSourceProvider);
    try {
      for (final mat in RawMaterialModel.defaultMaterials) {
        await ds.upsertRawMaterial({...mat, 'is_active': true});
      }
      ref.invalidate(rawMaterialsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إنشاء المواد الخام بنجاح'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
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
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'الاسم *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref
                  .read(dataSourceProvider)
                  .upsertWorker({'name': nameCtrl.text.trim(), 'is_active': true});
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
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الماكينة *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref
                  .read(dataSourceProvider)
                  .upsertMachine({'name': nameCtrl.text.trim(), 'is_active': true});
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
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الخلاط *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref
                  .read(dataSourceProvider)
                  .upsertMixer({'name': nameCtrl.text.trim(), 'is_active': true});
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
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الخلطة *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref
                  .read(dataSourceProvider)
                  .upsertMixtureType({'name': nameCtrl.text.trim(), 'is_active': true});
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
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم المنتج *')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await ref
                  .read(dataSourceProvider)
                  .upsertProduct({'name': nameCtrl.text.trim(), 'is_active': true});
              ref.invalidate(productsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // ── منطقة الخطر: تأكيد مزدوج قبل أي حذف نهائي ──────────────────
  Future<void> _confirmAndClear({
    required BuildContext context,
    required String title,
    required String message,
    required Future<int> Function() action,
    VoidCallback? onDone,
  }) async {
    final confirmCtrl = TextEditingController();
    bool confirmedFirst = false;

    final firstStep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ]),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (firstStep != true) return;
    confirmedFirst = true;

    if (!confirmedFirst || !context.mounted) return;

    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('تأكيد نهائي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اكتب "حذف" لتأكيد العملية:'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => ss(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: confirmCtrl.text.trim() == 'حذف'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('حذف نهائيًا'),
            ),
          ],
        ),
      ),
    );
    if (finalConfirm != true) return;

    try {
      final deleted = await action();
      onDone?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم الحذف بنجاح ($deleted سجل)'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}

// ══════════════════════════════════════════════════════
// SMS Settings Card
// ══════════════════════════════════════════════════════
class _SmsSettingsCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onSaved;
  const _SmsSettingsCard({required this.settings, required this.onSaved});

  @override
  ConsumerState<_SmsSettingsCard> createState() => _SmsSettingsCardState();
}

class _SmsSettingsCardState extends ConsumerState<_SmsSettingsCard> {
  late bool _enabled;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _phonesCtrl;
  late TextEditingController _deviceCtrl;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings['sms_enabled'] == 'true';
    _apiKeyCtrl =
        TextEditingController(text: widget.settings['sms_api_key'] ?? '');
    _phonesCtrl =
        TextEditingController(text: widget.settings['sms_phone_numbers'] ?? '');
    _deviceCtrl =
        TextEditingController(text: widget.settings['sms_device_id'] ?? '0');
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _phonesCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.updateSmsSettings({
        'sms_enabled': _enabled ? 'true' : 'false',
        'sms_api_key': _apiKeyCtrl.text.trim(),
        'sms_phone_numbers': _phonesCtrl.text.trim(),
        'sms_device_id': _deviceCtrl.text.trim().isEmpty
            ? '0'
            : _deviceCtrl.text.trim(),
      });
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم حفظ إعدادات SMS'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _saving = false);
  }

  Future<void> _testSms() async {
    if (_apiKeyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أدخل مفتاح API أولاً'),
          backgroundColor: Colors.orange));
      return;
    }
    if (_phonesCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أدخل رقم هاتف أولاً'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() => _testing = true);
    try {
      await _save();
      final ds = ref.read(dataSourceProvider);
      final result = await ds.sendTestSms('اختبار النظام');
      if (mounted) {
        final sent = result['sent'] as int? ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(sent > 0 ? '✅ تم إرسال الرسالة بنجاح' : '❌ فشل إرسال الرسالة'),
            backgroundColor: sent > 0 ? Colors.green : Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sms_outlined, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إشعارات SMS',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('إرسال تنبيهات عبر sms-gateway.app',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            const Divider(),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'مفتاح API',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
                helperText: 'مفتاح API من لوحة تحكم sms-gateway.app',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phonesCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'أرقام الهواتف',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText: 'أرقام مفصولة بفاصلة  مثال: +9665XXXXXXXX,+9665XXXXXXXX',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'معرّف الجهاز (Device ID)',
                prefixIcon: Icon(Icons.phone_android_outlined),
                helperText: 'رقم الجهاز في SMS Gateway (افتراضي: 0)',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testSms,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: const Text('إرسال اختباري'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined),
                    label: const Text('حفظ الإعدادات'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
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
