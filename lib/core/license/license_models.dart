import 'license_constants.dart';

/// License type enumeration.
enum LicenseType {
  free('free'),
  trial('trial'),
  monthly('monthly'),
  yearly('yearly'),
  lifetime('lifetime');

  final String value;
  const LicenseType(this.value);

  static LicenseType fromString(String value) {
    return LicenseType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => LicenseType.free,
    );
  }

  String get arabicLabel {
    switch (this) {
      case LicenseType.free:
        return 'مجاني';
      case LicenseType.trial:
        return 'تجريبي';
      case LicenseType.monthly:
        return 'شهري';
      case LicenseType.yearly:
        return 'سنوي';
      case LicenseType.lifetime:
        return 'دائم';
    }
  }
}

/// License status enumeration.
enum LicenseStatus {
  free('free'),
  active('active'),
  expired('expired'),
  revoked('revoked');

  final String value;
  const LicenseStatus(this.value);

  static LicenseStatus fromString(String value) {
    return LicenseStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => LicenseStatus.free,
    );
  }

  String get arabicLabel {
    switch (this) {
      case LicenseStatus.free:
        return 'مجاني';
      case LicenseStatus.active:
        return 'نشط';
      case LicenseStatus.expired:
        return 'منتهي';
      case LicenseStatus.revoked:
        return 'ملغى';
    }
  }
}

/// Represents the current license state of the application.
class LicenseStateModel {
  final String? licenseKey;
  final LicenseType licenseType;
  final LicenseStatus status;
  final DateTime? expiresAt;
  final String? deviceFingerprint;
  final String? installationId;
  final String? sessionToken;
  final DateTime? lastValidatedAt;
  final DateTime? lastSyncAt;
  final int recordCount;
  final bool isOfflineGrace;
  final DateTime? offlineSince;
  final String? serverUrl;

  const LicenseStateModel({
    this.licenseKey,
    this.licenseType = LicenseType.free,
    this.status = LicenseStatus.free,
    this.expiresAt,
    this.deviceFingerprint,
    this.installationId,
    this.sessionToken,
    this.lastValidatedAt,
    this.lastSyncAt,
    this.recordCount = 0,
    this.isOfflineGrace = false,
    this.offlineSince,
    this.serverUrl,
  });

  /// Whether this is a premium (paid) license.
  bool get isPremium => status == LicenseStatus.active;

  /// Whether this is the free edition.
  bool get isFree =>
      status == LicenseStatus.free || status == LicenseStatus.expired;

  /// Whether the license has expired.
  bool get isExpired => status == LicenseStatus.expired;

  /// Whether the license has been revoked.
  bool get isRevoked => status == LicenseStatus.revoked;

  /// Number of days remaining until expiration (null = never expires).
  int? get daysRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Whether the app can be used in offline grace period.
  bool get canUseOffline {
    if (!isOfflineGrace) return true;
    if (offlineSince == null) return true;
    final graceEnd = offlineSince!.add(
      Duration(days: LicenseConstants.offlineGraceDays),
    );
    return DateTime.now().isBefore(graceEnd);
  }

  /// Remaining days in the offline grace period.
  int get offlineGraceDaysRemaining {
    if (!isOfflineGrace || offlineSince == null) return 7;
    final graceEnd = offlineSince!.add(const Duration(days: 7));
    final remaining = graceEnd.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }

  LicenseStateModel copyWith({
    String? licenseKey,
    LicenseType? licenseType,
    LicenseStatus? status,
    DateTime? expiresAt,
    String? deviceFingerprint,
    String? installationId,
    String? sessionToken,
    DateTime? lastValidatedAt,
    DateTime? lastSyncAt,
    int? recordCount,
    bool? isOfflineGrace,
    DateTime? offlineSince,
    String? serverUrl,
  }) {
    return LicenseStateModel(
      licenseKey: licenseKey ?? this.licenseKey,
      licenseType: licenseType ?? this.licenseType,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      installationId: installationId ?? this.installationId,
      sessionToken: sessionToken ?? this.sessionToken,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      recordCount: recordCount ?? this.recordCount,
      isOfflineGrace: isOfflineGrace ?? this.isOfflineGrace,
      offlineSince: offlineSince ?? this.offlineSince,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }

  factory LicenseStateModel.fromMap(Map<String, dynamic> map) {
    return LicenseStateModel(
      licenseKey: map['license_key'] as String?,
      licenseType: LicenseType.fromString(map['license_type'] as String? ?? 'free'),
      status: LicenseStatus.fromString(map['status'] as String? ?? 'free'),
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'] as String)
          : null,
      deviceFingerprint: map['device_fingerprint'] as String?,
      installationId: map['installation_id'] as String?,
      sessionToken: map['session_token'] as String?,
      lastValidatedAt: map['last_validated_at'] != null
          ? DateTime.tryParse(map['last_validated_at'] as String)
          : null,
      lastSyncAt: map['last_sync_at'] != null
          ? DateTime.tryParse(map['last_sync_at'] as String)
          : null,
      recordCount: (map['record_count'] as int?) ?? 0,
      isOfflineGrace: (map['is_offline_grace'] as int?) == 1,
      offlineSince: map['offline_since'] != null
          ? DateTime.tryParse(map['offline_since'] as String)
          : null,
      serverUrl: map['server_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'license_key': licenseKey,
      'license_type': licenseType.value,
      'status': status.value,
      'expires_at': expiresAt?.toIso8601String(),
      'device_fingerprint': deviceFingerprint,
      'installation_id': installationId,
      'session_token': sessionToken,
      'last_validated_at': lastValidatedAt?.toIso8601String(),
      'last_sync_at': lastSyncAt?.toIso8601String(),
      'record_count': recordCount,
      'is_offline_grace': isOfflineGrace ? 1 : 0,
      'offline_since': offlineSince?.toIso8601String(),
      'server_url': serverUrl,
    };
  }
}
