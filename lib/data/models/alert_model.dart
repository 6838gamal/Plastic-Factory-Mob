class AlertModel {
  final String id;
  final String alertType;
  final String severity;
  final String? materialId;
  final String? materialName;
  final String? batchId;
  final String? batchNumber;
  final String? machineId;
  final String? machineName;
  final String? workerId;
  final String? workerName;
  final String description;
  final String status;
  final String? assignedTo;
  final String? transactionId;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AlertModel({
    required this.id,
    required this.alertType,
    required this.severity,
    this.materialId,
    this.materialName,
    this.batchId,
    this.batchNumber,
    this.machineId,
    this.machineName,
    this.workerId,
    this.workerName,
    required this.description,
    required this.status,
    this.assignedTo,
    this.transactionId,
    required this.createdAt,
    this.resolvedAt,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel(
        id: json['id'] as String,
        alertType: json['alert_type'] as String,
        severity: json['severity'] as String,
        materialId: json['material_id'] as String?,
        materialName: json['material_name'] as String?,
        batchId: json['batch_id'] as String?,
        batchNumber: json['batch_number'] as String?,
        machineId: json['machine_id'] as String?,
        machineName: json['machine_name'] as String?,
        workerId: json['worker_id'] as String?,
        workerName: json['worker_name'] as String?,
        description: json['description'] as String,
        status: json['status'] as String? ?? 'pending',
        assignedTo: json['assigned_to'] as String?,
        transactionId: json['transaction_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        resolvedAt: json['resolved_at'] != null
            ? DateTime.parse(json['resolved_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'alert_type': alertType,
        'severity': severity,
        'material_id': materialId,
        'material_name': materialName,
        'batch_id': batchId,
        'batch_number': batchNumber,
        'machine_id': machineId,
        'machine_name': machineName,
        'worker_id': workerId,
        'worker_name': workerName,
        'description': description,
        'status': status,
        'assigned_to': assignedTo,
        'transaction_id': transactionId,
      };
}
