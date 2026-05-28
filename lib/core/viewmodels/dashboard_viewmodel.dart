import 'package:flutter/foundation.dart';
import '../../data/datasources/database_helper.dart';
import '../../core/utils/money_helper.dart';

/// ViewModel for Dashboard — manages dashboard data loading and refresh.
/// Extracted from DashboardScreen State (H-08).
class DashboardViewModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  double totalSales = 0.0;
  double totalPurchases = 0.0;
  double totalExpenses = 0.0;
  double cashBalance = 0.0;
  int invoiceCount = 0;
  int productCount = 0;
  int customerCount = 0;

  List<Map<String, dynamic>> recentTransactions = [];
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
      final defaultCurrency = await _db.getDefaultCurrency();
      final currency = defaultCurrency != null
          ? (defaultCurrency['code'] as String?) ?? 'YER'
          : 'YER';

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final startStr = startOfDay.toIso8601String();
      final endStr = endOfDay.toIso8601String();

      final db = await _db.database;

      // Today's sales
      final salesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type IN ('sale', 'pos') AND is_return = 0 AND currency = ? AND created_at >= ? AND created_at < ?",
        [currency, startStr, endStr],
      );
      totalSales = MoneyHelper.readMoney(salesResult.first['total']);

      // Today's purchases
      final purchasesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type = 'purchase' AND is_return = 0 AND currency = ? AND created_at >= ? AND created_at < ?",
        [currency, startStr, endStr],
      );
      totalPurchases = MoneyHelper.readMoney(purchasesResult.first['total']);

      // Today's expenses
      final expensesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE currency = ? AND expense_date >= ? AND expense_date < ?",
        [currency, startStr, endStr],
      );
      totalExpenses = MoneyHelper.readMoney(expensesResult.first['total']);

      // Cash balance
      final cashResult = await db.rawQuery(
        "SELECT COALESCE(SUM(balance), 0) AS total FROM cash_boxes WHERE currency = ?",
        [currency],
      );
      cashBalance = MoneyHelper.readMoney(cashResult.first['total']);

      // Counts — use public methods
      final invoices = await _db.getAllInvoices();
      invoiceCount = invoices.length;
      productCount = await _db.getProductCount();
      customerCount = await _db.getCustomerCount();

      // Recent transactions
      recentTransactions = await db.rawQuery(
        "SELECT t.*, a.name_ar AS account_name FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id ORDER BY t.date DESC LIMIT 10",
      );

      // Top products — use public method
      topProducts = await _db.getTopProducts(5, currency: currency);

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
