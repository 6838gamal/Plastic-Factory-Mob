import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static String get apiBaseUrl {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && origin != 'null') {
          return origin;
        }
      } catch (_) {}
    }

    const injected = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );

    if (injected.isNotEmpty) {
      return injected;
    }

    return 'https://plastic-factory-api.onrender.com';
  }

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  static const String appVersion = '1.0.0';
  static const String appName = 'نظام إدارة مصنع البلاستيك';
}
