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
      'high_waste': 'هالك مرتفع',
      'high_scrap': 'سكراب مرتفع',
      'machine_stop': 'توقف ماكينة',
      'process_failed': 'فشل عملية',
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
