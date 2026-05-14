/// Application-wide constants for the FirstPro accounting app.
class AppConstants {
  AppConstants._();

  // ── App identity ──────────────────────────────────────────────
  static const String appName = 'الأول برو';
  static const String appNameEn = 'FirstPro';
  static const String appFullName = 'الأول برو المحاسبي';
  static const String appVersion = '1.0.0';
  static const String appSlogan = 'حلول محاسبية احترافية';

  // ── Database ──────────────────────────────────────────────────
  static const String dbName = 'firstpro.db';
  static const int dbVersion = 1;

  // ── Locale & currency ─────────────────────────────────────────
  static const String currency = 'ر.س';
  static const String currencyEn = 'SAR';
  static const String defaultLanguage = 'ar';
  static const String localeAr = 'ar';
  static const String localeEn = 'en';

  // ── Payment methods ───────────────────────────────────────────
  static const String cashPayment = 'نقدي';
  static const String creditPayment = 'آجل';
  static const String bankPayment = 'بنك';
  static const String checkPayment = 'شيك';

  // ── Invoice types ─────────────────────────────────────────────
  static const String saleInvoice = 'sale';
  static const String purchaseInvoice = 'purchase';
  static const String returnInvoice = 'return';

  // ── Invoice type display names ────────────────────────────────
  static const String saleInvoiceAr = 'فاتورة مبيعات';
  static const String purchaseInvoiceAr = 'فاتورة مشتريات';
  static const String returnInvoiceAr = 'فاتورة مرتجع';

  // ── Status ────────────────────────────────────────────────────
  static const String statusPaid = 'مدفوع';
  static const String statusUnpaid = 'غير مدفوع';
  static const String statusPending = 'معلق';
  static const String statusPartial = 'مدفوع جزئياً';
  static const String statusCancelled = 'ملغي';

  // ── Pagination ────────────────────────────────────────────────
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // ── Animation durations ───────────────────────────────────────
  static const Duration animationDurationShort = Duration(milliseconds: 200);
  static const Duration animationDurationMedium = Duration(milliseconds: 350);
  static const Duration animationDurationLong = Duration(milliseconds: 500);

  // ── Date formats ──────────────────────────────────────────────
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';

  // ── Number formats ────────────────────────────────────────────
  static const int decimalPlaces = 2;
  static const int quantityDecimalPlaces = 3;

  // ── Tax ───────────────────────────────────────────────────────
  static const double defaultVatRate = 15.0; // Saudi VAT rate
}
