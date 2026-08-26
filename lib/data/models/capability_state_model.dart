class CapabilityState {
  final String capabilityCode;
  final bool enabled;
  final String source;
  final int definitionVersion;
  final DateTime? enabledAt;
  final DateTime? disabledAt;

  const CapabilityState({
    required this.capabilityCode,
    required this.enabled,
    required this.source,
    required this.definitionVersion,
    required this.enabledAt,
    required this.disabledAt,
  });

  factory CapabilityState.fromRow(Map<String, Object?> row) {
    return CapabilityState(
      capabilityCode: row['capability_code'] as String,
      enabled: (row['enabled'] as num?)?.toInt() == 1,
      source: row['source'] as String? ?? 'system',
      definitionVersion: (row['definition_version'] as num?)?.toInt() ?? 1,
      enabledAt: _parseDate(row['enabled_at'] as String?),
      disabledAt: _parseDate(row['disabled_at'] as String?),
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
