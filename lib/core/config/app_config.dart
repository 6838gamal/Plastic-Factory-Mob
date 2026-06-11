// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

class AppConfig {
  AppConfig._();

  static String get apiBaseUrl {
    try {
      final origin = html.window.location.origin;
      if (origin.isNotEmpty && origin != 'null') {
        return origin;
      }
    } catch (_) {}
    const injected = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (injected.isNotEmpty) return injected;
    return '';
  }

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  static const String appVersion = '1.0.0';
  static const String appName = 'نظام إدارة مصنع البلاستيك';
}
