class InventoryModel {
  final String id;
  final String materialId;
  final String materialName;
  final String warehouseType; // 'main' or 'mixer'
  final double balance;
  final double minStock;
  final String unit;
  final DateTime updatedAt;

  const InventoryModel({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.warehouseType,
    required this.balance,
    required this.minStock,
    required this.unit,
    required this.updatedAt,
  });

  bool get isLowStock => balance <= minStock;
  bool get isCritical => balance <= minStock * 0.5;
  double get stockPercentage => minStock > 0 ? (balance / minStock) * 100 : 100;

  factory InventoryModel.fromJson(Map<String, dynamic> json) => InventoryModel(
        id: json['id'] as String,
        materialId: json['material_id'] as String,
        materialName: json['material_name'] as String? ?? '',
        warehouseType: json['warehouse_type'] as String,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? 'كجم',
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'material_id': materialId,
        'warehouse_type': warehouseType,
        'balance': balance,
        'min_stock': minStock,
        'unit': unit,
        'updated_at': updatedAt.toIso8601String(),
      };
}

class InventoryTransactionModel {
  final String id;
  final String materialId;
  final String materialName;
  final String warehouseType;
  final String transactionType; // 'in', 'out', 'transfer'
  final double quantity;
  final String? batchId;
  final String? productionId;
  final String? transactionRef;
  final String createdBy;
  final String? notes;
  final DateTime createdAt;

  const InventoryTransactionModel({
    required this.id,
    required this.materialId,
    this.materialName = '',
    required this.warehouseType,
    required this.transactionType,
    required this.quantity,
    this.batchId,
    this.productionId,
    this.transactionRef,
    required this.createdBy,
    this.notes,
    required this.createdAt,
  });

  factory InventoryTransactionModel.fromJson(Map<String, dynamic> json) =>
      InventoryTransactionModel(
        id: json['id'] as String,
        materialId: json['material_id'] as String,
        materialName: json['material_name'] as String? ?? '',
        warehouseType: json['warehouse_type'] as String,
        transactionType: json['transaction_type'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        batchId: json['batch_id'] as String?,
        productionId: json['production_id'] as String?,
        transactionRef: json['transaction_ref'] as String?,
        createdBy: json['created_by'] as String? ?? '',
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'material_id': materialId,
        'warehouse_type': warehouseType,
        'transaction_type': transactionType,
        'quantity': quantity,
        'batch_id': batchId,
        'production_id': productionId,
        'transaction_ref': transactionRef,
        'created_by': createdBy,
        'notes': notes,
      };
}
