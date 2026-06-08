class MachineProductionModel {
  final String id;
  final String batchNumber;
  final String? batchId;
  final String machineId;
  final String machineName;
  final String productId;
  final String productName;
  final double producedQuantity;
  final double scrapQuantity;
  final double wasteQuantity;
  final double stopTimeMinutes;
  final String? notes;
  final String? productionImageUrl;
  final String? transactionId;
  final String workerId;
  final String status;
  final DateTime createdAt;

  double get efficiency {
    final total = producedQuantity + scrapQuantity + wasteQuantity;
    if (total == 0) return 0;
    return (producedQuantity / total) * 100;
  }

  const MachineProductionModel({
    required this.id,
    required this.batchNumber,
    this.batchId,
    required this.machineId,
    required this.machineName,
    required this.productId,
    required this.productName,
    required this.producedQuantity,
    required this.scrapQuantity,
    required this.wasteQuantity,
    required this.stopTimeMinutes,
    this.notes,
    this.productionImageUrl,
    this.transactionId,
    required this.workerId,
    required this.status,
    required this.createdAt,
  });

  factory MachineProductionModel.fromJson(Map<String, dynamic> json) => MachineProductionModel(
        id: json['id'] as String,
        batchNumber: json['batch_number'] as String,
        batchId: json['batch_id'] as String?,
        machineId: json['machine_id'] as String? ?? '',
        machineName: json['machine_name'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        productName: json['product_name'] as String? ?? '',
        producedQuantity: (json['produced_quantity'] as num?)?.toDouble() ?? 0,
        scrapQuantity: (json['scrap_quantity'] as num?)?.toDouble() ?? 0,
        wasteQuantity: (json['waste_quantity'] as num?)?.toDouble() ?? 0,
        stopTimeMinutes: (json['stop_time_minutes'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String?,
        productionImageUrl: json['production_image_url'] as String?,
        transactionId: json['transaction_id'] as String?,
        workerId: json['worker_id'] as String? ?? '',
        status: json['status'] as String? ?? 'saved',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'batch_number': batchNumber,
        'batch_id': batchId,
        'machine_id': machineId,
        'product_id': productId,
        'produced_quantity': producedQuantity,
        'scrap_quantity': scrapQuantity,
        'waste_quantity': wasteQuantity,
        'stop_time_minutes': stopTimeMinutes,
        'notes': notes,
        'production_image_url': productionImageUrl,
        'transaction_id': transactionId,
        'worker_id': workerId,
        'status': status,
      };
}
