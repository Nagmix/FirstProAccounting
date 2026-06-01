import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
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
/// directly. All SQL queries are now in repository/service methods.
/// Registered in [service_locator.dart] as a lazy singleton.
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

      // Load data in parallel — all via repository/service methods, no raw SQL
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
        // Today's purchases (via InvoiceRepository)
        _invoiceRepo.getTotalPurchasesForDateRange(currency, startStr, endStr),
        // Today's expenses (via ExpenseRepository)
        _expenseRepo.getTotalExpensesForDateRange(currency, startStr, endStr),
        // Today's COGS (via InvoiceRepository)
        _invoiceRepo.getCOGSForDateRange(currency, startStr, endStr),
        // Cash balance for currency (via CashBoxService)
        _cashBoxService.getCashBalanceForCurrency(currency),
        // Top products
        _reportService.getTopProducts(5, currency: currency),
      ]);

      todaySales = results[0] as double;
      yesterdaySales = results[1] as double;
      todayInvoiceCount = (results[2] as num?)?.toInt() ?? 0;
      recentInvoices = (results[3] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      productCount = results[4] as int;
      customerCount = results[5] as int;
      totalPurchases = results[6] as double;
      totalExpenses = results[7] as double;
      totalCOGS = results[8] as double;
      cashBalance = results[9] as double;
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
