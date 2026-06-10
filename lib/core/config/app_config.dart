class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://plastic-factory-api.onrender.com',
  );

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  static const String appVersion = '1.0.0';
  static const String appName = 'نظام إدارة مصنع البلاستيك';
}
