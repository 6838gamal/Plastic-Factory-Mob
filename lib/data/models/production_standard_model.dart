class ProductionStandardModel {
  final String id;
  final String productName;
  final String? productCode;
  final double standardGramPerPair;
  final double standardKgPerPair;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductionStandardModel({
    required this.id,
    required this.productName,
    this.productCode,
    required this.standardGramPerPair,
    required this.standardKgPerPair,
    required this.isActive,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductionStandardModel.fromJson(Map<String, dynamic> json) =>
      ProductionStandardModel(
        id: json['id'] as String,
        productName: json['product_name'] as String,
        productCode: json['product_code'] as String?,
        standardGramPerPair:
            (json['standard_gram_per_pair'] as num?)?.toDouble() ?? 0,
        standardKgPerPair:
            (json['standard_kg_per_pair'] as num?)?.toDouble() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'product_code': productCode,
        'standard_gram_per_pair': standardGramPerPair,
        'is_active': isActive,
        'notes': notes,
      };
}

/// Result of yield computation shown live in the machine entry form.
class YieldStats {
  final double actualGramPerPair;
  final double standardGramPerPair;
  final double deviationPct;
  final WasteIndicator indicator;

  const YieldStats({
    required this.actualGramPerPair,
    required this.standardGramPerPair,
    required this.deviationPct,
    required this.indicator,
  });
}

enum WasteIndicator { normal, warning, critical }

extension WasteIndicatorExt on WasteIndicator {
  String get label {
    switch (this) {
      case WasteIndicator.normal:
        return 'ضمن المعيار';
      case WasteIndicator.warning:
        return 'تجاوز بسيط';
      case WasteIndicator.critical:
        return 'هدر حرج';
    }
  }

  String get arabicStatus {
    switch (this) {
      case WasteIndicator.normal:
        return 'Normal';
      case WasteIndicator.warning:
        return 'Warning';
      case WasteIndicator.critical:
        return 'Critical Waste';
    }
  }

  int get colorValue {
    switch (this) {
      case WasteIndicator.normal:
        return 0xFF388E3C; // green
      case WasteIndicator.warning:
        return 0xFFF9A825; // yellow
      case WasteIndicator.critical:
        return 0xFFB71C1C; // red
    }
  }
}

WasteIndicator wasteIndicatorFromDeviation(double deviation) {
  if (deviation <= 0) return WasteIndicator.normal;
  if (deviation <= 5) return WasteIndicator.warning;
  return WasteIndicator.critical;
}

WasteIndicator wasteIndicatorFromString(String? s) {
  switch (s) {
    case 'warning':
      return WasteIndicator.warning;
    case 'critical':
      return WasteIndicator.critical;
    default:
      return WasteIndicator.normal;
  }
}
