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
