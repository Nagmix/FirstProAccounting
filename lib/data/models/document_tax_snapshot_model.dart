class DocumentTaxSnapshot {
  final int? id;
  final String documentType;
  final String documentId;
  final int? taxProfileId;
  final String countryCode;
  final String regimeCode;
  final int rateBasisPoints;
  final String calculationMethod;
  final bool transportTaxable;
  final int taxableSubtotalMinor;
  final int taxableTransportMinor;
  final int discountMinor;
  final int taxMinor;
  final String roundingMode;
  final String source;
  final DateTime? createdAt;

  const DocumentTaxSnapshot({
    this.id,
    required this.documentType,
    required this.documentId,
    this.taxProfileId,
    required this.countryCode,
    required this.regimeCode,
    required this.rateBasisPoints,
    required this.calculationMethod,
    required this.transportTaxable,
    required this.taxableSubtotalMinor,
    required this.taxableTransportMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.roundingMode,
    required this.source,
    this.createdAt,
  });

  factory DocumentTaxSnapshot.fromRow(Map<String, Object?> row) {
    return DocumentTaxSnapshot(
      id: row['id'] as int?,
      documentType: row['document_type'] as String,
      documentId: row['document_id'] as String,
      taxProfileId: row['tax_profile_id'] as int?,
      countryCode: row['country_code'] as String,
      regimeCode: row['regime_code'] as String,
      rateBasisPoints: row['rate_bps'] as int,
      calculationMethod: row['calculation_method'] as String,
      transportTaxable: row['transport_taxable'] == 1,
      taxableSubtotalMinor: row['taxable_subtotal_minor'] as int,
      taxableTransportMinor: row['taxable_transport_minor'] as int,
      discountMinor: row['discount_minor'] as int,
      taxMinor: row['tax_minor'] as int,
      roundingMode: row['rounding_mode'] as String,
      source: row['source'] as String,
      createdAt: _parseDate(row['created_at'] as String?),
    );
  }

  DocumentTaxSnapshot copyWith({
    int? rateBasisPoints,
    int? taxMinor,
  }) {
    return DocumentTaxSnapshot(
      id: id,
      documentType: documentType,
      documentId: documentId,
      taxProfileId: taxProfileId,
      countryCode: countryCode,
      regimeCode: regimeCode,
      rateBasisPoints: rateBasisPoints ?? this.rateBasisPoints,
      calculationMethod: calculationMethod,
      transportTaxable: transportTaxable,
      taxableSubtotalMinor: taxableSubtotalMinor,
      taxableTransportMinor: taxableTransportMinor,
      discountMinor: discountMinor,
      taxMinor: taxMinor ?? this.taxMinor,
      roundingMode: roundingMode,
      source: source,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toColumns({required String now}) {
    return {
      if (id != null) 'id': id,
      'document_type': documentType,
      'document_id': documentId,
      'tax_profile_id': taxProfileId,
      'country_code': countryCode,
      'regime_code': regimeCode,
      'rate_bps': rateBasisPoints,
      'calculation_method': calculationMethod,
      'transport_taxable': transportTaxable ? 1 : 0,
      'taxable_subtotal_minor': taxableSubtotalMinor,
      'taxable_transport_minor': taxableTransportMinor,
      'discount_minor': discountMinor,
      'tax_minor': taxMinor,
      'rounding_mode': roundingMode,
      'source': source,
      'created_at': createdAt?.toIso8601String() ?? now,
    };
  }

  static DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.parse(value);
}
