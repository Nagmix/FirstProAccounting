/// Compatibility rules for portable database restores.
class PortableBackupCompatibility {
  PortableBackupCompatibility._();

  static const int currentSchemaVersion = 59;

  static void validateSchemaVersion(int version) {
    if (version <= 0) {
      throw const FormatException('إصدار قاعدة البيانات غير صالح');
    }
    if (version > currentSchemaVersion) {
      throw const FormatException('النسخة أحدث من إصدار التطبيق');
    }
  }
}
