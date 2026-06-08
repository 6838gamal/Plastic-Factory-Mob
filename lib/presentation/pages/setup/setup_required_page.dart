import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_strings.dart';

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_outlined, size: 60, color: Colors.orange),
              ),
              const SizedBox(height: 24),
              const Text(
                'إعداد قاعدة البيانات مطلوب',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'يحتاج التطبيق إلى الاتصال بـ Supabase.\nيرجى إضافة بيانات الاتصال في المتغيرات البيئية.',
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _StepCard(
                step: 1,
                title: 'إنشاء مشروع Supabase',
                description: 'انتقل إلى supabase.com وأنشئ مشروعاً جديداً مجاناً',
                icon: Icons.open_in_new,
              ),
              _StepCard(
                step: 2,
                title: 'إضافة المتغيرات البيئية (Secrets)',
                description: 'في Replit → Secrets، أضف المتغيرات التالية:',
                icon: Icons.key,
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SizedBox(height: 8),
                    _CodeChip('SUPABASE_URL'),
                    SizedBox(height: 4),
                    _CodeChip('SUPABASE_ANON_KEY'),
                  ],
                ),
              ),
              _StepCard(
                step: 3,
                title: 'تشغيل ملف قاعدة البيانات',
                description: 'افتح ملف schema.sql وشغّله في Supabase SQL Editor',
                icon: Icons.table_chart,
                extra: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: _CodeChip('schema.sql'),
                ),
              ),
              _StepCard(
                step: 4,
                title: 'إعادة بناء التطبيق',
                description: 'بعد إضافة المتغيرات، أعد تشغيل الـ workflow ليتصل بقاعدة البيانات',
                icon: Icons.refresh,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'بعد إضافة SUPABASE_URL و SUPABASE_ANON_KEY في Secrets وإعادة البناء، سيعمل التطبيق بالكامل.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final String title;
  final String description;
  final IconData icon;
  final Widget? extra;

  const _StepCard({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Text(
                '$step',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  if (extra != null) extra!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String text;
  const _CodeChip(this.text);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
