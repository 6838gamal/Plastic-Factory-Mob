import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../../core/config/app_config.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  int _attempt = 0;
  String _statusMessage = 'جاري الاتصال بالخادم...';
  bool _connected = false;
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _startHealthCheck();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  Future<void> _startHealthCheck() async {
    while (mounted && !_connected) {
      _attempt++;
      setState(() {
        _statusMessage = _attempt == 1
            ? 'جاري الاتصال بالخادم...'
            : 'إعادة المحاولة رقم $_attempt...';
      });

      try {
        final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/health');
        final res = await http.get(uri).timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          if (body['status'] == 'ok') {
            if (mounted) {
              setState(() {
                _connected = true;
                _statusMessage = 'تم الاتصال بنجاح ✓';
              });
              await Future.delayed(const Duration(milliseconds: 600));
              if (mounted) context.go('/worker');
            }
            return;
          }
        }
      } catch (_) {}

      if (mounted && !_connected) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.precision_manufacturing_rounded,
                  size: 54,
                  color: primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'مصنع البلاستيك',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'نظام إدارة الإنتاج',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _statusMessage,
                  key: ValueKey(_statusMessage),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _connected
                        ? Colors.green.shade600
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              if (!_connected)
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    backgroundColor: primary.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                    minHeight: 3,
                  ),
                )
              else
                Icon(Icons.check_circle_outline,
                    color: Colors.green.shade600, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
