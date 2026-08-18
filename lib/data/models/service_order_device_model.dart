class ServiceOrderDevice {
  final int? id;
  final String serviceOrderId;
  final String deviceType;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? imei;
  final String? conditionOnReceipt;
  final String? accessories;
  final String? customerApprovalNote;
  final DateTime? createdAt;

  ServiceOrderDevice({
    this.id,
    required this.serviceOrderId,
    required this.deviceType,
    this.brand,
    this.model,
    this.serialNumber,
    this.imei,
    this.conditionOnReceipt,
    this.accessories,
    this.customerApprovalNote,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'device_type': deviceType,
      'brand': brand,
      'model': model,
      'serial_number': serialNumber,
      'imei': imei,
      'condition_on_receipt': conditionOnReceipt,
      'accessories': accessories,
      'customer_approval_note': customerApprovalNote,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory ServiceOrderDevice.fromMap(Map<String, dynamic> map) {
    return ServiceOrderDevice(
      id: map['id'] as int?,
      serviceOrderId: map['service_order_id'] as String,
      deviceType: map['device_type'] as String,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      serialNumber: map['serial_number'] as String?,
      imei: map['imei'] as String?,
      conditionOnReceipt: map['condition_on_receipt'] as String?,
      accessories: map['accessories'] as String?,
      customerApprovalNote: map['customer_approval_note'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
    );
  }
}
