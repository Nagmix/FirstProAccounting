import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../widgets/bar_chart_widget.dart';
import '../../../core/constants/app_constants.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedReportType = 'المبيعات';
  String _selectedCurrency = 'الكل';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _selectedAccountId;
  String _selectedAccountType = 'الكل';
  String _searchQuery = '';

  static const List<String> _reportTypes = [
    'المبيعات',
    'المشتريات',
    'الأرباح والخسائر',
    'حركة الحسابات',
    'حركة جميع الحسابات',
    'حركة الصندوق',
    'ميزان المراجعة',
    'المخزون',
    'ديون العملاء',
    'ديون الموردين',
    'حسابات بدون حركة',
    'ربح الفواتير',
    'حركة المخزون',
    'تكلفة المخزون',
    'العمليات اليومية',
  ];

  static const List<String> _currencyOptions = ['الكل', 'ر.ي', 'ر.س', r'$'];

  static const List<MapEntry<String, String>> _accountTypes = [
    MapEntry('الكل', 'الكل'),
    MapEntry('أصول', 'ASSET'),
    MapEntry('خصوم', 'LIABILITY'),
    MapEntry('تكاليف', 'COST'),
    MapEntry('إيرادات', 'REVENUE'),
    MapEntry('مصاريف', 'EXPENSE'),
  ];

  bool _isLoading = true;
  double _totalRevenue = 0.0;
  double _totalPurchases = 0.0;
  double _totalOperatingExpenses = 0.0;
  double _totalExpenses = 0.0; // kept for backward compat in summary cards
  double _netProfit = 0.0;
  double _grossProfit = 0.0;
  int _invoiceCount = 0;
  List<BarData> _dailySalesData = [];
  List<_TopProduct> _topProducts = [];
  List<_RecentInvoice> _recentInvoices = [];
  List<_AccountMovement> _accountMovements = [];
  List<_AllAccountMovement> _allAccountMovements = [];
  List<_TrialBalanceItem> _trialBalanceItems = [];
  List<_DebtItem> _debtItems = [];
  List<_CashBoxMovement> _cashBoxMovements = [];
  List<_InventoryItem> _inventoryItems = [];
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;

  // بيانات التقارير الجديدة
  List<Map<String, dynamic>> _accountsWithoutMovements = [];
  List<Map<String, dynamic>> _invoiceProfitItems = [];
  List<Map<String, dynamic>> _inventoryMovementItems = [];
  List<Map<String, dynamic>> _inventoryCostItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _currencyCode() {
    switch (_selectedCurrency) {
      case 'ر.ي':
        return 'YER';
      case 'ر.س':
        return 'SAR';
      case r'$':
        return 'USD';
      default:
        return null;
    }
  }

  Future<void> _loadReportData() async {
    try {
      final db = await DatabaseHelper().database;
      final dbHelper = DatabaseHelper();

      String dateFilter = '';
      List<dynamic> dateArgs = [];
      if (_dateFrom != null) {
        dateFilter += ' AND created_at >= ?';
        dateArgs.add(_dateFrom!.toIso8601String());
      }
      if (_dateTo != null) {
        final toDate = _dateTo!.add(const Duration(days: 1));
        dateFilter += ' AND created_at < ?';
        dateArgs.add(toDate.toIso8601String());
      }

      String currencyFilter = '';
      List<dynamic> currencyArgs = [];
      final cc = _currencyCode();
      if (cc != null) {
        currencyFilter = ' AND currency = ?';
        currencyArgs.add(cc);
      }
      final allArgs = [...dateArgs, ...currencyArgs];

      // ── Sales Revenue ──
      final revenueResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'pos') AND is_return = 0"
        "$dateFilter$currencyFilter",
        allArgs,
      );
      final totalRevenue =
          (revenueResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // ── Purchases ──
      final expenseResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'purchase' AND is_return = 0"
        "$dateFilter$currencyFilter",
        allArgs,
      );
      final totalExpenses =
          (expenseResult.first['total'] as num?)?.toDouble() ?? 0.0;

      // ── Actual Expenses ──
      String expDateFilter =
          dateFilter.replaceAll('created_at', 'expense_date');
      final actualExpensesResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses WHERE 1=1"
        "$expDateFilter$currencyFilter",
        [...dateArgs, ...currencyArgs],
      );
      final actualExpenses =
          (actualExpensesResult.first['total'] as num?)?.toDouble() ?? 0.0;
      final netProfit = totalRevenue - totalExpenses - actualExpenses;

      // ── Invoice Count ──
      final countResult = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM invoices WHERE is_return = 0"
        "$dateFilter$currencyFilter",
        allArgs,
      );
      final invoiceCount =
          (countResult.first['cnt'] as num?)?.toInt() ?? 0;

      // ── Daily Sales Chart ──
      final now = DateTime.now();
      const dayLabels = [
        'السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'
      ];
      final List<BarData> dailySales = [];
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dayStart = DateTime(date.year, date.month, date.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        final dayResult = await db.rawQuery(
          "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'pos') AND is_return = 0 AND created_at >= ? AND created_at < ?",
          [dayStart.toIso8601String(), dayEnd.toIso8601String()],
        );
        final dayTotal =
            (dayResult.first['total'] as num?)?.toDouble() ?? 0.0;
        int labelIndex;
        if (date.weekday == 6) {
          labelIndex = 0;
        } else if (date.weekday == 7) {
          labelIndex = 1;
        } else {
          labelIndex = date.weekday + 1;
        }
        dailySales.add(BarData(label: dayLabels[labelIndex], value: dayTotal));
      }

      // ── Top Products ──
      final topProductsResult = await db.rawQuery(
        "SELECT ii.product_id, ii.product_name, SUM(ii.quantity) AS total_quantity, SUM(ii.total_price) AS total_revenue "
        "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id = i.id "
        "WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 "
        "GROUP BY ii.product_id ORDER BY total_quantity DESC LIMIT 10",
      );
      final List<_TopProduct> topProducts =
          topProductsResult.map((row) => _TopProduct(
                name: row['product_name'] as String? ?? 'منتج غير معروف',
                quantity: (row['total_quantity'] as num?)?.toInt() ?? 0,
                revenue: (row['total_revenue'] as num?)?.toDouble() ?? 0.0,
              )).toList();

      // ── Recent Invoices ──
      final recentResult = await db.rawQuery(
        "SELECT i.id, i.type, i.total, i.is_return, i.created_at, i.currency, "
        "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') "
        "WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') "
        "ELSE 'بدون عميل' END AS entity_name "
        "FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id "
        "LEFT JOIN suppliers s ON i.supplier_id = s.id "
        "ORDER BY i.created_at DESC LIMIT 20",
      );
      final List<_RecentInvoice> recentInvoices =
          recentResult.map((row) {
        final type = row['type'] as String? ?? 'sale';
        final isReturn = (row['is_return'] as int?) == 1;
        return _RecentInvoice(
          id: row['id'] as String? ?? '',
          title: type == 'sale' || type == 'pos'
              ? (isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات')
              : (isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات'),
          subtitle: row['entity_name'] as String? ?? '',
          date: row['created_at'] as String? ?? '',
          total: (row['total'] as num?)?.toDouble() ?? 0.0,
          currency: row['currency'] as String? ?? 'YER',
          icon: type == 'sale' || type == 'pos'
              ? (isReturn ? Icons.undo : Icons.receipt_long_outlined)
              : (isReturn ? Icons.undo : Icons.shopping_cart_outlined),
          color: type == 'sale' || type == 'pos'
              ? (isReturn ? AppColors.warning : AppColors.success)
              : (isReturn ? AppColors.warning : AppColors.error),
        );
      }).toList();

      // ── Account movements (single account) ──
      List<_AccountMovement> accountMovements = [];
      if (_selectedAccountId != null) {
        final transactions =
            await dbHelper.getAccountTransactions(_selectedAccountId!);
        double runningBalance = 0.0;
        for (final tx in transactions) {
          final debit = (tx['debit'] as num?)?.toDouble() ?? 0.0;
          final credit = (tx['credit'] as num?)?.toDouble() ?? 0.0;
          runningBalance += (debit - credit);
          accountMovements.add(_AccountMovement(
            date: tx['date'] as String? ?? '',
            description: tx['description'] as String? ?? '',
            debit: debit,
            credit: credit,
            balance: runningBalance,
          ));
        }
      }

      // ── All accounts movements ──
      List<_AllAccountMovement> allAccountMovements = [];
      {
        String allTxDateFilter = dateFilter.replaceAll('created_at', 't.created_at');
        String allTxCurrencyFilter = '';
        List<dynamic> allTxArgs = [...dateArgs];
        if (cc != null) {
          allTxCurrencyFilter = ' AND a.currency = ?';
          allTxArgs.add(cc);
        }
        final allTx = await db.rawQuery(
          "SELECT t.id, t.account_id, t.debit, t.credit, t.description, t.date, t.created_at, "
          "a.name_ar AS account_name, a.account_code, a.currency "
          "FROM transactions t "
          "LEFT JOIN accounts a ON t.account_id = a.id "
          "WHERE 1=1 $allTxDateFilter $allTxCurrencyFilter "
          "ORDER BY t.date DESC, t.created_at DESC",
          allTxArgs,
        );
        for (final tx in allTx) {
          allAccountMovements.add(_AllAccountMovement(
            date: tx['date'] as String? ?? '',
            accountName: tx['account_name'] as String? ?? 'غير معروف',
            accountCode: tx['account_code'] as String? ?? '',
            currency: tx['currency'] as String? ?? 'YER',
            description: tx['description'] as String? ?? '',
            debit: (tx['debit'] as num?)?.toDouble() ?? 0.0,
            credit: (tx['credit'] as num?)?.toDouble() ?? 0.0,
          ));
        }
      }

      // ── Trial balance ──
      List<_TrialBalanceItem> trialBalanceItems = [];
      double totalDebit = 0.0;
      double totalCredit = 0.0;
      final accounts = await dbHelper.getAllAccounts();
      for (final account in accounts) {
        if (cc != null && account['currency'] != cc) continue;
        final accountId = account['id'] as int;
        final balance = await dbHelper.getAccountBalance(accountId);
        if (balance == 0.0) continue;
        final isDebit = balance > 0;
        if (isDebit) {
          totalDebit += balance.abs();
        } else {
          totalCredit += balance.abs();
        }
        trialBalanceItems.add(_TrialBalanceItem(
          accountId: accountId,
          accountName: account['name_ar'] as String? ?? '',
          accountCode: account['account_code'] as String? ?? '',
          accountType: account['account_type'] as String? ?? '',
          currency: account['currency'] as String? ?? 'YER',
          debit: isDebit ? balance.abs() : 0.0,
          credit: isDebit ? 0.0 : balance.abs(),
        ));
      }

      // ── Cash Box Movements ──
      List<_CashBoxMovement> cashBoxMovements = [];
      {
        final cashBoxes = await dbHelper.getAllCashBoxes();
        for (final cb in cashBoxes) {
          if (cc != null && cb['currency'] != cc) continue;
          final cbId = cb['id'] as int;
          final cbName = cb['name'] as String? ?? '';
          final cbType = cb['type'] as String? ?? 'cash_box';
          final cbBalance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
          final cbBalanceType = cb['balance_type'] as String? ?? 'credit';
          final cbCurrency = cb['currency'] as String? ?? 'YER';

          // Get invoices for this cash box
          String invDateFilter = dateFilter;
          String invCurrencyFilter = currencyFilter;
          final invResult = await db.rawQuery(
            "SELECT type, COUNT(*) as cnt, COALESCE(SUM(total), 0.0) as total "
            "FROM invoices WHERE cash_box_id = ? AND is_return = 0"
            "$invDateFilter$invCurrencyFilter "
            "GROUP BY type",
            [cbId, ...dateArgs, ...currencyArgs],
          );

          double salesTotal = 0;
          int salesCount = 0;
          double purchaseTotal = 0;
          int purchaseCount = 0;

          for (final inv in invResult) {
            final invType = inv['type'] as String? ?? '';
            final invTotal = (inv['total'] as num?)?.toDouble() ?? 0.0;
            final invCnt = (inv['cnt'] as num?)?.toInt() ?? 0;
            if (invType == 'sale' || invType == 'pos') {
              salesTotal = invTotal;
              salesCount = invCnt;
            } else if (invType == 'purchase') {
              purchaseTotal = invTotal;
              purchaseCount = invCnt;
            }
          }

          // Get cash transfers for this cash box
          String ctDateFilter = dateFilter;
          final transfersInResult = await db.rawQuery(
            "SELECT COALESCE(SUM(amount), 0.0) AS total, COUNT(*) AS cnt "
            "FROM cash_transfers WHERE to_cash_box_id = ?"
            "$ctDateFilter",
            [cbId, ...dateArgs],
          );
          final transfersOutResult = await db.rawQuery(
            "SELECT COALESCE(SUM(amount), 0.0) AS total, COUNT(*) AS cnt "
            "FROM cash_transfers WHERE from_cash_box_id = ?"
            "$ctDateFilter",
            [cbId, ...dateArgs],
          );
          final transfersInTotal = (transfersInResult.first['total'] as num?)?.toDouble() ?? 0.0;
          final transfersInCount = (transfersInResult.first['cnt'] as num?)?.toInt() ?? 0;
          final transfersOutTotal = (transfersOutResult.first['total'] as num?)?.toDouble() ?? 0.0;
          final transfersOutCount = (transfersOutResult.first['cnt'] as num?)?.toInt() ?? 0;

          // Get currency exchanges for this cash box
          String ceDateFilter = dateFilter;
          final exchangesInResult = await db.rawQuery(
            "SELECT COALESCE(SUM(to_amount), 0.0) AS total, COUNT(*) AS cnt "
            "FROM currency_exchanges WHERE to_cash_box_id = ?"
            "$ceDateFilter",
            [cbId, ...dateArgs],
          );
          final exchangesOutResult = await db.rawQuery(
            "SELECT COALESCE(SUM(from_amount), 0.0) AS total, COUNT(*) AS cnt "
            "FROM currency_exchanges WHERE from_cash_box_id = ?"
            "$ceDateFilter",
            [cbId, ...dateArgs],
          );
          final exchangesInTotal = (exchangesInResult.first['total'] as num?)?.toDouble() ?? 0.0;
          final exchangesInCount = (exchangesInResult.first['cnt'] as num?)?.toInt() ?? 0;
          final exchangesOutTotal = (exchangesOutResult.first['total'] as num?)?.toDouble() ?? 0.0;
          final exchangesOutCount = (exchangesOutResult.first['cnt'] as num?)?.toInt() ?? 0;

          cashBoxMovements.add(_CashBoxMovement(
            id: cbId,
            name: cbName,
            type: cbType,
            balance: cbBalance,
            balanceType: cbBalanceType,
            currency: cbCurrency,
            salesTotal: salesTotal,
            salesCount: salesCount,
            purchaseTotal: purchaseTotal,
            purchaseCount: purchaseCount,
            transfersInTotal: transfersInTotal,
            transfersInCount: transfersInCount,
            transfersOutTotal: transfersOutTotal,
            transfersOutCount: transfersOutCount,
            exchangesInTotal: exchangesInTotal,
            exchangesInCount: exchangesInCount,
            exchangesOutTotal: exchangesOutTotal,
            exchangesOutCount: exchangesOutCount,
          ));
        }
      }

      // ── Inventory Report ──
      List<_InventoryItem> inventoryItems = [];
      {
        String prodFilter = 'WHERE p.is_active = 1';
        List<dynamic> prodArgs = [];
        if (cc != null) {
          // No direct currency on products, skip currency filter for inventory
        }
        final prodResult = await db.rawQuery(
          "SELECT p.id, p.name_ar, p.barcode, p.item_code, p.current_stock, "
          "p.cost_price, p.sell_price, p.min_stock, p.warehouse_id, "
          "w.name AS warehouse_name, c.name AS category_name "
          "FROM products p "
          "LEFT JOIN warehouses w ON p.warehouse_id = w.id "
          "LEFT JOIN categories c ON p.category_id = c.id "
          "$prodFilter ORDER BY p.current_stock DESC",
          prodArgs,
        );
        for (final p in prodResult) {
          final stock = (p['current_stock'] as num?)?.toDouble() ?? 0.0;
          final minStock = (p['min_stock'] as num?)?.toDouble() ?? 0.0;
          inventoryItems.add(_InventoryItem(
            id: p['id'] as int,
            name: p['name_ar'] as String? ?? '',
            barcode: p['barcode'] as String?,
            itemCode: p['item_code'] as String?,
            currentStock: stock,
            costPrice: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
            sellPrice: (p['sell_price'] as num?)?.toDouble() ?? 0.0,
            minStock: minStock,
            warehouseName: p['warehouse_name'] as String?,
            categoryName: p['category_name'] as String?,
            isLowStock: stock > 0 && stock <= minStock,
            isOutOfStock: stock <= 0,
          ));
        }
      }

      // ── Debt items ──
      // "ديون لنا" = owed TO us = balance_type 'debit' (they owe us)
      // "ديون علينا" = we owe THEM = balance_type 'credit' (we owe them)
      List<_DebtItem> debtItems = [];
      if (_selectedReportType == 'ديون العملاء') {
        final customers = await dbHelper.getAllCustomers();
        for (final c in customers) {
          final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
          final balanceType = c['balance_type'] as String? ?? 'credit';
          if (balance > 0) {
            debtItems.add(_DebtItem(
              name: c['name'] as String? ?? '',
              balance: balance,
              balanceType: balanceType,
              currency: c['currency'] as String? ?? 'YER',
              phone: c['phone'] as String?,
            ));
          }
        }
      } else if (_selectedReportType == 'ديون الموردين') {
        final suppliers = await dbHelper.getAllSuppliers();
        for (final s in suppliers) {
          final balance = (s['balance'] as num?)?.toDouble() ?? 0.0;
          final balanceType = s['balance_type'] as String? ?? 'debit';
          if (balance > 0) {
            debtItems.add(_DebtItem(
              name: s['name'] as String? ?? '',
              balance: balance,
              balanceType: balanceType,
              currency: s['currency'] as String? ?? 'YER',
              phone: s['phone'] as String?,
            ));
          }
        }
      }

      final grossProfit = totalRevenue - totalExpenses;

      // ── التقارير الإضافية ──
      // حسابات بدون حركة
      final accountsWithoutMovements = await dbHelper.getAccountsWithoutMovements();

      // ربح الفواتير
      final invoiceProfitItems = await dbHelper.getInvoiceProfitReport(
        startDate: _dateFrom,
        endDate: _dateTo,
      );

      // حركة المخزون
      final inventoryMovementItems = await dbHelper.getInventoryMovementReport(
        startDate: _dateFrom,
        endDate: _dateTo,
      );

      // تكلفة المخزون
      final inventoryCostItems = await dbHelper.getInventoryCostReport();

      if (mounted) {
        setState(() {
          _totalRevenue = totalRevenue;
          _totalPurchases = totalExpenses;
          _totalOperatingExpenses = actualExpenses;
          _totalExpenses = totalExpenses + actualExpenses;
          _grossProfit = grossProfit;
          _netProfit = netProfit;
          _invoiceCount = invoiceCount;
          _dailySalesData = dailySales;
          _topProducts = topProducts;
          _recentInvoices = recentInvoices;
          _accountMovements = accountMovements;
          _allAccountMovements = allAccountMovements;
          _trialBalanceItems = trialBalanceItems;
          _totalDebit = totalDebit;
          _totalCredit = totalCredit;
          _debtItems = debtItems;
          _cashBoxMovements = cashBoxMovements;
          _inventoryItems = inventoryItems;
          _accountsWithoutMovements = accountsWithoutMovements;
          _invoiceProfitItems = invoiceProfitItems;
          _inventoryMovementItems = inventoryMovementItems;
          _inventoryCostItems = inventoryCostItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقارير: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _dateFrom = picked);
      _loadReportData();
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _dateTo = picked);
      _loadReportData();
    }
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedCurrency = 'الكل';
      _isLoading = true;
    });
    _loadReportData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التقارير والإحصائيات'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'التقارير', icon: Icon(Icons.bar_chart, size: 20)),
              Tab(text: 'حركة الحسابات', icon: Icon(Icons.swap_horiz, size: 20)),
            ],
          ),
          actions: [
            if (_dateFrom != null || _dateTo != null || _selectedCurrency != 'الكل')
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'مسح الفلاتر',
                onPressed: _clearFilters,
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () {
                setState(() => _isLoading = true);
                _loadReportData();
              },
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadReportData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewPadding.bottom + 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterSection(theme, isDark),
                          const SizedBox(height: 16),
                          _buildReportContent(theme, isDark),
                        ],
                      ),
                    ),
                  ),
            _buildAccountMovementsTab(theme, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent(ThemeData theme, bool isDark) {
    switch (_selectedReportType) {
      case 'حركة الحسابات':
        return _buildAccountMovementReport(theme, isDark);
      case 'حركة جميع الحسابات':
        return _buildAllAccountMovementReport(theme, isDark);
      case 'ميزان المراجعة':
        return _buildTrialBalanceReport(theme, isDark);
      case 'حركة الصندوق':
        return _buildCashBoxReport(theme, isDark);
      case 'المخزون':
        return _buildInventoryReport(theme, isDark);
      case 'ديون العملاء':
      case 'ديون الموردين':
        return _buildDebtReport(theme, isDark);
      case 'المشتريات':
        return _buildPurchasesReport(theme, isDark);
      case 'الأرباح والخسائر':
        return _buildProfitLossReport(theme, isDark);
      case 'حسابات بدون حركة':
        return _buildAccountsWithoutMovementsReport(theme, isDark);
      case 'ربح الفواتير':
        return _buildInvoiceProfitReport(theme, isDark);
      case 'حركة المخزون':
        return _buildInventoryMovementReport(theme, isDark);
      case 'تكلفة المخزون':
        return _buildInventoryCostReport(theme, isDark);
      case 'العمليات اليومية':
        return _buildDailyOperationsLink(theme, isDark);
      default:
        return _buildSalesReport(theme, isDark);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SALES REPORT (المبيعات)
  // ══════════════════════════════════════════════════════════════
  Widget _buildSalesReport(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(theme, isDark),
        const SizedBox(height: 20),
        if (_dailySalesData.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BarChartWidget(
              data: _dailySalesData,
              title: 'المبيعات اليومية (آخر 7 أيام)',
              barColor: AppColors.primary,
              height: 240,
            ),
          ),
          const SizedBox(height: 20),
        ],
        _buildTopProductsSection(theme, isDark),
        const SizedBox(height: 20),
        _buildRecentInvoicesSection(theme, isDark),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  PURCHASES REPORT (المشتريات)
  // ══════════════════════════════════════════════════════════════
  Widget _buildPurchasesReport(ThemeData theme, bool isDark) {
    final purchaseInvoices = _recentInvoices.where((i) =>
        i.title.contains('مشتريات') && !i.title.contains('مرتجع')).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(theme, isDark),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_cart, color: AppColors.error, size: 22),
                  const SizedBox(width: 8),
                  Text('فواتير المشتريات', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              if (purchaseInvoices.isEmpty)
                _buildEmptyState(theme, Icons.shopping_cart, 'لا توجد فواتير مشتريات')
              else
                ...purchaseInvoices.map((invoice) => _RecentInvoiceCard(invoice: invoice, isDark: isDark)),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  PROFIT & LOSS REPORT (الأرباح والخسائر)
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfitLossReport(ThemeData theme, bool isDark) {
    final profitPercent = _totalRevenue > 0 ? (_netProfit / _totalRevenue * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main P&L Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _netProfit >= 0
                    ? [AppColors.success.withValues(alpha: 0.1), AppColors.success.withValues(alpha: 0.05)]
                    : [AppColors.error.withValues(alpha: 0.1), AppColors.error.withValues(alpha: 0.05)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(_netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                    size: 48, color: _netProfit >= 0 ? AppColors.success : AppColors.error),
                const SizedBox(height: 12),
                Text(
                  _netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  CurrencyFormatter.formatWithSymbol(_netProfit.abs()),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _netProfit >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'هامش الربح الصافي: ${profitPercent.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _netProfit >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // P&L Breakdown - clear structure
          _buildPLRow(theme, isDark, 'إجمالي الإيرادات (المبيعات)', _totalRevenue, AppColors.success, Icons.arrow_outward),
          const SizedBox(height: 8),
          _buildPLRow(theme, isDark, 'تكلفة المشتريات', _totalPurchases, AppColors.error, Icons.south_east),
          const SizedBox(height: 8),
          _buildPLRow(theme, isDark, 'ربح إجمالي', _grossProfit, _grossProfit >= 0 ? AppColors.success : AppColors.error, _grossProfit >= 0 ? Icons.trending_up : Icons.trending_down),
          const SizedBox(height: 8),
          _buildPLRow(theme, isDark, 'المصاريف التشغيلية', _totalOperatingExpenses, AppColors.warning, Icons.remove),
          const SizedBox(height: 16),
          // Visual Bar
          Container(
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surfaceVariant,
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final totalCosts = _totalPurchases + _totalOperatingExpenses;
              final revenueWidth = _totalRevenue > 0 && (_totalRevenue + totalCosts) > 0 ? (_totalRevenue / (_totalRevenue + totalCosts) * totalWidth).clamp(0.0, totalWidth) as double : 0.0;
              return Row(
                children: [
                  Container(
                    width: revenueWidth,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                    ),
                    alignment: Alignment.center,
                    child: Text('إيرادات', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.7),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      ),
                      alignment: Alignment.center,
                      child: Text('تكاليف', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPLRow(ThemeData theme, bool isDark, String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(CurrencyFormatter.formatWithSymbol(value),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  CASH BOX REPORT (حركة الصندوق)
  // ══════════════════════════════════════════════════════════════
  Widget _buildCashBoxReport(ThemeData theme, bool isDark) {
    if (_cashBoxMovements.isEmpty) {
      return _buildEmptyState(theme, Icons.account_balance_wallet, 'لا توجد صناديق');
    }
    final totalBalance = _cashBoxMovements.fold(0.0, (s, m) => s + (m.balanceType == 'credit' ? m.balance : -m.balance));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.secondary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.account_balance_wallet, size: 36, color: AppColors.primary),
                const SizedBox(height: 8),
                Text('إجمالي الأرصدة', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.formatWithSymbol(totalBalance.abs()),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                Text(totalBalance >= 0 ? 'له' : 'عليه',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: totalBalance >= 0 ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Cash box cards
          ..._cashBoxMovements.map((cb) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: (cb.type == 'bank' ? AppColors.info : AppColors.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          cb.type == 'bank' ? Icons.account_balance : Icons.account_balance_wallet,
                          color: cb.type == 'bank' ? AppColors.info : AppColors.primary, size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cb.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                            Text('${cb.type == 'bank' ? 'بنك' : 'صندوق'} - ${cb.currency}',
                                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(CurrencyFormatter.format(cb.balance),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text(cb.balanceType == 'credit' ? 'له' : 'عليه',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cb.balanceType == 'credit' ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatMini(theme, 'المبيعات', cb.salesTotal, cb.salesCount, AppColors.success),
                      ),
                      Container(width: 1, height: 40, color: AppColors.divider),
                      Expanded(
                        child: _buildStatMini(theme, 'المشتريات', cb.purchaseTotal, cb.purchaseCount, AppColors.error),
                      ),
                    ],
                  ),
                  if (cb.transfersInTotal > 0 || cb.transfersOutTotal > 0) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatMini(theme, 'تحويلات واردة', cb.transfersInTotal, cb.transfersInCount, AppColors.info, 'تحويل'),
                        ),
                        Container(width: 1, height: 40, color: AppColors.divider),
                        Expanded(
                          child: _buildStatMini(theme, 'تحويلات صادرة', cb.transfersOutTotal, cb.transfersOutCount, AppColors.warning, 'تحويل'),
                        ),
                      ],
                    ),
                  ],
                  if (cb.exchangesInTotal > 0 || cb.exchangesOutTotal > 0) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatMini(theme, 'صرافة واردة', cb.exchangesInTotal, cb.exchangesInCount, AppColors.info, 'عملية'),
                        ),
                        Container(width: 1, height: 40, color: AppColors.divider),
                        Expanded(
                          child: _buildStatMini(theme, 'صرافة صادرة', cb.exchangesOutTotal, cb.exchangesOutCount, AppColors.warning, 'عملية'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildStatMini(ThemeData theme, String label, double total, int count, Color color, [String countLabel = 'فاتورة']) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.formatCompactWithSymbol(total),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          Text('$count $countLabel', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  INVENTORY REPORT (المخزون)
  // ══════════════════════════════════════════════════════════════
  Widget _buildInventoryReport(ThemeData theme, bool isDark) {
    final lowStockItems = _inventoryItems.where((i) => i.isLowStock).toList();
    final outOfStockItems = _inventoryItems.where((i) => i.isOutOfStock).toList();
    final totalStockValue = _inventoryItems.fold(0.0, (s, i) => s + (i.currentStock * i.costPrice));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(child: _buildInventoryStatCard(theme, 'إجمالي الأصناف', '${_inventoryItems.length}', AppColors.primary, Icons.inventory_2)),
              const SizedBox(width: 8),
              Expanded(child: _buildInventoryStatCard(theme, 'قيمة المخزون', CurrencyFormatter.formatCompactWithSymbol(totalStockValue), AppColors.success, Icons.attach_money)),
              const SizedBox(width: 8),
              Expanded(child: _buildInventoryStatCard(theme, 'نفذ المخزون', '${outOfStockItems.length}', AppColors.error, Icons.warning)),
            ],
          ),
          const SizedBox(height: 16),
          // Alerts
          if (outOfStockItems.isNotEmpty) ...[
            _buildAlertBanner(theme, 'أصناف نفذت من المخزون (${outOfStockItems.length})', AppColors.error, Icons.error_outline),
            const SizedBox(height: 8),
          ],
          if (lowStockItems.isNotEmpty) ...[
            _buildAlertBanner(theme, 'أصناف قاربت على النفاد (${lowStockItems.length})', AppColors.warning, Icons.warning),
            const SizedBox(height: 12),
          ],
          // Inventory list
          if (_inventoryItems.isEmpty)
            _buildEmptyState(theme, Icons.inventory_2, 'لا توجد أصناف في المخزون')
          else
            ..._inventoryItems.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: (item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.isOutOfStock ? Icons.error_outline : item.isLowStock ? Icons.warning : Icons.inventory_2,
                    color: item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success, size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (item.categoryName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                        child: Text(item.categoryName!, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: AppColors.primary)),
                      ),
                  ],
                ),
                subtitle: Text(
                  '${item.barcode ?? item.itemCode ?? ""}${item.warehouseName != null ? " | ${item.warehouseName}" : ""}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${item.currentStock.toStringAsFixed(item.currentStock == item.currentStock.roundToDouble() ? 0 : 1)} قطعة',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success,
                        )),
                    Text('تكلفة: ${CurrencyFormatter.format(item.costPrice)}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                  ],
                ),
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildInventoryStatCard(ThemeData theme, String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          Text(title, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(ThemeData theme, String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: color))),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  ACCOUNT MOVEMENTS TAB (2nd Tab)
  // ══════════════════════════════════════════════════════════════
  Widget _buildAccountMovementsTab(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('اختر الحساب',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper().getAllAccounts(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final accounts = snap.data!;
                  return DropdownButtonFormField<int>(
                    value: _selectedAccountId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      prefixIcon: const Icon(Icons.account_balance_wallet,
                          size: 20),
                    ),
                    items: accounts
                        .map((acc) => DropdownMenuItem<int>(
                              value: acc['id'] as int,
                              child: Text(
                                "${acc['name_ar']} (${acc['currency']})",
                                style: const TextStyle(fontSize: 13),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedAccountId = val;
                        _isLoading = true;
                      });
                      _loadReportData();
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _buildDateChip('من', _dateFrom, _pickDateFrom, isDark)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildDateChip('إلى', _dateTo, _pickDateTo, isDark)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _accountMovements.isEmpty
              ? _buildEmptyState(theme, Icons.swap_horiz, 'اختر حساباً لعرض حركته')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _accountMovements.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == 0) return _buildMovementHeader(theme, isDark);
                    return _buildMovementRow(
                        _accountMovements[i - 1], theme, isDark, i - 1);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(icon, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(fontSize: 16, color: AppColors.textHint), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(
      String label, DateTime? date, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              date != null ? DateFormatter.formatDate(date) : label,
              style: TextStyle(fontSize: 13, color: date != null ? null : AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('التاريخ', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
          Expanded(flex: 3, child: Text('البيان', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
          Expanded(flex: 2, child: Text('مدين', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('دائن', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('الرصيد', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildMovementRow(_AccountMovement mov, ThemeData theme, bool isDark, int index) {
    final bgColor = index.isEven
        ? (isDark ? AppColors.darkSurface : AppColors.surface)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: bgColor),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(_formatDateShort(mov.date), style: theme.textTheme.bodySmall)),
          Expanded(flex: 3, child: Text(mov.description, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(mov.debit > 0 ? CurrencyFormatter.format(mov.debit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(mov.credit > 0 ? CurrencyFormatter.format(mov.credit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(CurrencyFormatter.format(mov.balance), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: mov.balance >= 0 ? AppColors.primary : AppColors.error), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  String _formatDateShort(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}";
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildAllAccountMovementReport(ThemeData theme, bool isDark) {
    if (_allAccountMovements.isEmpty) {
      return _buildEmptyState(theme, Icons.swap_horiz, 'لا توجد حركات - قم بإجراء عمليات بيع أو شراء أولاً');
    }

    double totalDebit = _allAccountMovements.fold(0.0, (s, m) => s + m.debit);
    double totalCredit = _allAccountMovements.fold(0.0, (s, m) => s + m.credit);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('إجمالي المدين', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      Text(CurrencyFormatter.format(totalDebit), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error)),
                    ],
                  ),
                ),
                Container(width: 1, height: 36, color: AppColors.divider),
                Expanded(
                  child: Column(
                    children: [
                      Text('إجمالي الدائن', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      Text(CurrencyFormatter.format(totalCredit), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success)),
                    ],
                  ),
                ),
                Container(width: 1, height: 36, color: AppColors.divider),
                Expanded(
                  child: Column(
                    children: [
                      Text('عدد الحركات', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      Text('${_allAccountMovements.length}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('التاريخ', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
                Expanded(flex: 3, child: Text('الحساب', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
                Expanded(flex: 3, child: Text('البيان', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
                Expanded(flex: 2, child: Text('مدين', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('دائن', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _allAccountMovements.length,
              itemBuilder: (ctx, i) {
                final mov = _allAccountMovements[i];
                final bgColor = i.isEven
                    ? (isDark ? AppColors.darkSurface : AppColors.surface)
                    : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant);
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(color: bgColor),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(_formatDateShort(mov.date), style: theme.textTheme.bodySmall)),
                      Expanded(flex: 3, child: Text(
                        '${mov.accountName} (${mov.currency})',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      )),
                      Expanded(flex: 3, child: Text(mov.description, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text(mov.debit > 0 ? CurrencyFormatter.format(mov.debit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                      Expanded(flex: 2, child: Text(mov.credit > 0 ? CurrencyFormatter.format(mov.credit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialBalanceReport(ThemeData theme, bool isDark) {
    if (_trialBalanceItems.isEmpty) {
      return _buildEmptyState(theme, Icons.balance, 'لا توجد أرصدة - قم بإجراء عمليات أولاً');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.secondary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(child: _buildTrialSummaryCard('إجمالي المدين', _totalDebit, AppColors.error, isDark)),
                Expanded(child: _buildTrialSummaryCard('إجمالي الدائن', _totalCredit, AppColors.success, isDark)),
                Expanded(child: _buildTrialSummaryCard('الفرق', (_totalDebit - _totalCredit).abs(), AppColors.warning, isDark)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Account type filter chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _accountTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_accountTypes[i].key, style: const TextStyle(fontSize: 12)),
                selected: _selectedAccountType == _accountTypes[i].key,
                onSelected: (_) => setState(() {
                  _selectedAccountType = _accountTypes[i].key;
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildTrialHeader(theme),
          ..._getFilteredTrialItems().map((item) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              border: Border(bottom: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text(item.accountCode, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(flex: 3, child: Text(item.accountName, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 1, child: Text(item.currency, style: theme.textTheme.bodySmall, textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(item.debit > 0 ? CurrencyFormatter.format(item.debit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(item.credit > 0 ? CurrencyFormatter.format(item.credit) : '-', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
              ],
            ),
          )),
          // Totals row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(top: BorderSide(width: 2, color: AppColors.primary)),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('الإجمالي', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary))),
                Expanded(flex: 1, child: const SizedBox()),
                Expanded(flex: 2, child: Text(CurrencyFormatter.format(_totalDebit), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(CurrencyFormatter.format(_totalCredit), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success), textAlign: TextAlign.center)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_TrialBalanceItem> _getFilteredTrialItems() {
    if (_selectedAccountType == 'الكل') return _trialBalanceItems;
    final typeCode = _accountTypes
        .firstWhere((e) => e.key == _selectedAccountType,
            orElse: () => const MapEntry('الكل', 'الكل'))
        .value;
    if (typeCode == 'الكل') return _trialBalanceItems;
    return _trialBalanceItems.where((i) => i.accountType == typeCode).toList();
  }

  Widget _buildTrialHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('الكود', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
          Expanded(flex: 3, child: Text('الحساب', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))),
          Expanded(flex: 1, child: Text('العملة', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('مدين', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('دائن', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTrialSummaryCard(String title, double value, Color color, bool isDark) {
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(CurrencyFormatter.formatCompactWithSymbol(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _buildAccountMovementReport(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper().getAllAccounts(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              var filteredAccounts = snap.data!;
              if (_selectedAccountType != 'الكل') {
                final typeCode = _accountTypes
                    .firstWhere((e) => e.key == _selectedAccountType,
                        orElse: () => const MapEntry('الكل', 'الكل'))
                    .value;
                if (typeCode != 'الكل') {
                  filteredAccounts = filteredAccounts
                      .where((a) => a['account_type'] == typeCode)
                      .toList();
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _accountTypes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => ChoiceChip(
                        label: Text(_accountTypes[i].key, style: const TextStyle(fontSize: 12)),
                        selected: _selectedAccountType == _accountTypes[i].key,
                        onSelected: (_) => setState(() {
                          _selectedAccountType = _accountTypes[i].key;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: _selectedAccountId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
                    ),
                    items: filteredAccounts.map((acc) => DropdownMenuItem<int>(
                      value: acc['id'] as int,
                      child: Text("${acc['name_ar']} (${acc['currency']})", style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (val) {
                      setState(() { _selectedAccountId = val; _isLoading = true; });
                      _loadReportData();
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_accountMovements.isNotEmpty) ...[
            _buildMovementHeader(theme, isDark),
            ..._accountMovements.asMap().entries.map((e) => _buildMovementRow(e.value, theme, isDark, e.key)),
          ] else ...[
            _buildEmptyState(theme, Icons.swap_horiz, 'اختر حساباً لعرض حركته'),
          ],
        ],
      ),
    );
  }

  Widget _buildDebtReport(ThemeData theme, bool isDark) {
    final isCustomer = _selectedReportType == 'ديون العملاء';

    // Separate debts by balance_type semantics:
    // "ديون لنا" (owed TO us): balance_type = 'debit'
    // "ديون علينا" (we owe them): balance_type = 'credit'
    final debtsOwedToUs = _debtItems.where((i) => i.balanceType == 'debit').toList();
    final debtsWeOwe = _debtItems.where((i) => i.balanceType == 'credit').toList();

    final totalDebtsOwedToUs = debtsOwedToUs.fold(0.0, (sum, item) => sum + item.balance);
    final totalDebtsWeOwe = debtsWeOwe.fold(0.0, (sum, item) => sum + item.balance);
    final netDebt = totalDebtsOwedToUs - totalDebtsWeOwe;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.error.withValues(alpha: 0.08),
                AppColors.warning.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(isCustomer ? Icons.people : Icons.local_shipping, size: 32, color: AppColors.primary),
                const SizedBox(height: 8),
                Text(
                  isCustomer ? 'ملخص ديون العملاء' : 'ملخص مديونيات الموردين',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text('ديون لنا', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(CurrencyFormatter.formatCompactWithSymbol(totalDebtsOwedToUs),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success)),
                        Text('${debtsOwedToUs.length} ${isCustomer ? "عميل" : "مورد"}',
                            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      ],
                    ),
                    Container(width: 1, height: 50, color: AppColors.divider),
                    Column(
                      children: [
                        Text('ديون علينا', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(CurrencyFormatter.formatCompactWithSymbol(totalDebtsWeOwe),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error)),
                        Text('${debtsWeOwe.length} ${isCustomer ? "عميل" : "مورد"}',
                            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('صافي الرصيد: ${CurrencyFormatter.formatWithSymbol(netDebt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: netDebt >= 0 ? AppColors.success : AppColors.error,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Section: Debts owed TO us (ديون لنا) ──
          if (debtsOwedToUs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.call_made, color: AppColors.success, size: 20),
                  const SizedBox(width: 8),
                  Text('ديون لنا (مبالغ مستحقة لنا)',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
            ...debtsOwedToUs.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(isCustomer ? Icons.person : Icons.local_shipping, color: AppColors.success, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${item.currency}${item.phone != null ? " | ${item.phone}" : ""}',
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(CurrencyFormatter.format(item.balance),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                        Text('لنا',
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            )),
            const SizedBox(height: 16),
          ],

          // ── Section: Debts WE owe (ديون علينا) ──
          if (debtsWeOwe.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.call_received, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text('ديون علينا (مبالغ مستحقة علينا)',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                ],
              ),
            ),
            ...debtsWeOwe.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(isCustomer ? Icons.person : Icons.local_shipping, color: AppColors.error, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${item.currency}${item.phone != null ? " | ${item.phone}" : ""}',
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(CurrencyFormatter.format(item.balance),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                        Text('علينا',
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            )),
          ],

          // Empty state if no debts at all
          if (debtsOwedToUs.isEmpty && debtsWeOwe.isEmpty)
            _buildEmptyState(theme, isCustomer ? Icons.people : Icons.local_shipping,
                'لا توجد ${isCustomer ? "ديون عملاء" : "مديونيات موردين"}'),
        ],
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('نوع التقرير', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedReportType,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _reportTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() { _selectedReportType = value; _isLoading = true; });
                _loadReportData();
              }
            },
          ),
          const SizedBox(height: 12),
          Text('نطاق التاريخ', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: InkWell(
                onTap: _pickDateFrom,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(_dateFrom != null ? DateFormatter.formatDate(_dateFrom!) : 'من تاريخ', style: theme.textTheme.bodySmall?.copyWith(color: _dateFrom != null ? null : AppColors.textHint)),
                  ]),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: InkWell(
                onTap: _pickDateTo,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(_dateTo != null ? DateFormatter.formatDate(_dateTo!) : 'إلى تاريخ', style: theme.textTheme.bodySmall?.copyWith(color: _dateTo != null ? null : AppColors.textHint)),
                  ]),
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          Text('العملة', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() { _selectedCurrency = value; _isLoading = true; });
                _loadReportData();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme, bool isDark) {
    final cards = [
      _SummaryCardData(title: 'إجمالي الإيرادات', value: _totalRevenue, icon: Icons.trending_up, color: AppColors.success, lightBg: AppColors.successLight),
      _SummaryCardData(title: 'إجمالي المصروفات', value: _totalExpenses, icon: Icons.trending_down, color: AppColors.error, lightBg: AppColors.errorLight),
      _SummaryCardData(title: 'صافي الربح', value: _netProfit, icon: Icons.attach_money, color: AppColors.secondaryDark, lightBg: const Color(0xFFFFF8E1)),
      _SummaryCardData(title: 'عدد الفواتير', value: _invoiceCount.toDouble(), icon: Icons.receipt, color: AppColors.info, lightBg: AppColors.infoLight, isCount: true),
    ];
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _SummaryCard(card: cards[index], isDark: isDark),
      ),
    );
  }

  Widget _buildTopProductsSection(ThemeData theme, bool isDark) {
    if (_topProducts.isEmpty) return const SizedBox.shrink();
    final maxQuantity = _topProducts.first.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المنتجات الأكثر مبيعاً', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
            child: Column(
              children: _topProducts.asMap().entries.map((entry) {
                final product = entry.value;
                final progress = maxQuantity == 0 ? 0.0 : product.quantity / maxQuantity;
                return _TopProductTile(rank: entry.key + 1, product: product, progress: progress, isDark: isDark, isLast: entry.key == _topProducts.length - 1);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentInvoicesSection(ThemeData theme, bool isDark) {
    if (_recentInvoices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('آخر الفواتير', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._recentInvoices.take(10).map((invoice) => _RecentInvoiceCard(invoice: invoice, isDark: isDark)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  ACCOUNTS WITHOUT MOVEMENTS (حسابات بدون حركة)
  // ══════════════════════════════════════════════════════════════
  Widget _buildAccountsWithoutMovementsReport(ThemeData theme, bool isDark) {
    if (_accountsWithoutMovements.isEmpty) {
      return _buildEmptyState(theme, Icons.account_balance, 'جميع الحسابات لديها حركات');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.warning.withValues(alpha: 0.08),
                AppColors.secondary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.account_balance, size: 36, color: AppColors.warning),
                const SizedBox(height: 8),
                Text('حسابات بدون حركة',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${_accountsWithoutMovements.length} حساب',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.warning)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // قائمة الحسابات
          ..._accountsWithoutMovements.map((account) {
            final accountType = account['account_type'] as String? ?? '';
            String typeLabel;
            Color typeColor;
            switch (accountType) {
              case 'ASSET':
                typeLabel = 'أصول';
                typeColor = AppColors.primary;
                break;
              case 'LIABILITY':
                typeLabel = 'خصوم';
                typeColor = AppColors.error;
                break;
              case 'COST':
                typeLabel = 'تكاليف';
                typeColor = AppColors.warning;
                break;
              case 'REVENUE':
                typeLabel = 'إيرادات';
                typeColor = AppColors.success;
                break;
              case 'EXPENSE':
                typeLabel = 'مصاريف';
                typeColor = const Color(0xFF9C27B0);
                break;
              default:
                typeLabel = accountType;
                typeColor = AppColors.textSecondary;
            }
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_balance, color: typeColor, size: 20),
                ),
                title: Text(
                  account['name_ar'] as String? ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${account['account_code'] ?? ''} | ${account['currency'] ?? 'YER'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: typeColor,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  INVOICE PROFIT REPORT (ربح الفواتير)
  // ══════════════════════════════════════════════════════════════
  Widget _buildInvoiceProfitReport(ThemeData theme, bool isDark) {
    if (_invoiceProfitItems.isEmpty) {
      return _buildEmptyState(theme, Icons.trending_up, 'لا توجد بيانات أرباح');
    }
    final totalProfit = _invoiceProfitItems.fold(0.0,
        (s, item) => s + ((item['profit'] as num?)?.toDouble() ?? 0.0));
    final totalCost = _invoiceProfitItems.fold(0.0,
        (s, item) => s + ((item['cost_total'] as num?)?.toDouble() ?? 0.0));
    final totalRevenue = _invoiceProfitItems.fold(0.0,
        (s, item) => s + ((item['sale_total'] as num?)?.toDouble() ?? 0.0));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                (totalProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.08),
                (totalProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.03),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(totalProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                    size: 36, color: totalProfit >= 0 ? AppColors.success : AppColors.error),
                const SizedBox(height: 8),
                Text('إجمالي الربح',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.formatWithSymbol(totalProfit),
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: totalProfit >= 0 ? AppColors.success : AppColors.error)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text('إجمالي المبيعات', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                        Text(CurrencyFormatter.formatCompactWithSymbol(totalRevenue),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                      ],
                    ),
                    Container(width: 1, height: 30, color: AppColors.divider),
                    Column(
                      children: [
                        Text('إجمالي التكلفة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                        Text(CurrencyFormatter.formatCompactWithSymbol(totalCost),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // قائمة الفواتير
          ..._invoiceProfitItems.map((item) {
            final profit = (item['profit'] as num?)?.toDouble() ?? 0.0;
            final saleTotal = (item['sale_total'] as num?)?.toDouble() ?? 0.0;
            final costTotal = (item['cost_total'] as num?)?.toDouble() ?? 0.0;
            final invoiceType = item['type'] as String? ?? '';
            final isSale = invoiceType == 'sale' || invoiceType == 'pos';
            final profitPercent = saleTotal > 0 ? (profit / saleTotal * 100) : 0.0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: (isSale ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isSale ? Icons.receipt_long_outlined : Icons.shopping_cart_outlined,
                            color: isSale ? AppColors.success : AppColors.error, size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['entity_name'] as String? ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '#${(item['invoice_id'] as String?)?.substring(0, (item['invoice_id'] as String).length > 10 ? 10 : (item['invoice_id'] as String).length) ?? ''}',
                                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(profit),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: profit >= 0 ? AppColors.success : AppColors.error,
                              ),
                            ),
                            Text(
                              '${profitPercent.toStringAsFixed(1)}%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: profit >= 0 ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text('المبيعات: ${CurrencyFormatter.format(saleTotal)}',
                              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success)),
                        ),
                        Expanded(
                          child: Text('التكلفة: ${CurrencyFormatter.format(costTotal)}',
                              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  INVENTORY MOVEMENT REPORT (حركة المخزون)
  // ══════════════════════════════════════════════════════════════
  Widget _buildInventoryMovementReport(ThemeData theme, bool isDark) {
    if (_inventoryMovementItems.isEmpty) {
      return _buildEmptyState(theme, Icons.inventory, 'لا توجد حركات مخزون');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.info.withValues(alpha: 0.08),
                AppColors.primary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.inventory, size: 36, color: AppColors.info),
                const SizedBox(height: 8),
                Text('حركة المخزون',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${_inventoryMovementItems.length} منتج',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.info)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // قائمة المنتجات
          ..._inventoryMovementItems.map((item) {
            final qtyIn = (item['qty_in'] as num?)?.toDouble() ?? 0.0;
            final qtyOut = (item['qty_out'] as num?)?.toDouble() ?? 0.0;
            final currentStock = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
            final totalCost = (item['total_cost'] as num?)?.toDouble() ?? 0.0;
            final totalRevenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.inventory_2, color: AppColors.info, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name_ar'] as String? ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${item['item_code'] ?? ''} | المخزون: ${currentStock.toStringAsFixed(currentStock == currentStock.roundToDouble() ? 0 : 1)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.south_east, color: AppColors.success, size: 16),
                                Text('وارد',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.success, fontWeight: FontWeight.w700)),
                                Text(qtyIn.toStringAsFixed(qtyIn == qtyIn.roundToDouble() ? 0 : 1),
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text(CurrencyFormatter.formatCompactWithSymbol(totalCost),
                                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.north_west, color: AppColors.error, size: 16),
                                Text('صادر',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.error, fontWeight: FontWeight.w700)),
                                Text(qtyOut.toStringAsFixed(qtyOut == qtyOut.roundToDouble() ? 0 : 1),
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text(CurrencyFormatter.formatCompactWithSymbol(totalRevenue),
                                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  INVENTORY COST REPORT (تكلفة المخزون)
  // ══════════════════════════════════════════════════════════════
  Widget _buildInventoryCostReport(ThemeData theme, bool isDark) {
    if (_inventoryCostItems.isEmpty) {
      return _buildEmptyState(theme, Icons.attach_money, 'لا توجد أصناف في المخزون');
    }
    final totalCostValue = _inventoryCostItems.fold(0.0,
        (s, item) => s + ((item['stock_cost_value'] as num?)?.toDouble() ?? 0.0));
    final totalSellValue = _inventoryCostItems.fold(0.0,
        (s, item) => s + ((item['stock_sell_value'] as num?)?.toDouble() ?? 0.0));
    final potentialProfit = totalSellValue - totalCostValue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.secondary.withValues(alpha: 0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.attach_money, size: 36, color: AppColors.primary),
                const SizedBox(height: 8),
                Text('تكلفة المخزون',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.formatWithSymbol(totalCostValue),
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text('قيمة البيع', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                        Text(CurrencyFormatter.formatCompactWithSymbol(totalSellValue),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700, color: AppColors.success)),
                      ],
                    ),
                    Container(width: 1, height: 30, color: AppColors.divider),
                    Column(
                      children: [
                        Text('ربح محتمل', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                        Text(CurrencyFormatter.formatCompactWithSymbol(potentialProfit),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: potentialProfit >= 0 ? AppColors.success : AppColors.error)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // قائمة المنتجات
          ..._inventoryCostItems.map((item) {
            final stock = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
            final costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
            final sellPrice = (item['sell_price'] as num?)?.toDouble() ?? 0.0;
            final costValue = (item['stock_cost_value'] as num?)?.toDouble() ?? 0.0;
            final sellValue = (item['stock_sell_value'] as num?)?.toDouble() ?? 0.0;
            final itemProfit = sellValue - costValue;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.inventory_2, color: AppColors.primary, size: 20),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['name_ar'] as String? ?? '',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  'الكمية: ${stock.toStringAsFixed(stock == stock.roundToDouble() ? 0 : 1)} | تكلفة: ${CurrencyFormatter.format(costPrice)} | بيع: ${CurrencyFormatter.format(sellPrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(CurrencyFormatter.format(costValue),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.primary)),
                    Text(
                      'ربح: ${CurrencyFormatter.format(itemProfit)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: itemProfit >= 0 ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  DAILY OPERATIONS LINK (العمليات اليومية)
  // ══════════════════════════════════════════════════════════════
  Widget _buildDailyOperationsLink(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.today, size: 80, color: AppColors.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text(
            'العمليات اليومية',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'عرض جميع الحركات المالية ليوم محدد في مكان واحد\nفواتير المبيعات والمشتريات والسندات والمصروفات والتحويلات',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(AppConstants.dailyOperations);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح شاشة العمليات اليومية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  DATA CLASSES
// ═══════════════════════════════════════════════════════════════════

class _SummaryCardData {
  const _SummaryCardData({required this.title, required this.value, required this.icon, required this.color, required this.lightBg, this.isCount = false});
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  final Color lightBg;
  final bool isCount;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.card, required this.isDark});
  final _SummaryCardData card;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? card.color.withValues(alpha: 0.15) : card.lightBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: card.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, color: card.color, size: 24),
          const SizedBox(height: 10),
          Text(
            card.isCount ? card.value.toStringAsFixed(0) : CurrencyFormatter.formatCompactWithSymbol(card.value),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: card.color),
          ),
          const SizedBox(height: 4),
          Text(
            card.title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TopProduct {
  const _TopProduct({required this.name, required this.quantity, required this.revenue});
  final String name;
  final int quantity;
  final double revenue;
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({required this.rank, required this.product, required this.progress, required this.isDark, required this.isLast});
  final int rank;
  final _TopProduct product;
  final double progress;
  final bool isDark;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: rank <= 3 ? AppColors.secondary.withValues(alpha: 0.2) : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$rank', style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? AppColors.secondaryDark : AppColors.textSecondary,
                  )),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${product.quantity} قطعة', style: theme.textTheme.labelSmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textHint)),
                  ],
                ),
              ),
              Text(CurrencyFormatter.format(product.revenue), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          if (!isLast) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(
                  rank == 1 ? AppColors.primary : rank <= 3 ? AppColors.secondary : AppColors.textHint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentInvoice {
  const _RecentInvoice({required this.id, required this.title, required this.subtitle, required this.date, required this.total, required this.currency, required this.icon, required this.color});
  final String id;
  final String title;
  final String subtitle;
  final String date;
  final double total;
  final String currency;
  final IconData icon;
  final Color color;
}

class _RecentInvoiceCard extends StatelessWidget {
  const _RecentInvoiceCard({required this.invoice, required this.isDark});
  final _RecentInvoice invoice;
  final bool isDark;

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: invoice.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(invoice.icon, color: invoice.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(invoice.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.format(invoice.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: invoice.color)),
                Text(_formatDate(invoice.date), style: theme.textTheme.labelSmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textHint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMovement {
  const _AccountMovement({required this.date, required this.description, required this.debit, required this.credit, required this.balance});
  final String date;
  final String description;
  final double debit;
  final double credit;
  final double balance;
}

class _AllAccountMovement {
  const _AllAccountMovement({required this.date, required this.accountName, required this.accountCode, required this.currency, required this.description, required this.debit, required this.credit});
  final String date;
  final String accountName;
  final String accountCode;
  final String currency;
  final String description;
  final double debit;
  final double credit;
}

class _TrialBalanceItem {
  const _TrialBalanceItem({required this.accountId, required this.accountName, required this.accountCode, required this.accountType, required this.currency, required this.debit, required this.credit});
  final int accountId;
  final String accountName;
  final String accountCode;
  final String accountType;
  final String currency;
  final double debit;
  final double credit;
}

class _DebtItem {
  const _DebtItem({required this.name, required this.balance, required this.balanceType, required this.currency, this.phone});
  final String name;
  final double balance;
  final String balanceType;
  final String currency;
  final String? phone;
}

class _CashBoxMovement {
  const _CashBoxMovement({required this.id, required this.name, required this.type, required this.balance, required this.balanceType, required this.currency, required this.salesTotal, required this.salesCount, required this.purchaseTotal, required this.purchaseCount, this.transfersInTotal = 0, this.transfersInCount = 0, this.transfersOutTotal = 0, this.transfersOutCount = 0, this.exchangesInTotal = 0, this.exchangesInCount = 0, this.exchangesOutTotal = 0, this.exchangesOutCount = 0});
  final int id;
  final String name;
  final String type;
  final double balance;
  final String balanceType;
  final String currency;
  final double salesTotal;
  final int salesCount;
  final double purchaseTotal;
  final int purchaseCount;
  final double transfersInTotal;
  final int transfersInCount;
  final double transfersOutTotal;
  final int transfersOutCount;
  final double exchangesInTotal;
  final int exchangesInCount;
  final double exchangesOutTotal;
  final int exchangesOutCount;
}

class _InventoryItem {
  const _InventoryItem({required this.id, required this.name, this.barcode, this.itemCode, required this.currentStock, required this.costPrice, required this.sellPrice, required this.minStock, this.warehouseName, this.categoryName, required this.isLowStock, required this.isOutOfStock});
  final int id;
  final String name;
  final String? barcode;
  final String? itemCode;
  final double currentStock;
  final double costPrice;
  final double sellPrice;
  final double minStock;
  final String? warehouseName;
  final String? categoryName;
  final bool isLowStock;
  final bool isOutOfStock;
}
