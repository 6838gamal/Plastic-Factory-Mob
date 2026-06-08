class InventorySummaryModel {
  final String materialId;
  final String materialName;
  final String? code;
  final String unit;
  final double minStock;
  final double openingBalance;
  final double currentBalance;
  final double totalIn;
  final double totalOut;
  final double totalTransfers;
  final double totalAdjustmentsPos;
  final double totalAdjustmentsNeg;
  final String stockStatus;

  const InventorySummaryModel({
    required this.materialId,
    required this.materialName,
    this.code,
    required this.unit,
    required this.minStock,
    required this.openingBalance,
    required this.currentBalance,
    required this.totalIn,
    required this.totalOut,
    required this.totalTransfers,
    required this.totalAdjustmentsPos,
    required this.totalAdjustmentsNeg,
    required this.stockStatus,
  });

  bool get isLow => stockStatus == 'low';
  bool get isCritical => minStock > 0 && currentBalance <= minStock * 0.5;
  double get netAdjustments => totalAdjustmentsPos - totalAdjustmentsNeg;

  factory InventorySummaryModel.fromJson(Map<String, dynamic> json) =>
      InventorySummaryModel(
        materialId: json['material_id'] as String,
        materialName: json['material_name'] as String? ?? '',
        code: json['code'] as String?,
        unit: json['unit'] as String? ?? 'كجم',
        minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
        openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
        currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0,
        totalIn: (json['total_in'] as num?)?.toDouble() ?? 0,
        totalOut: (json['total_out'] as num?)?.toDouble() ?? 0,
        totalTransfers: (json['total_transfers'] as num?)?.toDouble() ?? 0,
        totalAdjustmentsPos: (json['total_adjustments_pos'] as num?)?.toDouble() ?? 0,
        totalAdjustmentsNeg: (json['total_adjustments_neg'] as num?)?.toDouble() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'normal',
      );
}
