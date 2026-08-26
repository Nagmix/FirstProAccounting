class TaxProfile {
  final int? id;
  final String countryCode;
  final String regimeCode;
  final String nameAr;
  final int rateBasisPoints;
  final String calculationMethod;
  final bool transportTaxable;
  final DateTime validFrom;
  final DateTime? validTo;
  final bool requiresConfirmation;
  final String? sourceNote;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaxProfile({
    this.id,
    required this.countryCode,
    required this.regimeCode,
    required this.nameAr,
    required this.rateBasisPoints,
    required this.calculationMethod,
    required this.transportTaxable,
    required this.validFrom,
    this.validTo,
    required this.requiresConfirmation,
    this.sourceNote,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory TaxProfile.fromRow(Map<String, Object?> row) {
    return TaxProfile(
      id: row['id'] as int?,
      countryCode: row['country_code'] as String,
      regimeCode: row['regime_code'] as String,
      nameAr: row['name_ar'] as String,
      rateBasisPoints: row['rate_bps'] as int,
      calculationMethod: row['calculation_method'] as String,
      transportTaxable: row['transport_taxable'] == 1,
      validFrom: DateTime.parse(row['valid_from'] as String),
      validTo: (row['valid_to'] as String?) == null
          ? null
          : DateTime.parse(row['valid_to'] as String),
      requiresConfirmation: row['requires_confirmation'] == 1,
      sourceNote: row['source_note'] as String?,
      isActive: row['is_active'] == 1,
      createdAt: _parseDate(row['created_at'] as String?),
      updatedAt: _parseDate(row['updated_at'] as String?),
    );
  }

  Map<String, Object?> toColumns({required String now}) {
    return {
      if (id != null) 'id': id,
      'country_code': countryCode,
      'regime_code': regimeCode,
      'name_ar': nameAr,
      'rate_bps': rateBasisPoints,
      'calculation_method': calculationMethod,
      'transport_taxable': transportTaxable ? 1 : 0,
      'valid_from': validFrom.toIso8601String(),
      'valid_to': validTo?.toIso8601String(),
      'requires_confirmation': requiresConfirmation ? 1 : 0,
      'source_note': sourceNote,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String() ?? now,
      'updated_at': now,
    };
  }

  static DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.parse(value);
}
