class AuditLogModel {
  final String id;
  final String action;
  final String tableName;
  final String? recordId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String userId;
  final String? userEmail;
  final String? transactionId;
  final String? description;
  final DateTime createdAt;

  const AuditLogModel({
    required this.id,
    required this.action,
    required this.tableName,
    this.recordId,
    this.oldValues,
    this.newValues,
    required this.userId,
    this.userEmail,
    this.transactionId,
    this.description,
    required this.createdAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
        id: json['id'] as String,
        action: json['action'] as String,
        tableName: json['table_name'] as String,
        recordId: json['record_id'] as String?,
        oldValues: json['old_values'] != null
            ? Map<String, dynamic>.from(json['old_values'] as Map)
            : null,
        newValues: json['new_values'] != null
            ? Map<String, dynamic>.from(json['new_values'] as Map)
            : null,
        userId: json['user_id'] as String? ?? '',
        userEmail: json['user_email'] as String?,
        transactionId: json['transaction_id'] as String?,
        description: json['description'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'old_values': oldValues,
        'new_values': newValues,
        'user_id': userId,
        'user_email': userEmail,
        'transaction_id': transactionId,
        'description': description,
      };
}
