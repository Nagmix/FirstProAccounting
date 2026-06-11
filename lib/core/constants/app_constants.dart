/// Application-wide constants for the FirstPro accounting app.
class AppConstants {
  AppConstants._();

  // ── App identity ──────────────────────────────────────────────
  static const String appName = 'الأول برو';
  static const String appNameEn = 'FirstPro';
  static const String appFullName = 'الأول برو المحاسبي';
  static const String appVersion = '2.0.0'; // Must match pubspec.yaml version
  static const String appSlogan = 'حلول محاسبية احترافية';

  // ── Database ──────────────────────────────────────────────────
  static const String dbName = 'firstpro.db';
  static const int dbVersion = 52; // Must match DatabaseHelper._databaseVersion

  // ── Locale & currency ─────────────────────────────────────────
  static String currency = 'ر.ي';
  static String currencyEn = 'YER';
  static const String defaultLanguage = 'ar';
  static const String localeAr = 'ar';
  static const String localeEn = 'en';

  // ── Payment mechanisms ────────────────────────────────────────
  static const String cashMechanism = 'cash';
  static const String creditMechanism = 'credit';

  // ── Payment methods ───────────────────────────────────────────
  static const String cashPayment = 'cash';
  static const String checkPayment = 'check';
  static const String transferPayment = 'transfer';
  static const String bankPayment = 'bank';

  // ── Invoice types ─────────────────────────────────────────────
  static const String saleInvoice = 'sale';
  static const String purchaseInvoice = 'purchase';
  static const String returnInvoice = 'return';
  static const String saleReturnInvoice = 'sale_return';
  static const String purchaseReturnInvoice = 'purchase_return';

  // ── Invoice type display names ────────────────────────────────
  static const String saleInvoiceAr = 'فاتورة مبيعات';
  static const String purchaseInvoiceAr = 'فاتورة مشتريات';
  static const String returnInvoiceAr = 'فاتورة مرتجع';

  // ── Account types ─────────────────────────────────────────────
  static const String assetAccount = 'ASSET';
  static const String liabilityAccount = 'LIABILITY';
  static const String equityAccount = 'EQUITY';
  static const String costAccount = 'COST';
  static const String revenueAccount = 'REVENUE';
  static const String expenseAccount = 'EXPENSE';

  // ── Account type Arabic names ─────────────────────────────────
  static const String assetAccountAr = 'الأصول';
  static const String liabilityAccountAr = 'الخصوم';
  static const String equityAccountAr = 'حقوق الملكية';
  static const String costAccountAr = 'التكاليف';
  static const String revenueAccountAr = 'الإيرادات';
  static const String expenseAccountAr = 'المصاريف';

  // ── Balance types ─────────────────────────────────────────────
  static const String debitBalance = 'debit';
  static const String creditBalance = 'credit';

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

  // ── Route names ───────────────────────────────────────────────
  static const String dashboard = '/dashboard';
  static const String customers = '/customers';
  static const String products = '/products';
  static const String invoices = '/invoices';
  static const String reports = '/reports';
  static const String pos = '/pos';
  static const String settings = '/settings';
  static const String support = '/support';
  static const String currencies = '/currencies';
  static const String cashBoxes = '/cash-boxes';
  static const String chartOfAccounts = '/chart-of-accounts';
  static const String newSaleInvoice = '/invoices/new-sale';
  static const String newPurchaseInvoice = '/invoices/new-purchase';
  static const String addCustomer = '/customers/add';
  static const String customerDetail = '/customers/detail';
  static const String addProduct = '/products/add';
  static const String inventory = '/products/inventory';
  static const String statistics = '/statistics';
  static const String dailySalesReport = '/reports/daily-sales';
  static const String delegates = '/delegates';
  static const String customerImport = '/customers/import';
  static const String customerLoad = '/customers/load';
  static const String customerPrint = '/customers/print';
  static const String financialOrders = '/financial-orders';
  static const String suppliers = '/suppliers';
  static const String supplierDetail = '/suppliers/detail';
  static const String warehouses = '/warehouses';
  static const String accountLedger = '/accounts/ledger';
  static const String expenses = '/expenses';
  static const String employees = '/employees';
  static const String accountingAudit = '/accounting-audit';
  static const String quotations = '/quotations';
  static const String purchaseOrders = '/purchase-orders';
  static const String salesOrders = '/sales-orders';
  static const String shifts = '/shifts';
  static const String currencyExchange = '/currency-exchange';
  static const String cashTransfers = '/cash-transfers';
  static const String debts = '/debts';
  static const String appLock = '/app-lock';
  static const String notifications = '/notifications';
  static const String vouchers = '/vouchers';
  static const String newVoucher = '/vouchers/new';
  static const String dailyOperations = '/daily-operations';
  static const String stockTransfer = '/stock-transfer';
  static const String stocktaking = '/stocktaking';
  static const String inventoryVoucher = '/vouchers/inventory';
  static const String annualPosting = '/reports/annual-posting';
  static const String trialBalance = '/reports/trial-balance';
  static const String financialStatements = '/reports/financial-statements';
  static const String salesInvoices = '/invoices/sales';
  static const String purchaseInvoices = '/invoices/purchases';
  static const String invoiceDetail = '/invoices/detail';
  static const String bankReconciliation = '/bank-reconciliation';
  static const String licenseActivation = '/license-activation';
  static const String licenseStatus = '/license-status';

  // ── Voucher types ────────────────────────────────────────────
  static const String voucherReceipt = 'receipt';
  static const String voucherPayment = 'payment';
  static const String voucherSettlement = 'settlement';
  static const String voucherCompound = 'compound';
}
