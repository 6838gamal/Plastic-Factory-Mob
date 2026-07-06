class VoucherItemModel {
  final String? id;
  final String? materialId;
  final String materialName;
  final String unit;
  final double requestedQty;
  final double? confirmedQty;
  final String? notes;

  const VoucherItemModel({
    this.id,
    this.materialId,
    required this.materialName,
    this.unit = 'كجم',
    required this.requestedQty,
    this.confirmedQty,
    this.notes,
  });

  factory VoucherItemModel.fromJson(Map<String, dynamic> json) => VoucherItemModel(
        id: json['id'] as String?,
        materialId: json['material_id'] as String?,
        materialName: json['material_name'] as String? ?? '',
        unit: json['unit'] as String? ?? 'كجم',
        requestedQty: (json['requested_qty'] as num? ?? json['quantity'] as num? ?? 0).toDouble(),
        confirmedQty: (json['confirmed_qty'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (materialId != null) 'material_id': materialId,
        'material_name': materialName,
        'unit': unit,
        'requested_qty': requestedQty,
        if (confirmedQty != null) 'confirmed_qty': confirmedQty,
        if (notes != null) 'notes': notes,
      };
}

// ─────────────────────────── Receipt Voucher ──────────────────────────────

class ReceiptVoucherModel {
  final String? id;
  final String? voucherNumber;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierRef;
  final String? receivedBy;
  final String? date;
  final String status; // draft | posted
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final int itemCount;
  final List<VoucherItemModel> items;

  const ReceiptVoucherModel({
    this.id,
    this.voucherNumber,
    this.supplierName,
    this.supplierPhone,
    this.supplierRef,
    this.receivedBy,
    this.date,
    this.status = 'draft',
    this.notes,
    this.createdBy,
    this.createdAt,
    this.itemCount = 0,
    this.items = const [],
  });

  factory ReceiptVoucherModel.fromJson(Map<String, dynamic> json) => ReceiptVoucherModel(
        id: json['id'] as String?,
        voucherNumber: json['voucher_number'] as String?,
        supplierName: json['supplier_name'] as String?,
        supplierPhone: json['supplier_phone'] as String?,
        supplierRef: json['supplier_ref'] as String?,
        receivedBy: json['received_by'] as String?,
        date: json['date'] as String?,
        status: json['status'] as String? ?? 'draft',
        notes: json['notes'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: json['created_at'] as String?,
        itemCount: (json['item_count'] as num? ?? 0).toInt(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => VoucherItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ─────────────────────────── Transfer Voucher ─────────────────────────────

class TransferVoucherModel {
  final String? id;
  final String? voucherNumber;
  final String status; // draft | pending | confirmed | cancelled
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final String? confirmedBy;
  final String? confirmedAt;
  final int itemCount;
  final List<VoucherItemModel> items;

  const TransferVoucherModel({
    this.id,
    this.voucherNumber,
    this.status = 'draft',
    this.notes,
    this.createdBy,
    this.createdAt,
    this.confirmedBy,
    this.confirmedAt,
    this.itemCount = 0,
    this.items = const [],
  });

  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';
  bool get canEdit => status == 'draft' || status == 'pending';
  bool get canConfirm => status == 'pending' || status == 'draft';

  factory TransferVoucherModel.fromJson(Map<String, dynamic> json) => TransferVoucherModel(
        id: json['id'] as String?,
        voucherNumber: json['voucher_number'] as String?,
        status: json['status'] as String? ?? 'draft',
        notes: json['notes'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: json['created_at'] as String?,
        confirmedBy: json['confirmed_by'] as String?,
        confirmedAt: json['confirmed_at'] as String?,
        itemCount: (json['item_count'] as num? ?? 0).toInt(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => VoucherItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ─────────────────────────── Return Voucher ───────────────────────────────

class ReturnVoucherModel {
  final String? id;
  final String? voucherNumber;
  final String? originalVoucherId;
  final String? originalVoucherNumber;
  final String? reason;
  final String status; // draft | posted
  final String? createdBy;
  final String? createdAt;
  final int itemCount;
  final List<VoucherItemModel> items;

  const ReturnVoucherModel({
    this.id,
    this.voucherNumber,
    this.originalVoucherId,
    this.originalVoucherNumber,
    this.reason,
    this.status = 'draft',
    this.createdBy,
    this.createdAt,
    this.itemCount = 0,
    this.items = const [],
  });

  factory ReturnVoucherModel.fromJson(Map<String, dynamic> json) => ReturnVoucherModel(
        id: json['id'] as String?,
        voucherNumber: json['voucher_number'] as String?,
        originalVoucherId: json['original_voucher_id'] as String?,
        originalVoucherNumber: json['original_voucher_number'] as String?,
        reason: json['reason'] as String?,
        status: json['status'] as String? ?? 'draft',
        createdBy: json['created_by'] as String?,
        createdAt: json['created_at'] as String?,
        itemCount: (json['item_count'] as num? ?? 0).toInt(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => VoucherItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ─────────────────────────── Withdrawal Voucher ───────────────────────────

class WithdrawalVoucherModel {
  final String? id;
  final String? voucherNumber;
  final String? purpose;
  final String status; // draft | pending_approval | approved | rejected
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final int itemCount;
  final List<VoucherItemModel> items;

  const WithdrawalVoucherModel({
    this.id,
    this.voucherNumber,
    this.purpose,
    this.status = 'draft',
    this.notes,
    this.createdBy,
    this.createdAt,
    this.itemCount = 0,
    this.items = const [],
  });

  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending_approval';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory WithdrawalVoucherModel.fromJson(Map<String, dynamic> json) =>
      WithdrawalVoucherModel(
        id: json['id'] as String?,
        voucherNumber: json['voucher_number'] as String?,
        purpose: json['purpose'] as String?,
        status: json['status'] as String? ?? 'draft',
        notes: json['notes'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: json['created_at'] as String?,
        itemCount: (json['item_count'] as num? ?? 0).toInt(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => VoucherItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
