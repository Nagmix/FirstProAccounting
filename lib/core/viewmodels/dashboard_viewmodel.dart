import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/datasources/repositories/invoice_repository.dart';
import '../../data/datasources/repositories/product_repository.dart';
import '../../data/datasources/repositories/customer_repository.dart';
import '../../data/datasources/repositories/expense_repository.dart';
import '../../data/datasources/repositories/reference_data_repository.dart';
import '../../data/datasources/services/report_service.dart';
import '../../data/datasources/services/cash_box_service.dart';
import '../utils/money_helper.dart';

/// ViewModel for Dashboard — manages dashboard data loading and refresh.
///
/// Uses dependency-injected repositories/services instead of DatabaseHelper
/// directly. Registered in [service_locator.dart] as a lazy singleton.
class DashboardViewModel extends ChangeNotifier {
  final InvoiceRepository _invoiceRepo = locator<InvoiceRepository>();
  final ProductRepository _productRepo = locator<ProductRepository>();
  final CustomerRepository _customerRepo = locator<CustomerRepository>();
  final ExpenseRepository _expenseRepo = locator<ExpenseRepository>();
  final ReferenceDataRepository _refData = locator<ReferenceDataRepository>();
  final ReportService _reportService = locator<ReportService>();
  final CashBoxService _cashBoxService = locator<CashBoxService>();

  // ── Dashboard state ──
  double todaySales = 0.0;
  double yesterdaySales = 0.0;
  int todayInvoiceCount = 0;
  double totalPurchases = 0.0;
  double totalExpenses = 0.0;
  double totalCOGS = 0.0;
  double grossProfit = 0.0;
  double netProfit = 0.0;
  double cashBalance = 0.0;
  int invoiceCount = 0;
  int productCount = 0;
  int customerCount = 0;

  List<Map<String, dynamic>> recentTransactions = [];
  List<Map<String, dynamic>> recentInvoices = [];
  List<Map<String, dynamic>> topProducts = [];

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Refresh all dashboard data from the database.
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      final defaultCurrency = await _refData.getDefaultCurrency();
      final currency = defaultCurrency != null
          ? (defaultCurrency['code'] as String?) ?? 'YER'
          : 'YER';

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final startStr = startOfDay.toIso8601String();
      final endStr = endOfDay.toIso8601String();

      // Use the raw database for complex aggregation queries
      // (these have no repository method yet — will be migrated in future step)
      final db = await locator<DatabaseHelper>().database;

      // Load data in parallel where possible
      final results = await Future.wait([
        // Today's sales
        _invoiceRepo.getTotalSalesForDate(today),
        // Yesterday's sales
        _invoiceRepo.getTotalSalesForDate(yesterday),
        // Today's invoice count
        _invoiceRepo.getInvoiceCountForDate(today),
        // Recent invoices
        _invoiceRepo.getRecentInvoices(limit: 5),
        // Product count
        _productRepo.getProductCount(),
        // Customer count
        _customerRepo.getCustomerCount(),
        // Today's purchases (raw SQL)
        db.rawQuery(
          "SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type = 'purchase' AND is_return = 0 AND currency = ? AND created_at >= ? AND created_at < ?",
          [currency, startStr, endStr],
        ),
        // Today's expenses (raw SQL)
        db.rawQuery(
          "SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE currency = ? AND expense_date >= ? AND expense_date < ?",
          [currency, startStr, endStr],
        ),
        // Today's COGS (raw SQL)
        db.rawQuery(
          "SELECT CAST(COALESCE(SUM("
          "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
          "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
          "), 0) AS INTEGER) AS total_cogs "
          "FROM invoice_items ii "
          "INNER JOIN invoices i ON ii.invoice_id = i.id "
          "LEFT JOIN products p ON ii.product_id = p.id "
          "WHERE i.type IN ('sale','pos') AND i.is_return = 0 "
          "AND i.currency = ? AND i.created_at >= ? AND i.created_at < ?",
          [currency, startStr, endStr],
        ),
        // Cash balance (raw SQL)
        db.rawQuery(
          "SELECT COALESCE(SUM(balance), 0) AS total FROM cash_boxes WHERE currency = ?",
          [currency],
        ),
        // Top products
        _reportService.getTopProducts(5, currency: currency),
      ]);

      todaySales = results[0] as double;
      yesterdaySales = results[1] as double;
      todayInvoiceCount = (results[2] as num?)?.toInt() ?? 0;
      recentInvoices = (results[3] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      productCount = results[4] as int;
      customerCount = results[5] as int;
      totalPurchases = MoneyHelper.readCalculatedMoney((results[6] as List).first['total']);
      totalExpenses = MoneyHelper.readCalculatedMoney((results[7] as List).first['total']);

      try {
        totalCOGS = MoneyHelper.readCalculatedMoney((results[8] as List).first['total_cogs']);
      } catch (e) {
        debugPrint('COGS calculation error on dashboard: $e');
        totalCOGS = 0.0;
      }

      cashBalance = MoneyHelper.readCalculatedMoney((results[9] as List).first['total']);
      topProducts = results[10] as List<Map<String, dynamic>>;

      // Calculate profit
      grossProfit = todaySales - totalCOGS;
      netProfit = grossProfit - totalExpenses;

      // Invoice count (total)
      final allInvoices = await _invoiceRepo.getAllInvoices();
      invoiceCount = allInvoices.length;

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      debugPrint('DashboardViewModel refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
