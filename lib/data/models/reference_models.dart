class WorkerModel {
  final String id;
  final String name;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  const WorkerModel({
    required this.id,
    required this.name,
    this.phone,
    required this.isActive,
    required this.createdAt,
  });

  factory WorkerModel.fromJson(Map<String, dynamic> json) => WorkerModel(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'is_active': isActive,
      };
}

class MachineModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const MachineModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
  });

  factory MachineModel.fromJson(Map<String, dynamic> json) => MachineModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'is_active': isActive,
      };
}

class MixerModel {
  final String id;
  final String name;
  final double? capacity;
  final bool isActive;
  final DateTime createdAt;

  const MixerModel({
    required this.id,
    required this.name,
    this.capacity,
    required this.isActive,
    required this.createdAt,
  });

  factory MixerModel.fromJson(Map<String, dynamic> json) => MixerModel(
        id: json['id'] as String,
        name: json['name'] as String,
        capacity: (json['capacity'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'capacity': capacity,
        'is_active': isActive,
      };
}

class ProductModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const ProductModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'is_active': isActive,
      };
}

class RecipeItemModel {
  final String id;
  final String recipeId;
  final String materialName;
  final double standardQty;
  final String unit;

  const RecipeItemModel({
    required this.id,
    required this.recipeId,
    required this.materialName,
    required this.standardQty,
    required this.unit,
  });

  factory RecipeItemModel.fromJson(Map<String, dynamic> json) => RecipeItemModel(
        id: json['id'] as String,
        recipeId: json['recipe_id'] as String,
        materialName: json['material_name'] as String,
        standardQty: (json['standard_qty'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? 'كجم',
      );

  Map<String, dynamic> toJson() => {
        'material_name': materialName,
        'standard_qty': standardQty,
        'unit': unit,
      };
}

class RecipeModel {
  final String id;
  final String mixtureTypeId;
  final String? mixtureTypeName;
  final String name;
  final String? notes;
  final bool isActive;
  final List<RecipeItemModel> items;

  const RecipeModel({
    required this.id,
    required this.mixtureTypeId,
    this.mixtureTypeName,
    required this.name,
    this.notes,
    required this.isActive,
    required this.items,
  });

  factory RecipeModel.fromJson(Map<String, dynamic> json) => RecipeModel(
        id: json['id'] as String,
        mixtureTypeId: json['mixture_type_id'] as String,
        mixtureTypeName: json['mixture_type_name'] as String?,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        items: ((json['items'] as List?) ?? [])
            .map((e) => RecipeItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, double> get qtyMap => {for (final i in items) i.materialName: i.standardQty};
  Map<String, String> get unitMap => {for (final i in items) i.materialName: i.unit};
}

class MixtureTypeModel {
  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const MixtureTypeModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
  });

  factory MixtureTypeModel.fromJson(Map<String, dynamic> json) => MixtureTypeModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'is_active': isActive,
      };
}
