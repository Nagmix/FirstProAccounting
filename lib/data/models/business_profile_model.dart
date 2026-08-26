class BusinessProfile {
  final String? businessName;
  final String? phone;
  final String? email;
  final String? address;
  final String? logoPath;
  final String countryCode;
  final String baseCurrencyCode;
  final String locale;
  final String timezone;
  final String taxMode;
  final String setupStatus;
  final int setupVersion;
  final String source;

  const BusinessProfile({
    required this.businessName,
    required this.phone,
    required this.email,
    required this.address,
    required this.logoPath,
    required this.countryCode,
    required this.baseCurrencyCode,
    required this.locale,
    required this.timezone,
    required this.taxMode,
    required this.setupStatus,
    required this.setupVersion,
    required this.source,
  });

  factory BusinessProfile.fromRow(Map<String, Object?> row) {
    return BusinessProfile(
      businessName: row['business_name'] as String?,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      address: row['address'] as String?,
      logoPath: row['logo_path'] as String?,
      countryCode: row['country_code'] as String? ?? 'YE',
      baseCurrencyCode: row['base_currency_code'] as String? ?? 'YER',
      locale: row['locale'] as String? ?? 'ar',
      timezone: row['timezone'] as String? ?? 'Asia/Aden',
      taxMode: row['tax_mode'] as String? ?? 'none',
      setupStatus: row['setup_status'] as String? ?? 'not_started',
      setupVersion: (row['setup_version'] as num?)?.toInt() ?? 1,
      source: row['source'] as String? ?? 'migration',
    );
  }

  BusinessProfile copyWith({
    String? businessName,
    String? phone,
    String? email,
    String? address,
    String? logoPath,
    String? countryCode,
    String? baseCurrencyCode,
    String? locale,
    String? timezone,
    String? taxMode,
    String? setupStatus,
    int? setupVersion,
    String? source,
  }) {
    return BusinessProfile(
      businessName: businessName ?? this.businessName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      logoPath: logoPath ?? this.logoPath,
      countryCode: countryCode ?? this.countryCode,
      baseCurrencyCode: baseCurrencyCode ?? this.baseCurrencyCode,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      taxMode: taxMode ?? this.taxMode,
      setupStatus: setupStatus ?? this.setupStatus,
      setupVersion: setupVersion ?? this.setupVersion,
      source: source ?? this.source,
    );
  }
}
