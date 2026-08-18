class ServiceWarranty {
  final int? id;
  final String serviceOrderId;
  final int? serviceOrderLineId;
  final String warrantyType;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? terms;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ServiceWarranty({
    this.id,
    required this.serviceOrderId,
    this.serviceOrderLineId,
    this.warrantyType = 'repair',
    required this.startsAt,
    required this.endsAt,
    this.terms,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  }) : assert(!endsAt.isBefore(startsAt), 'انتهاء الضمان لا يسبق بدايته');

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'service_order_line_id': serviceOrderLineId,
      'warranty_type': warrantyType,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
      'terms': terms,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ServiceWarranty.fromMap(Map<String, dynamic> map) {
    return ServiceWarranty(
      id: map['id'] as int?,
      serviceOrderId: map['service_order_id'] as String,
      serviceOrderLineId: map['service_order_line_id'] as int?,
      warrantyType: map['warranty_type'] as String? ?? 'repair',
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: DateTime.parse(map['ends_at'] as String),
      terms: map['terms'] as String?,
      status: map['status'] as String? ?? 'active',
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
    );
  }
}
