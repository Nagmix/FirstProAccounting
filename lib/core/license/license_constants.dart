/// Constants for the license system.
class LicenseConstants {
  LicenseConstants._();

  /// Base URL for the license API server.
  static const String apiBaseUrl = 'https://firstpro-license-server.vercel.app';

  /// Maximum number of records allowed in the free edition.
  static const int freeRecordLimit = 500;

  /// Number of days the app works offline without server validation.
  static const int offlineGraceDays = 7;

  /// How often (in hours) the app should re-validate with the server.
  static const int validationIntervalHours = 24;

  /// Regex pattern for validating license key format.
  static const String licenseKeyPattern =
      r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$';

  // ── Secure Storage Keys ──
  static const String installationIdKey = 'license_installation_id';
  static const String sessionTokenKey = 'license_session_token';
  static const String licenseKeyStorage = 'license_key';
  static const String licenseStatusKey = 'license_status';

  // ── API Endpoints ──
  static const String activateEndpoint = '/api/license/activate';
  static const String validateEndpoint = '/api/license/validate';
  static const String rebindEndpoint = '/api/license/rebind';
  static const String statusEndpoint = '/api/license/status';
  static const String usageEndpoint = '/api/usage/increment';

  // ── WhatsApp ──
  static const String supportWhatsApp = '967777123456';
  static const String supportWhatsAppMessage =
      'مرحباً، أريد تفعيل ترخيص تطبيق الأول برو المحاسبي.\nكود الجهاز: ';
}
