class Category {
  final int? id;
  final String name;
  final int? parentId;
  final String? icon;
  final String? color;
  final bool isActive;
  final DateTime createdAt;

  Category({
    this.id,
    required this.name,
    this.parentId,
    this.icon,
    this.color,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      parentId: map['parent_id'],
      icon: map['icon'],
      color: map['color'],
      isActive: (map['is_active'] ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Category copyWith({
    int? id,
    String? name,
    int? parentId,
    String? icon,
    String? color,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
