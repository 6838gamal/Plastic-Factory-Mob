class BatchMaterialModel {
  final String materialId;
  final String materialName;
  final double quantity;
  final String unit;

  const BatchMaterialModel({
    required this.materialId,
    required this.materialName,
    required this.quantity,
    required this.unit,
  });

  factory BatchMaterialModel.fromJson(Map<String, dynamic> json) => BatchMaterialModel(
        materialId: json['material_id'] as String? ?? '',
        materialName: (json['material_name'] ?? json['name']) as String? ?? '',
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String? ?? 'كجم',
      );

  Map<String, dynamic> toJson() => {
        'material_id': materialId,
        'quantity': quantity,
        'unit': unit,
      };
}

class BatchModel {
  final String id;
  final String batchNumber;
  final DateTime date;
  final String shift;
  final String workerId;
  final String workerName;
  final String mixerId;
  final String mixerName;
  final String productId;
  final String productName;
  final String mixtureTypeId;
  final String mixtureTypeName;
  final List<BatchMaterialModel> materials;
  final double pvcQty;
  final double dopQty;
  final double scrapQty;
  final double calciumQty;
  final double waxQty;
  final double stabilizerQty;
  final double titaniumQty;
  final List<Map<String, dynamic>> pigments;
  final List<Map<String, dynamic>> additives;
  final String? notes;
  final String? scaleImageUrl;
  final String? transactionId;
  final String status; // 'pending_sync', 'saved'
  final DateTime createdAt;

  double get totalInput =>
      pvcQty +
      dopQty +
      scrapQty +
      calciumQty +
      waxQty +
      stabilizerQty +
      titaniumQty +
      pigments.fold(0.0, (s, m) => s + (m['quantity'] as num).toDouble()) +
      additives.fold(0.0, (s, m) => s + (m['quantity'] as num).toDouble());

  const BatchModel({
    required this.id,
    required this.batchNumber,
    required this.date,
    required this.shift,
    required this.workerId,
    required this.workerName,
    required this.mixerId,
    required this.mixerName,
    required this.productId,
    required this.productName,
    required this.mixtureTypeId,
    required this.mixtureTypeName,
    required this.materials,
    required this.pvcQty,
    required this.dopQty,
    required this.scrapQty,
    required this.calciumQty,
    required this.waxQty,
    required this.stabilizerQty,
    required this.titaniumQty,
    required this.pigments,
    required this.additives,
    this.notes,
    this.scaleImageUrl,
    this.transactionId,
    required this.status,
    required this.createdAt,
  });

  factory BatchModel.fromJson(Map<String, dynamic> json) => BatchModel(
        id: json['id'] as String,
        batchNumber: json['batch_number'] as String,
        date: DateTime.parse(json['date'] as String),
        shift: json['shift'] as String,
        workerId: json['worker_id'] as String? ?? '',
        workerName: json['worker_name'] as String? ?? '',
        mixerId: json['mixer_id'] as String? ?? '',
        mixerName: json['mixer_name'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        productName: json['product_name'] as String? ?? '',
        mixtureTypeId: json['mixture_type_id'] as String? ?? '',
        mixtureTypeName: json['mixture_type_name'] as String? ?? '',
        materials: (json['materials'] as List<dynamic>?)
                ?.map((e) => BatchMaterialModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        pvcQty: (json['pvc_qty'] as num?)?.toDouble() ?? 0,
        dopQty: (json['dop_qty'] as num?)?.toDouble() ?? 0,
        scrapQty: (json['scrap_qty'] as num?)?.toDouble() ?? 0,
        calciumQty: (json['calcium_qty'] as num?)?.toDouble() ?? 0,
        waxQty: (json['wax_qty'] as num?)?.toDouble() ?? 0,
        stabilizerQty: (json['stabilizer_qty'] as num?)?.toDouble() ?? 0,
        titaniumQty: (json['titanium_qty'] as num?)?.toDouble() ?? 0,
        pigments: (json['pigments'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [],
        additives: (json['additives'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [],
        notes: json['notes'] as String?,
        scaleImageUrl: json['scale_image_url'] as String?,
        transactionId: json['transaction_id'] as String?,
        status: json['status'] as String? ?? 'saved',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'batch_number': batchNumber,
        'date': date.toIso8601String().split('T').first,
        'shift': shift,
        'worker_id': workerId,
        'mixer_id': mixerId,
        'product_id': productId,
        'mixture_type_id': mixtureTypeId,
        'pvc_qty': pvcQty,
        'dop_qty': dopQty,
        'scrap_qty': scrapQty,
        'calcium_qty': calciumQty,
        'wax_qty': waxQty,
        'stabilizer_qty': stabilizerQty,
        'titanium_qty': titaniumQty,
        'pigments': pigments,
        'additives': additives,
        'notes': notes,
        'scale_image_url': scaleImageUrl,
        'transaction_id': transactionId,
        'status': status,
      };
}
