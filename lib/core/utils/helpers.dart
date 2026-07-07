import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class Helpers {
  static final _uuid = const Uuid();
  static final _dateFormat = DateFormat('yyyy-MM-dd', 'ar');
  static final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm', 'ar');
  static final _numberFormat = NumberFormat('#,##0.##', 'ar');

  static String generateTransactionId() => _uuid.v4();

  static String formatDate(DateTime date) => _dateFormat.format(date);

  static String formatDateTime(DateTime date) => _dateTimeFormat.format(date);

  static String formatNumber(double number) => _numberFormat.format(number);

  static String formatWeight(double kg) {
    if (kg >= 1000) {
      return '${_numberFormat.format(kg / 1000)} طن';
    }
    return '${_numberFormat.format(kg)} كجم';
  }

  /// Converts [value] from [unit] to kilograms.
  /// 'قطعة' and unknown units return the value unchanged.
  static double toKg(double value, String unit) {
    switch (unit.trim()) {
      case 'طن':
        return value * 1000;
      case 'جرام':
      case 'غرام':
        return value / 1000;
      default:
        return value; // كجم, كيلو, لتر, قطعة, etc.
    }
  }

  /// Returns a display string with the quantity converted to كجم.
  /// For non-كجم units (except قطعة), appends the original value in parentheses.
  /// Examples:
  ///   (25, 'طن')    → "25,000 كجم (25 طن)"
  ///   (500, 'جرام') → "0.5 كجم (500 جرام)"
  ///   (22.5, 'لتر') → "22.5 كجم (22.5 لتر)"
  ///   (22.5, 'كجم') → "22.5 كجم"
  ///   (5, 'قطعة')   → "5 قطعة"
  static String formatQuantityInKg(double value, String unit) {
    final u = unit.trim();
    if (u == 'قطعة') {
      return '${_numberFormat.format(value)} قطعة';
    }
    final kg = toKg(value, u);
    final kgStr = '${_numberFormat.format(kg)} كجم';
    if (u == 'كجم' || u == 'كيلو') {
      return kgStr;
    }
    return '$kgStr (${_numberFormat.format(value)} $u)';
  }

  /// Compact variant — only shows the kg value (no parenthetical).
  /// Useful for small chips and tight UI spaces.
  static String formatQuantityInKgCompact(double value, String unit) {
    final u = unit.trim();
    if (u == 'قطعة') {
      return '${_numberFormat.format(value)} قطعة';
    }
    final kg = toKg(value, u);
    return '${_numberFormat.format(kg)} كجم';
  }

  static String formatPercentage(double value) => '${value.toStringAsFixed(2)}%';

  static Color getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFB71C1C);
      case 'high':
        return const Color(0xFFE65100);
      case 'medium':
        return const Color(0xFFF9A825);
      case 'low':
        return const Color(0xFF1B5E20);
      default:
        return const Color(0xFF757575);
    }
  }

  static String getSeverityText(String severity) {
    switch (severity) {
      case 'critical':
        return 'حرج';
      case 'high':
        return 'عالي';
      case 'medium':
        return 'متوسط';
      case 'low':
        return 'منخفض';
      default:
        return severity;
    }
  }

  static String getAlertTypeText(String type) {
    const map = {
      'low_stock': 'مخزون منخفض',
      'insufficient_stock': 'مخزون غير كاف',
      'excess_consumption': 'استهلاك زائد',
      'low_consumption': 'استهلاك ناقص',
      'production_deviation': 'انحراف إنتاج',
      'industrial_deviation': 'انحراف صناعي',
      'high_waste': 'هالك مرتفع',
      'high_scrap': 'سكراب مرتفع',
      'machine_stop': 'توقف ماكينة',
      'process_failed': 'فشل عملية',
      'yield_deviation': 'انحراف معيار الإنتاج',
    };
    return map[type] ?? type;
  }

  static double calculateDeviation(double input, double output, double scrap, double waste) {
    if (input == 0) return 0;
    final totalOutput = output + scrap + waste;
    return ((input - totalOutput) / input) * 100;
  }

  static double calculateScrapBalance(double previousBalance, double produced, double used) {
    return previousBalance + produced - used;
  }

  static String friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network') ||
        msg.contains('connection refused') ||
        msg.contains('os error')) {
      return 'تعذّر الاتصال بالخادم.\nتحقق من الاتصال بالإنترنت.';
    }
    if (msg.contains('timeoutexception') || msg.contains('timeout')) {
      return 'انتهت مهلة الاتصال.\nيرجى المحاولة مجدداً.';
    }
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'انتهت جلسة العمل.\nيرجى إعادة تسجيل الدخول.';
    }
    if (msg.contains('403') || msg.contains('forbidden')) {
      return 'ليس لديك صلاحية للوصول لهذه البيانات.';
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return 'البيانات المطلوبة غير موجودة.';
    }
    if (msg.contains('500') || msg.contains('internal server')) {
      return 'خطأ في الخادم.\nيرجى المحاولة مجدداً لاحقاً.';
    }
    if (msg.contains('xmlhttprequest') || msg.contains('cors') || msg.contains('fetch')) {
      return 'تعذّر الوصول للخادم.\nيرجى المحاولة مجدداً.';
    }
    return 'تعذّر تحميل البيانات.\nيرجى المحاولة مجدداً.';
  }
}
