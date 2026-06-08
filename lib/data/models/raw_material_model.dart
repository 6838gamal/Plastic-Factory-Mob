class RawMaterialModel {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double minStock;
  final bool isActive;
  final DateTime createdAt;

  const RawMaterialModel({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.minStock,
    required this.isActive,
    required this.createdAt,
  });

  factory RawMaterialModel.fromJson(Map<String, dynamic> json) => RawMaterialModel(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? '',
        unit: json['unit'] as String? ?? 'كجم',
        minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'unit': unit,
        'min_stock': minStock,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };

  RawMaterialModel copyWith({
    String? id,
    String? name,
    String? category,
    String? unit,
    double? minStock,
    bool? isActive,
  }) =>
      RawMaterialModel(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        unit: unit ?? this.unit,
        minStock: minStock ?? this.minStock,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  // Default raw materials for the factory
  static List<Map<String, dynamic>> get defaultMaterials => [
        // PVC
        {'name': 'PVC صيني', 'category': 'PVC', 'unit': 'كجم', 'min_stock': 1000},
        // Scrap
        {'name': 'سكراب أسود ناعم', 'category': 'سكراب', 'unit': 'كجم', 'min_stock': 200},
        {'name': 'سكراب أزرق ناعم', 'category': 'سكراب', 'unit': 'كجم', 'min_stock': 200},
        {'name': 'سكراب أزرق سكري', 'category': 'سكراب', 'unit': 'كجم', 'min_stock': 200},
        {'name': 'راجع ماكينة أزرق', 'category': 'سكراب', 'unit': 'كجم', 'min_stock': 100},
        // Oils and additives
        {'name': 'DOP زيت', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 200},
        {'name': 'مثبت استبليزر باودر 25 كجم', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 100},
        {'name': 'كالسيوم باودر 25 كجم', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 100},
        {'name': 'شمع باودر 25 كجم', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 50},
        {'name': 'تيتانيوم', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 50},
        {'name': 'سيتريك أسيد (ملح الليمون) 25 كجم', 'category': 'زيوت وإضافات', 'unit': 'كجم', 'min_stock': 25},
        // Bicarbonate
        {'name': 'بيكربونات أصفر محلي', 'category': 'بيكربونات', 'unit': 'كجم', 'min_stock': 50},
        {'name': 'بيكربونات أبيض محلي', 'category': 'بيكربونات', 'unit': 'كجم', 'min_stock': 50},
        // Pigments
        {'name': 'صبغة سوداء باودر 10 كجم', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'صبغة زرقاء باودر 20 كجم رقم 1027', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'صبغة زرقاء فاتح باودر 20 كجم رقم 1256', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'صبغة أرجواني باودر 25 كجم رقم F409', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 25},
        {'name': 'صبغة أحمر زهري باودر 25 كجم رقم F358', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 25},
        {'name': 'صبغة كاكي بيج باودر 25 كجم رقم 1035', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 25},
        {'name': 'صبغة خضراء طاووس محلي', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 10},
        {'name': 'صبغة برتقالي محلي', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 10},
        {'name': 'صبغة زرقاء طاووس محلي', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 10},
        {'name': 'صبغة سوداء طاووس محلي', 'category': 'أصباغ', 'unit': 'كجم', 'min_stock': 10},
        // Adhesives
        {'name': 'لاصق 703', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 8031', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 6031', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 6026', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 8026', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 6022', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        {'name': 'لاصق 8022', 'category': 'لواصق', 'unit': 'كجم', 'min_stock': 20},
        // Mixtures
        {'name': 'خلطة أزرق', 'category': 'خلطات', 'unit': 'كجم', 'min_stock': 100},
      ];
}
