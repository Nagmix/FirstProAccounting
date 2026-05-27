import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../data/datasources/database_helper.dart';

// ═══════════════════════════════════════════════════════════════════
//  Reports Screen – Professional Redesign
//  No charts, no auto-loading. User selects report → sets filters →
//  presses "عرض التقرير" to query. Excel export per report.
// ═══════════════════════════════════════════════════════════════════

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

// ── Report Group ────────────────────────────────────────────────

class _ReportGroup {
  final String name;
  final IconData icon;
  final Color color;
  final List<_ReportItem> items;
  bool isExpanded;

  _ReportGroup({
    required this.name,
    required this.icon,
    required this.color,
    required this.items,
    this.isExpanded = false,
  });
}

class _ReportItem {
  final String name;
  final IconData icon;
  final Color color;
  final String key;

  const _ReportItem({
    required this.name,
    required this.icon,
    required this.color,
    required this.key,
  });
}

// ── State ───────────────────────────────────────────────────────

class _ReportsScreenState extends State<ReportsScreen> {
  late List<_ReportGroup> _groups;
  String? _selectedReportKey;
  bool _isLoading = false;
  bool _hasData = false;

  // Filters
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _selectedCurrency = 'الكل';
  int? _selectedAccountId;
  int? _selectedCustomerId;
  int? _selectedSupplierId;
  int? _selectedCashBoxId;
  int? _selectedWarehouseId;
  int? _selectedCategoryId;
  String _selectedAccountType = 'الكل';

  // Report data
  List<Map<String, dynamic>> _reportRows = [];
  Map<String, double> _reportTotals = {};

  static const _currencyOptions = ['الكل', 'ر.ي', 'ر.س', r'$'];
  static const _accountTypes = [
    MapEntry('الكل', 'الكل'),
    MapEntry('أصول', 'ASSET'),
    MapEntry('خصوم', 'LIABILITY'),
    MapEntry('تكاليف', 'COST'),
    MapEntry('إيرادات', 'REVENUE'),
    MapEntry('مصاريف', 'EXPENSE'),
  ];

  @override
  void initState() {
    super.initState();
    _initGroups();
  }

  void _initGroups() {
    _groups = [
      _ReportGroup(
        name: 'المبيعات والمشتريات',
        icon: Icons.swap_horiz,
        color: AppColors.primary,
        isExpanded: true,
        items: [
          const _ReportItem(name: 'تقرير المبيعات', icon: Icons.trending_up, color: AppColors.success, key: 'sales'),
          const _ReportItem(name: 'تقرير المشتريات', icon: Icons.shopping_cart, color: AppColors.error, key: 'purchases'),
          const _ReportItem(name: 'مرتجعات المبيعات', icon: Icons.undo, color: AppColors.warning, key: 'sales_returns'),
          const _ReportItem(name: 'مرتجعات المشتريات', icon: Icons.undo, color: AppColors.warning, key: 'purchase_returns'),
          const _ReportItem(name: 'الأرباح والخسائر', icon: Icons.assessment, color: AppColors.primary, key: 'profit_loss'),
          const _ReportItem(name: 'ربح الفواتير', icon: Icons.receipt_long, color: AppColors.secondary, key: 'invoice_profit'),
          const _ReportItem(name: 'المبيعات حسب المنتج', icon: Icons.inventory, color: AppColors.info, key: 'sales_by_product'),
          const _ReportItem(name: 'المبيعات حسب العميل', icon: Icons.people, color: AppColors.success, key: 'sales_by_customer'),
        ],
      ),
      _ReportGroup(
        name: 'المحاسبة والمالية',
        icon: Icons.account_balance,
        color: AppColors.info,
        items: [
          const _ReportItem(name: 'حركة حساب', icon: Icons.swap_horiz, color: AppColors.info, key: 'account_movement'),
          const _ReportItem(name: 'حركة جميع الحسابات', icon: Icons.view_list, color: AppColors.info, key: 'all_account_movement'),
          const _ReportItem(name: 'ميزان المراجعة', icon: Icons.balance, color: AppColors.primary, key: 'trial_balance'),
          const _ReportItem(name: 'حركة الصندوق', icon: Icons.account_balance_wallet, color: AppColors.success, key: 'cash_box'),
          const _ReportItem(name: 'حسابات بدون حركة', icon: Icons.block, color: AppColors.textHint, key: 'accounts_no_movement'),
          const _ReportItem(name: 'كشف حساب عميل', icon: Icons.person, color: AppColors.success, key: 'customer_statement'),
          const _ReportItem(name: 'كشف حساب مورد', icon: Icons.local_shipping, color: AppColors.error, key: 'supplier_statement'),
          const _ReportItem(name: 'تقرير المصروفات', icon: Icons.money_off, color: AppColors.warning, key: 'expenses'),
        ],
      ),
      _ReportGroup(
        name: 'المخزون',
        icon: Icons.inventory_2,
        color: AppColors.success,
        items: [
          const _ReportItem(name: 'تقرير المخزون', icon: Icons.inventory_2, color: AppColors.success, key: 'inventory'),
          const _ReportItem(name: 'حركة المخزون', icon: Icons.swap_vert, color: AppColors.primary, key: 'inventory_movement'),
          const _ReportItem(name: 'تكلفة المخزون', icon: Icons.attach_money, color: AppColors.warning, key: 'inventory_cost'),
          const _ReportItem(name: 'الأصناف المنتهية', icon: Icons.warning, color: AppColors.error, key: 'out_of_stock'),
          const _ReportItem(name: 'الأصناف قاربت على النفاد', icon: Icons.notification_important, color: AppColors.warning, key: 'low_stock'),
        ],
      ),
      _ReportGroup(
        name: 'الديون',
        icon: Icons.people,
        color: AppColors.warning,
        items: [
          const _ReportItem(name: 'ديون العملاء', icon: Icons.people, color: AppColors.warning, key: 'customer_debts'),
          const _ReportItem(name: 'ديون الموردين', icon: Icons.local_shipping, color: AppColors.error, key: 'supplier_debts'),
        ],
      ),
      _ReportGroup(
        name: 'العمليات',
        icon: Icons.settings,
        color: AppColors.secondary,
        items: [
          const _ReportItem(name: 'تحويلات الصناديق', icon: Icons.swap_horiz, color: AppColors.info, key: 'cash_transfers'),
          const _ReportItem(name: 'صرافة العملات', icon: Icons.currency_exchange, color: AppColors.secondary, key: 'currency_exchanges'),
          const _ReportItem(name: 'السندات', icon: Icons.assignment, color: AppColors.primary, key: 'vouchers'),
          const _ReportItem(name: 'الورديات', icon: Icons.access_time, color: AppColors.info, key: 'shifts'),
        ],
      ),
    ];
  }

  // ══════════════════════════════════════════════════════════════
  //  Helpers
  // ══════════════════════════════════════════════════════════════

  String? _currencyCode() {
    switch (_selectedCurrency) {
      case 'ر.ي': return 'YER';
      case 'ر.س': return 'SAR';
      case r'$': return 'USD';
      default: return null;
    }
  }

  String _dateFilter({String column = 'created_at'}) {
    String f = '';
    if (_dateFrom != null) f += ' AND $column >= ?';
    if (_dateTo != null) f += ' AND $column < ?';
    return f;
  }

  List<dynamic> _dateArgs() {
    final args = <dynamic>[];
    if (_dateFrom != null) args.add(_dateFrom!.toIso8601String());
    if (_dateTo != null) args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String());
    return args;
  }

  String _currencyFilter({String column = 'currency'}) {
    return _currencyCode() != null ? ' AND $column = ?' : '';
  }

  List<dynamic> _currencyArgs() {
    return _currencyCode() != null ? [_currencyCode()!] : [];
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _fmtMoney(double v) => CurrencyFormatter.format(v);

  String _accountTypeAr(String type) {
    switch (type) {
      case 'ASSET': return 'أصول';
      case 'LIABILITY': return 'خصوم';
      case 'COST': return 'تكاليف';
      case 'REVENUE': return 'إيرادات';
      case 'EXPENSE': return 'مصاريف';
      default: return type;
    }
  }

  String _invoiceTypeAr(String type, {int? isReturn}) {
    final isRet = isReturn == 1;
    switch (type) {
      case 'sale': case 'pos': return isRet ? 'مرتجع مبيعات' : 'مبيعات';
      case 'purchase': return isRet ? 'مرتجع مشتريات' : 'مشتريات';
      default: return type;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Which filters are needed per report?
  // ══════════════════════════════════════════════════════════════

  bool _needsDateFilter() {
    if (_selectedReportKey == null) return false;
    const noDate = {'accounts_no_movement', 'inventory', 'out_of_stock', 'low_stock', 'inventory_cost'};
    return !noDate.contains(_selectedReportKey);
  }

  bool _needsCurrencyFilter() {
    if (_selectedReportKey == null) return false;
    const noCurrency = {'accounts_no_movement', 'inventory_movement', 'cash_transfers', 'currency_exchanges', 'shifts'};
    return !noCurrency.contains(_selectedReportKey);
  }

  bool _needsAccountFilter() {
    return _selectedReportKey == 'account_movement';
  }

  bool _needsCustomerFilter() {
    return _selectedReportKey == 'customer_statement';
  }

  bool _needsSupplierFilter() {
    return _selectedReportKey == 'supplier_statement';
  }

  bool _needsCashBoxFilter() {
    return _selectedReportKey == 'cash_box';
  }

  bool _needsWarehouseFilter() {
    return const {'inventory', 'out_of_stock', 'low_stock'}.contains(_selectedReportKey);
  }

  bool _needsCategoryFilter() {
    return const {'inventory', 'out_of_stock', 'low_stock', 'sales_by_product'}.contains(_selectedReportKey);
  }

  bool _needsAccountTypeFilter() {
    return const {'trial_balance', 'all_account_movement'}.contains(_selectedReportKey);
  }

  // ══════════════════════════════════════════════════════════════
  //  Date Pickers
  // ══════════════════════════════════════════════════════════════

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateFrom = picked);
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateTo = picked);
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedCurrency = 'الكل';
      _selectedAccountId = null;
      _selectedCustomerId = null;
      _selectedSupplierId = null;
      _selectedCashBoxId = null;
      _selectedWarehouseId = null;
      _selectedCategoryId = null;
      _selectedAccountType = 'الكل';
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Load Report Data
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadReport() async {
    if (_selectedReportKey == null) return;

    // Validate required filters
    if (_selectedReportKey == 'account_movement' && _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الحساب أولاً'), backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_selectedReportKey == 'customer_statement' && _selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار العميل أولاً'), backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_selectedReportKey == 'supplier_statement' && _selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المورد أولاً'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() { _isLoading = true; _hasData = false; });
    try {
      final db = DatabaseHelper();
      _reportRows = [];
      _reportTotals = {};

      switch (_selectedReportKey) {
        // ── SALES & PURCHASES ──
        case 'sales':
          await _loadSalesReport(db, typeFilter: "type IN ('sale','pos') AND is_return=0");
        case 'purchases':
          await _loadSalesReport(db, typeFilter: "type='purchase' AND is_return=0");
        case 'sales_returns':
          await _loadSalesReport(db, typeFilter: "type IN ('sale','pos') AND is_return=1");
        case 'purchase_returns':
          await _loadSalesReport(db, typeFilter: "type='purchase' AND is_return=1");
        case 'profit_loss':
          await _loadProfitLossReport(db);
        case 'invoice_profit':
          await _loadInvoiceProfitReport(db);
        case 'sales_by_product':
          await _loadSalesByProductReport(db);
        case 'sales_by_customer':
          await _loadSalesByCustomerReport(db);

        // ── ACCOUNTING ──
        case 'account_movement':
          await _loadAccountMovementReport(db);
        case 'all_account_movement':
          await _loadAllAccountMovementReport(db);
        case 'trial_balance':
          await _loadTrialBalanceReport(db);
        case 'cash_box':
          await _loadCashBoxReport(db);
        case 'accounts_no_movement':
          await _loadAccountsWithoutMovementReport(db);
        case 'customer_statement':
          await _loadCustomerStatementReport(db);
        case 'supplier_statement':
          await _loadSupplierStatementReport(db);
        case 'expenses':
          await _loadExpensesReport(db);

        // ── INVENTORY ──
        case 'inventory':
          await _loadInventoryReport(db);
        case 'inventory_movement':
          await _loadInventoryMovementReport(db);
        case 'inventory_cost':
          await _loadInventoryCostReport(db);
        case 'out_of_stock':
          await _loadOutOfStockReport(db);
        case 'low_stock':
          await _loadLowStockReport(db);

        // ── DEBTS ──
        case 'customer_debts':
          await _loadDebtReport(db, isCustomer: true);
        case 'supplier_debts':
          await _loadDebtReport(db, isCustomer: false);

        // ── OPERATIONS ──
        case 'cash_transfers':
          await _loadCashTransfersReport(db);
        case 'currency_exchanges':
          await _loadCurrencyExchangesReport(db);
        case 'vouchers':
          await _loadVouchersReport(db);
        case 'shifts':
          await _loadShiftsReport(db);
      }

      _hasData = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقرير: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ══════════════════════════════════════════════════════════════
  //  Individual Report Queries
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadSalesReport(DatabaseHelper db, {required String typeFilter}) async {
    final database = await db.database;
    final args = <dynamic>[];
    String whereClause = typeFilter;

    if (_dateFrom != null) { whereClause += ' AND created_at >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { whereClause += ' AND created_at < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
    if (_currencyCode() != null) { whereClause += ' AND currency = ?'; args.add(_currencyCode()!); }
    if (_selectedCashBoxId != null) { whereClause += ' AND cash_box_id = ?'; args.add(_selectedCashBoxId!); }

    final results = await database.rawQuery(
      "SELECT i.id, i.type, i.is_return, i.total, i.subtotal, i.discount_amount, i.paid_amount, "
      "i.remaining, i.currency, i.created_at, i.cash_box_id, "
      "COALESCE(c.name, s.name, 'بدون') AS entity_name "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id=c.id "
      "LEFT JOIN suppliers s ON i.supplier_id=s.id "
      "WHERE $whereClause ORDER BY i.created_at DESC",
      args,
    );

    double totalAmount = 0, totalPaid = 0, totalRemaining = 0;
    _reportRows = results.map((r) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0;
      final remaining = (r['remaining'] as num?)?.toDouble() ?? 0;
      totalAmount += total;
      totalPaid += paid;
      totalRemaining += remaining;
      return {
        'رقم الفاتورة': (r['id'] as String?)?.substring(0, (r['id'] as String).length.clamp(1, 12)) ?? '',
        'النوع': _invoiceTypeAr(r['type'] as String? ?? '', isReturn: r['is_return'] as int?),
        'الجهة': r['entity_name'] as String? ?? '',
        'الإجمالي': total,
        'المدفوع': paid,
        'المتبقي': remaining,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['created_at'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'الإجمالي': totalAmount, 'المدفوع': totalPaid, 'المتبقي': totalRemaining, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadProfitLossReport(DatabaseHelper db) async {
    final database = await db.database;
    final allArgs = [..._dateArgs(), ..._currencyArgs()];
    final df = _dateFilter();
    final cf = _currencyFilter();

    final revRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type IN ('sale','pos') AND is_return=0$df$cf", allArgs);
    final revenue = (revRes.first['t'] as num?)?.toDouble() ?? 0;

    final purRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type='purchase' AND is_return=0$df$cf", allArgs);
    final purchases = (purRes.first['t'] as num?)?.toDouble() ?? 0;

    final retSaleRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type IN ('sale','pos') AND is_return=1$df$cf", allArgs);
    final salesReturns = (retSaleRes.first['t'] as num?)?.toDouble() ?? 0;

    final retPurRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type='purchase' AND is_return=1$df$cf", allArgs);
    final purchaseReturns = (retPurRes.first['t'] as num?)?.toDouble() ?? 0;

    final expArgs = <dynamic>[];
    if (_dateFrom != null) expArgs.add(_dateFrom!.toIso8601String());
    if (_dateTo != null) expArgs.add(_dateTo!.add(const Duration(days: 1)).toIso8601String());
    expArgs.addAll(_currencyArgs());
    final expRes = await database.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE 1=1${_dateFilter(column: 'expense_date')}$cf", expArgs);
    final expenses = (expRes.first['t'] as num?)?.toDouble() ?? 0;

    final netSales = revenue - salesReturns;
    final netPurchases = purchases - purchaseReturns;
    final grossProfit = netSales - netPurchases;
    final netProfit = grossProfit - expenses;

    _reportRows = [
      {'البند': 'إجمالي المبيعات', 'المبلغ': revenue, 'ملاحظة': 'فواتير البيع'},
      {'البند': 'مرتجعات المبيعات', 'المبلغ': -salesReturns, 'ملاحظة': 'فواتير المرتجع'},
      {'البند': 'صافي المبيعات', 'المبلغ': netSales, 'ملاحظة': ''},
      {'البند': 'إجمالي المشتريات', 'المبلغ': purchases, 'ملاحظة': 'فواتير الشراء'},
      {'البند': 'مرتجعات المشتريات', 'المبلغ': -purchaseReturns, 'ملاحظة': ''},
      {'البند': 'صافي المشتريات', 'المبلغ': netPurchases, 'ملاحظة': ''},
      {'البند': 'مجمل الربح', 'المبلغ': grossProfit, 'ملاحظة': 'صافي المبيعات - صافي المشتريات'},
      {'البند': 'المصاريف التشغيلية', 'المبلغ': -expenses, 'ملاحظة': ''},
      {'البند': 'صافي الربح', 'المبلغ': netProfit, 'ملاحظة': 'مجمل الربح - المصاريف'},
    ];
    _reportTotals = {'صافي المبيعات': netSales, 'صافي المشتريات': netPurchases, 'صافي الربح': netProfit};
  }

  Future<void> _loadInvoiceProfitReport(DatabaseHelper db) async {
    final items = await db.getInvoiceProfitReport(startDate: _dateFrom, endDate: _dateTo);
    double totalProfit = 0, totalRevenue = 0, totalCost = 0;
    _reportRows = items.map((item) {
      final profit = (item['profit'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toDouble() ?? 0;
      final cost = (item['total_cost'] as num?)?.toDouble() ?? 0;
      totalProfit += profit;
      totalRevenue += total;
      totalCost += cost;
      return {
        'رقم الفاتورة': (item['invoice_id']?.toString() ?? '').substring(0, (item['invoice_id']?.toString().length ?? 1).clamp(1, 12)),
        'إجمالي الفاتورة': total,
        'تكلفة الفاتورة': cost,
        'الربح': profit,
        'هامش الربح': total > 0 ? (profit / total * 100) : 0.0,
        'التاريخ': item['created_at'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'إجمالي الإيرادات': totalRevenue, 'إجمالي التكلفة': totalCost, 'إجمالي الربح': totalProfit, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadSalesByProductReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = <dynamic>[];
    String dateF = '';
    if (_dateFrom != null) { dateF += ' AND i.created_at >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { dateF += ' AND i.created_at < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
    String curF = '';
    if (_currencyCode() != null) { curF = ' AND i.currency = ?'; args.add(_currencyCode()!); }

    String catJoin = '';
    String catFilter = '';
    if (_selectedCategoryId != null) {
      catJoin = ' INNER JOIN products p2 ON ii.product_id=p2.id';
      catFilter = ' AND p2.category_id=?';
      args.add(_selectedCategoryId!);
    }

    final results = await database.rawQuery(
      "SELECT ii.product_name, SUM(ii.quantity) AS qty, SUM(ii.total_price) AS revenue, "
      "COUNT(DISTINCT ii.invoice_id) AS inv_count "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id=i.id $catJoin "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0$dateF$curF$catFilter "
      "GROUP BY ii.product_id ORDER BY revenue DESC",
      args,
    );
    double totalRevenue = 0;
    int totalQty = 0;
    _reportRows = results.map((r) {
      final rev = (r['revenue'] as num?)?.toDouble() ?? 0;
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      totalRevenue += rev;
      totalQty += qty.toInt();
      return {
        'المنتج': r['product_name'] as String? ?? '',
        'الكمية المباعة': qty,
        'إجمالي المبيعات': rev,
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    _reportTotals = {'إجمالي المبيعات': totalRevenue, 'إجمالي الكمية': totalQty.toDouble(), 'عدد الأصناف': _reportRows.length.toDouble()};
  }

  Future<void> _loadSalesByCustomerReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = <dynamic>[];
    String dateF = '';
    if (_dateFrom != null) { dateF += ' AND i.created_at >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { dateF += ' AND i.created_at < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
    String curF = '';
    if (_currencyCode() != null) { curF = ' AND i.currency = ?'; args.add(_currencyCode()!); }

    final results = await database.rawQuery(
      "SELECT COALESCE(c.name, 'بدون عميل') AS customer_name, c.currency, "
      "COUNT(i.id) AS inv_count, COALESCE(SUM(i.total),0) AS total_sales, "
      "COALESCE(SUM(i.paid_amount),0) AS total_paid, COALESCE(SUM(i.remaining),0) AS total_remaining "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id=c.id "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0$dateF$curF "
      "GROUP BY i.customer_id ORDER BY total_sales DESC",
      args,
    );
    double totalSales = 0;
    _reportRows = results.map((r) {
      final sales = (r['total_sales'] as num?)?.toDouble() ?? 0;
      totalSales += sales;
      return {
        'العميل': r['customer_name'] as String,
        'العملة': r['currency'] as String? ?? 'YER',
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
        'إجمالي المبيعات': sales,
        'المدفوع': (r['total_paid'] as num?)?.toDouble() ?? 0,
        'المتبقي': (r['total_remaining'] as num?)?.toDouble() ?? 0,
      };
    }).toList();
    _reportTotals = {'إجمالي المبيعات': totalSales, 'عدد العملاء': _reportRows.length.toDouble()};
  }

  Future<void> _loadAccountMovementReport(DatabaseHelper db) async {
    if (_selectedAccountId == null) return;
    final transactions = await db.getAccountTransactions(_selectedAccountId!);
    double running = 0;
    double totalDebit = 0, totalCredit = 0;
    _reportRows = [];
    for (final tx in transactions) {
      final debit = (tx['debit'] as num?)?.toDouble() ?? 0;
      final credit = (tx['credit'] as num?)?.toDouble() ?? 0;
      running += (debit - credit);
      totalDebit += debit;
      totalCredit += credit;
      _reportRows.add({
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'مدين': debit,
        'دائن': credit,
        'الرصيد': running,
      });
    }
    _reportTotals = {'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadAllAccountMovementReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = [..._dateArgs()];
    String cf = '';
    if (_currencyCode() != null) { cf = ' AND a.currency = ?'; args.add(_currencyCode()!); }
    if (_selectedAccountType != 'الكل') {
      final typeCode = _accountTypes.firstWhere((e) => e.key == _selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
      if (typeCode != 'الكل') { cf += ' AND a.account_type = ?'; args.add(typeCode); }
    }
    final allTx = await database.rawQuery(
      "SELECT t.id, t.account_id, t.debit, t.credit, t.description, t.date, t.created_at, "
      "a.name_ar AS account_name, a.account_code, a.currency "
      "FROM transactions t LEFT JOIN accounts a ON t.account_id=a.id "
      "WHERE 1=1${_dateFilter(column: 't.created_at')}$cf "
      "ORDER BY t.date DESC, t.created_at DESC", args);
    double totalDebit = 0, totalCredit = 0;
    _reportRows = allTx.map((tx) {
      final debit = (tx['debit'] as num?)?.toDouble() ?? 0;
      final credit = (tx['credit'] as num?)?.toDouble() ?? 0;
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'كود الحساب': tx['account_code'] as String? ?? '',
        'اسم الحساب': tx['account_name'] as String? ?? 'غير معروف',
        'البيان': tx['description'] as String? ?? '',
        'مدين': debit,
        'دائن': credit,
        'العملة': tx['currency'] as String? ?? 'YER',
      };
    }).toList();
    _reportTotals = {'مدين': totalDebit, 'دائن': totalCredit, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadTrialBalanceReport(DatabaseHelper db) async {
    final accounts = await db.getAllAccounts();
    final cc = _currencyCode();
    double totalDebit = 0, totalCredit = 0;
    _reportRows = [];
    for (final account in accounts) {
      if (cc != null && account['currency'] != cc) continue;
      if (_selectedAccountType != 'الكل') {
        final typeCode = _accountTypes.firstWhere((e) => e.key == _selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
        if (typeCode != 'الكل' && account['account_type'] != typeCode) continue;
      }
      final accountId = account['id'] as int;
      final balance = await db.getAccountBalance(accountId);
      if (balance == 0.0) continue;
      final isDebit = balance > 0;
      final debit = isDebit ? balance.abs() : 0.0;
      final credit = isDebit ? 0.0 : balance.abs();
      totalDebit += debit;
      totalCredit += credit;
      _reportRows.add({
        'كود الحساب': account['account_code'] as String? ?? '',
        'اسم الحساب': account['name_ar'] as String? ?? '',
        'نوع الحساب': _accountTypeAr(account['account_type'] as String? ?? ''),
        'العملة': account['currency'] as String? ?? 'YER',
        'مدين': debit,
        'دائن': credit,
      });
    }
    _reportTotals = {'مدين': totalDebit, 'دائن': totalCredit, 'الفرق': (totalDebit - totalCredit).abs(), 'عدد الحسابات': _reportRows.length.toDouble()};
  }

  Future<void> _loadCashBoxReport(DatabaseHelper db) async {
    final database = await db.database;
    final cashBoxes = await db.getAllCashBoxes();
    final cc = _currencyCode();
    double totalBalance = 0;
    _reportRows = [];
    for (final cb in cashBoxes) {
      if (cc != null && cb['currency'] != cc) continue;
      if (_selectedCashBoxId != null && cb['id'] != _selectedCashBoxId) continue;
      final cbId = cb['id'] as int;
      final balance = (cb['balance'] as num?)?.toDouble() ?? 0;
      final isCredit = (cb['balance_type'] as String? ?? 'credit') == 'credit';
      final signedBalance = isCredit ? balance : -balance;
      totalBalance += signedBalance;

      final invRes = await database.rawQuery(
        "SELECT type, COALESCE(SUM(total),0) as total FROM invoices WHERE cash_box_id=? AND is_return=0${_dateFilter()} GROUP BY type",
        [cbId, ..._dateArgs()]);
      double salesTotal = 0, purchaseTotal = 0;
      for (final inv in invRes) {
        final t = inv['type'] as String? ?? '';
        final tot = (inv['total'] as num?)?.toDouble() ?? 0;
        if (t == 'sale' || t == 'pos') salesTotal = tot;
        else if (t == 'purchase') purchaseTotal = tot;
      }

      _reportRows.add({
        'الصندوق': cb['name'] as String? ?? '',
        'النوع': cb['type'] == 'bank' ? 'بنك' : 'صندوق',
        'العملة': cb['currency'] as String? ?? 'YER',
        'الرصيد': balance,
        'حالة الرصيد': isCredit ? 'له' : 'عليه',
        'المبيعات': salesTotal,
        'المشتريات': purchaseTotal,
      });
    }
    _reportTotals = {'إجمالي الأرصدة': totalBalance.abs(), 'عدد الصناديق': _reportRows.length.toDouble()};
  }

  Future<void> _loadAccountsWithoutMovementReport(DatabaseHelper db) async {
    final accounts = await db.getAccountsWithoutMovements();
    _reportRows = accounts.map((a) => {
      'كود الحساب': a['account_code'] as String? ?? '',
      'اسم الحساب': a['name_ar'] as String? ?? '',
      'نوع الحساب': _accountTypeAr(a['account_type'] as String? ?? ''),
      'العملة': a['currency'] as String? ?? 'YER',
    }).toList();
    _reportTotals = {'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadCustomerStatementReport(DatabaseHelper db) async {
    if (_selectedCustomerId == null) return;
    final database = await db.database;
    final args = <dynamic>[_selectedCustomerId!];
    String dateF = '';
    if (_dateFrom != null) { dateF += ' AND t.created_at >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { dateF += ' AND t.created_at < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }

    // Get customer's linked account(s)
    final customer = await db.getAllCustomers();
    final cust = customer.firstWhere((c) => c['id'] == _selectedCustomerId, orElse: () => <String, dynamic>{});
    final custName = cust['name'] as String? ?? '';
    final custCurrency = cust['currency'] as String? ?? 'YER';

    // Get account movements for the customer's linked account
    final acctRes = await database.rawQuery(
      "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1", [custName, custCurrency]);
    if (acctRes.isEmpty) {
      _reportRows = [];
      return;
    }
    final accountId = acctRes.first['id'] as int;
    final txArgs = <dynamic>[accountId, ...args.sublist(1)];
    final txs = await database.rawQuery(
      "SELECT t.date, t.description, t.debit, t.credit, t.created_at "
      "FROM transactions t WHERE t.account_id=?$dateF ORDER BY t.date ASC, t.created_at ASC",
      txArgs,
    );
    double running = 0, totalDebit = 0, totalCredit = 0;
    _reportRows = txs.map((tx) {
      final debit = (tx['debit'] as num?)?.toDouble() ?? 0;
      final credit = (tx['credit'] as num?)?.toDouble() ?? 0;
      running += (debit - credit);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'عليه (مدين)': debit,
        'له (دائن)': credit,
        'الرصيد': running,
      };
    }).toList();
    _reportTotals = {'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'العميل': 0};
  }

  Future<void> _loadSupplierStatementReport(DatabaseHelper db) async {
    if (_selectedSupplierId == null) return;
    final database = await db.database;
    final suppliers = await db.getAllSuppliers();
    final sup = suppliers.firstWhere((s) => s['id'] == _selectedSupplierId, orElse: () => <String, dynamic>{});
    final supName = sup['name'] as String? ?? '';
    final supCurrency = sup['currency'] as String? ?? 'YER';

    final acctRes = await database.rawQuery(
      "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1", [supName, supCurrency]);
    if (acctRes.isEmpty) { _reportRows = []; return; }

    final accountId = acctRes.first['id'] as int;
    final args = <dynamic>[accountId];
    String dateF = '';
    if (_dateFrom != null) { dateF += ' AND t.created_at >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { dateF += ' AND t.created_at < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }

    final txs = await database.rawQuery(
      "SELECT t.date, t.description, t.debit, t.credit, t.created_at "
      "FROM transactions t WHERE t.account_id=?$dateF ORDER BY t.date ASC, t.created_at ASC", args);
    double running = 0, totalDebit = 0, totalCredit = 0;
    _reportRows = txs.map((tx) {
      final debit = (tx['debit'] as num?)?.toDouble() ?? 0;
      final credit = (tx['credit'] as num?)?.toDouble() ?? 0;
      running += (debit - credit);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'عليه (مدين)': debit,
        'له (دائن)': credit,
        'الرصيد': running,
      };
    }).toList();
    _reportTotals = {'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'المورد': 0};
  }

  Future<void> _loadExpensesReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = <dynamic>[];
    String whereClause = '1=1';
    if (_dateFrom != null) { whereClause += ' AND expense_date >= ?'; args.add(_dateFrom!.toIso8601String()); }
    if (_dateTo != null) { whereClause += ' AND expense_date < ?'; args.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
    if (_currencyCode() != null) { whereClause += ' AND currency = ?'; args.add(_currencyCode()!); }

    final results = await database.rawQuery(
      "SELECT title, amount, currency, expense_date, category, payment_method, beneficiary "
      "FROM expenses WHERE $whereClause ORDER BY expense_date DESC", args);
    double totalAmount = 0;
    _reportRows = results.map((r) {
      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
      totalAmount += amount;
      return {
        'العنوان': r['title'] as String? ?? '',
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['expense_date'] as String? ?? '',
        'الفئة': r['category'] as String? ?? '',
        'طريقة الدفع': r['payment_method'] as String? ?? '',
        'المستفيد': r['beneficiary'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'إجمالي المصروفات': totalAmount, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadInventoryReport(DatabaseHelper db) async {
    final database = await db.database;
    String whereExtra = '';
    final args = <dynamic>[];
    if (_selectedWarehouseId != null) { whereExtra += ' AND p.warehouse_id=?'; args.add(_selectedWarehouseId!); }
    if (_selectedCategoryId != null) { whereExtra += ' AND p.category_id=?'; args.add(_selectedCategoryId!); }

    final results = await database.rawQuery(
      "SELECT p.name_ar, p.barcode, p.item_code, p.current_stock, p.cost_price, p.sell_price, "
      "p.min_stock, w.name AS warehouse_name, c.name AS category_name, p.currency "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1$whereExtra ORDER BY p.name_ar", args);
    double totalValue = 0;
    _reportRows = results.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final cost = (p['cost_price'] as num?)?.toDouble() ?? 0;
      final value = stock * cost;
      totalValue += value;
      return {
        'الصنف': p['name_ar'] as String? ?? '',
        'الباركود': p['barcode'] as String? ?? '',
        'الكمية': stock,
        'سعر التكلفة': cost,
        'سعر البيع': (p['sell_price'] as num?)?.toDouble() ?? 0,
        'قيمة المخزون': value,
        'المخزن': p['warehouse_name'] as String? ?? '',
        'الفئة': p['category_name'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'قيمة المخزون': totalValue, 'عدد الأصناف': _reportRows.length.toDouble()};
  }

  Future<void> _loadInventoryMovementReport(DatabaseHelper db) async {
    final items = await db.getInventoryMovementReport(startDate: _dateFrom, endDate: _dateTo);
    _reportRows = items.map((item) {
      final qtyIn = (item['qty_in'] as num?)?.toDouble() ?? 0;
      final qtyOut = (item['qty_out'] as num?)?.toDouble() ?? 0;
      return {
        'الصنف': item['product_name'] as String? ?? '',
        'الوارد': qtyIn,
        'الصادر': qtyOut,
        'الصافي': qtyIn - qtyOut,
      };
    }).toList();
    final totalIn = _reportRows.fold(0.0, (s, r) => s + (r['الوارد'] as double));
    final totalOut = _reportRows.fold(0.0, (s, r) => s + (r['الصادر'] as double));
    _reportTotals = {'إجمالي الوارد': totalIn, 'إجمالي الصادر': totalOut, 'الصافي': totalIn - totalOut};
  }

  Future<void> _loadInventoryCostReport(DatabaseHelper db) async {
    final items = await db.getInventoryCostReport();
    double totalCost = 0, totalSell = 0;
    _reportRows = items.map((item) {
      final costVal = (item['stock_cost_value'] as num?)?.toDouble() ?? 0;
      final sellVal = (item['stock_sell_value'] as num?)?.toDouble() ?? 0;
      totalCost += costVal;
      totalSell += sellVal;
      return {
        'الصنف': item['product_name'] as String? ?? '',
        'الكمية': (item['current_stock'] as num?)?.toDouble() ?? 0,
        'سعر التكلفة': (item['cost_price'] as num?)?.toDouble() ?? 0,
        'تكلفة المخزون': costVal,
        'قيمة البيع': sellVal,
      };
    }).toList();
    _reportTotals = {'تكلفة المخزون': totalCost, 'قيمة البيع': totalSell, 'الربح المتوقع': totalSell - totalCost};
  }

  Future<void> _loadOutOfStockReport(DatabaseHelper db) async {
    final database = await db.database;
    String whereExtra = '';
    final args = <dynamic>[];
    if (_selectedWarehouseId != null) { whereExtra += ' AND p.warehouse_id=?'; args.add(_selectedWarehouseId!); }
    if (_selectedCategoryId != null) { whereExtra += ' AND p.category_id=?'; args.add(_selectedCategoryId!); }

    final results = await database.rawQuery(
      "SELECT p.name_ar, p.barcode, p.item_code, p.cost_price, p.sell_price, "
      "w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1 AND p.current_stock <= 0$whereExtra ORDER BY p.name_ar", args);
    _reportRows = results.map((p) => {
      'الصنف': p['name_ar'] as String? ?? '',
      'الباركود': p['barcode'] as String? ?? '',
      'سعر التكلفة': (p['cost_price'] as num?)?.toDouble() ?? 0,
      'سعر البيع': (p['sell_price'] as num?)?.toDouble() ?? 0,
      'المخزن': p['warehouse_name'] as String? ?? '',
      'الفئة': p['category_name'] as String? ?? '',
    }).toList();
    _reportTotals = {'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadLowStockReport(DatabaseHelper db) async {
    final database = await db.database;
    String whereExtra = '';
    final args = <dynamic>[];
    if (_selectedWarehouseId != null) { whereExtra += ' AND p.warehouse_id=?'; args.add(_selectedWarehouseId!); }
    if (_selectedCategoryId != null) { whereExtra += ' AND p.category_id=?'; args.add(_selectedCategoryId!); }

    final results = await database.rawQuery(
      "SELECT p.name_ar, p.barcode, p.current_stock, p.min_stock, p.cost_price, p.sell_price, "
      "w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1 AND p.current_stock > 0 AND p.current_stock <= p.min_stock$whereExtra ORDER BY p.name_ar", args);
    _reportRows = results.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final min = (p['min_stock'] as num?)?.toDouble() ?? 0;
      return {
        'الصنف': p['name_ar'] as String? ?? '',
        'الباركود': p['barcode'] as String? ?? '',
        'الكمية الحالية': stock,
        'الحد الأدنى': min,
        'سعر التكلفة': (p['cost_price'] as num?)?.toDouble() ?? 0,
        'سعر البيع': (p['sell_price'] as num?)?.toDouble() ?? 0,
        'المخزن': p['warehouse_name'] as String? ?? '',
        'الفئة': p['category_name'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadDebtReport(DatabaseHelper db, {required bool isCustomer}) async {
    _reportRows = [];
    double totalBalance = 0;
    if (isCustomer) {
      final customers = await db.getAllCustomers();
      for (final c in customers) {
        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
        if (balance > 0) {
          totalBalance += balance;
          _reportRows.add({
            'الاسم': c['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (c['balance_type'] as String? ?? 'credit') == 'credit' ? 'له (علينا)' : 'عليه (لنا)',
            'العملة': c['currency'] as String? ?? 'YER',
            'الهاتف': c['phone'] as String? ?? '',
            'سقف الدين': (c['debt_ceiling'] as num?)?.toDouble() ?? 0,
          });
        }
      }
    } else {
      final suppliers = await db.getAllSuppliers();
      for (final s in suppliers) {
        final balance = (s['balance'] as num?)?.toDouble() ?? 0;
        if (balance > 0) {
          totalBalance += balance;
          _reportRows.add({
            'الاسم': s['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (s['balance_type'] as String? ?? 'debit') == 'debit' ? 'عليه (لنا)' : 'له (علينا)',
            'العملة': s['currency'] as String? ?? 'YER',
            'الهاتف': s['phone'] as String? ?? '',
            'سقف الدين': (s['debt_ceiling'] as num?)?.toDouble() ?? 0,
          });
        }
      }
    }
    _reportTotals = {'إجمالي الديون': totalBalance, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadCashTransfersReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = [..._dateArgs()];
    final results = await database.rawQuery(
      "SELECT ct.*, cb1.name AS from_name, cb2.name AS to_name "
      "FROM cash_transfers ct LEFT JOIN cash_boxes cb1 ON ct.from_cash_box_id=cb1.id "
      "LEFT JOIN cash_boxes cb2 ON ct.to_cash_box_id=cb2.id "
      "WHERE 1=1${_dateFilter(column: 'ct.created_at')} ORDER BY ct.created_at DESC", args);
    double totalAmount = 0;
    _reportRows = results.map((r) {
      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
      totalAmount += amount;
      return {
        'من صندوق': r['from_name'] as String? ?? '',
        'إلى صندوق': r['to_name'] as String? ?? '',
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['created_at'] as String? ?? '',
        'ملاحظات': r['notes'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'إجمالي المبالغ': totalAmount, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadCurrencyExchangesReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = [..._dateArgs()];
    final results = await database.rawQuery(
      "SELECT ce.*, cb1.name AS from_name, cb2.name AS to_name "
      "FROM currency_exchanges ce LEFT JOIN cash_boxes cb1 ON ce.from_cash_box_id=cb1.id "
      "LEFT JOIN cash_boxes cb2 ON ce.to_cash_box_id=cb2.id "
      "WHERE 1=1${_dateFilter(column: 'ce.created_at')} ORDER BY ce.created_at DESC", args);
    _reportRows = results.map((r) => {
      'من عملة': r['from_currency'] as String? ?? '',
      'إلى عملة': r['to_currency'] as String? ?? '',
      'المبلغ المصروف': (r['from_amount'] as num?)?.toDouble() ?? 0,
      'المبلغ المستلم': (r['to_amount'] as num?)?.toDouble() ?? 0,
      'سعر الصرف': (r['exchange_rate'] as num?)?.toDouble() ?? 0,
      'من صندوق': r['from_name'] as String? ?? '',
      'إلى صندوق': r['to_name'] as String? ?? '',
      'التاريخ': r['created_at'] as String? ?? '',
    }).toList();
    _reportTotals = {'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadVouchersReport(DatabaseHelper db) async {
    final database = await db.database;
    final args = [..._dateArgs()];
    final results = await database.rawQuery(
      "SELECT v.*, cb.name AS cash_box_name "
      "FROM vouchers v LEFT JOIN cash_boxes cb ON v.cash_box_id=cb.id "
      "WHERE 1=1${_dateFilter(column: 'v.created_at')} ORDER BY v.created_at DESC", args);
    double totalAmount = 0;
    _reportRows = results.map((r) {
      final amount = (r['total_amount'] as num?)?.toDouble() ?? 0;
      totalAmount += amount;
      final vType = r['voucher_type'] as String? ?? '';
      String typeAr;
      switch (vType) {
        case 'receipt': typeAr = 'سند قبض'; break;
        case 'payment': typeAr = 'سند صرف'; break;
        default: typeAr = vType;
      }
      return {
        'رقم السند': r['voucher_number'] as String? ?? '',
        'النوع': typeAr,
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'الصندوق': r['cash_box_name'] as String? ?? '',
        'الوصف': r['description'] as String? ?? '',
        'التاريخ': r['date'] as String? ?? '',
      };
    }).toList();
    _reportTotals = {'إجمالي المبالغ': totalAmount, 'العدد': _reportRows.length.toDouble()};
  }

  Future<void> _loadShiftsReport(DatabaseHelper db) async {
    final database = await db.database;
    final results = await db.getAllShifts(orderBy: 'opened_at DESC');
    _reportRows = results.map((r) => {
      'رقم الوردية': r['shift_number'] as String? ?? '',
      'الكاشير': r['cashier_name'] as String? ?? '',
      'الصندوق': '', // would need join
      'المبيعات': (r['total_sales'] as num?)?.toDouble() ?? 0,
      'المرتجعات': (r['total_returns'] as num?)?.toDouble() ?? 0,
      'الخصومات': (r['total_discounts'] as num?)?.toDouble() ?? 0,
      'الحالة': (r['status'] as String? ?? '') == 'open' ? 'مفتوحة' : 'مغلقة',
      'تاريخ الفتح': r['opened_at'] as String? ?? '',
      'تاريخ الإغلاق': r['closed_at'] as String? ?? '',
    }).toList();
    _reportTotals = {'العدد': _reportRows.length.toDouble()};
  }

  // ══════════════════════════════════════════════════════════════
  //  Excel Export
  // ══════════════════════════════════════════════════════════════

  Future<void> _exportToExcel() async {
    if (_reportRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات للتصدير'), backgroundColor: AppColors.warning),
      );
      return;
    }
    try {
      await ExcelExporter.exportGenericReport(
        reportName: _getSelectedReportName(),
        rows: _reportRows,
        totals: _reportTotals,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _getSelectedReportName() {
    if (_selectedReportKey == null) return 'تقرير';
    for (final group in _groups) {
      for (final item in group.items) {
        if (item.key == _selectedReportKey) return item.name;
      }
    }
    return 'تقرير';
  }

  // ══════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التقارير'),
        ),
        body: Column(
          children: [
            // ── Report Selector + Filters ──
            _buildReportSelectorAndFilters(theme, isDark),
            const Divider(height: 1),
            // ── Results ──
            Expanded(child: _buildResultsArea(theme, isDark)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Report Selector & Filters
  // ══════════════════════════════════════════════════════════════

  Widget _buildReportSelectorAndFilters(ThemeData theme, bool isDark) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.topCenter,
      child: Container(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category accordion
            ..._groups.map((group) => _buildGroupSection(theme, isDark, group)),
            // Filters
            if (_selectedReportKey != null) ...[
              _buildFiltersRow(theme, isDark),
              // Action buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _loadReport,
                        icon: _isLoading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.search, size: 20),
                        label: Text(_isLoading ? 'جاري التحميل...' : 'عرض التقرير'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    if (_hasData && _reportRows.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _exportToExcel,
                        icon: const Icon(Icons.file_download, size: 20),
                        label: const Text('تصدير Excel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: const BorderSide(color: AppColors.success),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSection(ThemeData theme, bool isDark, _ReportGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => group.isExpanded = !group.isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(group.icon, size: 20, color: group.color),
                const SizedBox(width: 10),
                Expanded(child: Text(group.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: group.color))),
                Icon(group.isExpanded ? Icons.expand_less : Icons.expand_more, size: 22, color: AppColors.textHint),
              ],
            ),
          ),
        ),
        if (group.isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: group.items.map((item) {
                final isSelected = _selectedReportKey == item.key;
                return ChoiceChip(
                  avatar: Icon(item.icon, size: 16, color: isSelected ? Colors.white : item.color),
                  label: Text(item.name, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : null)),
                  selected: isSelected,
                  selectedColor: item.color,
                  onSelected: (_) {
                    setState(() {
                      _selectedReportKey = item.key;
                      _hasData = false;
                      _reportRows = [];
                      _reportTotals = {};
                    });
                  },
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFiltersRow(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Row 1: Date range + Currency
          if (_needsDateFilter() || _needsCurrencyFilter())
            Row(
              children: [
                if (_needsDateFilter()) ...[
                  _buildFilterChip(theme, Icons.calendar_today, _dateFrom != null ? _fmtDate(_dateFrom!.toIso8601String()) : 'من', _pickDateFrom),
                  const SizedBox(width: 6),
                  _buildFilterChip(theme, Icons.calendar_today, _dateTo != null ? _fmtDate(_dateTo!.toIso8601String()) : 'إلى', _pickDateTo),
                ],
                if (_needsCurrencyFilter()) ...[
                  const SizedBox(width: 6),
                  _buildCurrencyDropdown(theme),
                ],
                const Spacer(),
                if (_dateFrom != null || _dateTo != null || _selectedCurrency != 'الكل')
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: AppColors.error),
                    tooltip: 'مسح الفلاتر',
                    onPressed: _clearFilters,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          // Row 2: Entity-specific filters
          if (_needsAccountFilter() || _needsCustomerFilter() || _needsSupplierFilter() ||
              _needsCashBoxFilter() || _needsWarehouseFilter() || _needsCategoryFilter() || _needsAccountTypeFilter())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (_needsAccountFilter()) Expanded(child: _buildAccountDropdown(theme)),
                  if (_needsCustomerFilter()) Expanded(child: _buildCustomerDropdown(theme)),
                  if (_needsSupplierFilter()) Expanded(child: _buildSupplierDropdown(theme)),
                  if (_needsCashBoxFilter()) Expanded(child: _buildCashBoxDropdown(theme)),
                  if (_needsWarehouseFilter()) Expanded(child: _buildWarehouseDropdown(theme)),
                  if (_needsCategoryFilter()) ...[
                    const SizedBox(width: 6),
                    Expanded(child: _buildCategoryDropdown(theme)),
                  ],
                  if (_needsAccountTypeFilter()) ...[
                    const SizedBox(width: 6),
                    Expanded(child: _buildAccountTypeDropdown(theme)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCurrency,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
          items: _currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (val) { if (val != null) setState(() => _selectedCurrency = val); },
        ),
      ),
    );
  }

  Widget _buildAccountDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllAccounts(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedAccountId,
          items: snap.data!.map((a) => DropdownMenuItem<int>(
            value: a['id'] as int,
            child: Text('${a['name_ar']} (${a['currency']})', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedAccountId = v),
          hint: 'اختر الحساب',
        );
      },
    );
  }

  Widget _buildCustomerDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllCustomers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedCustomerId,
          items: snap.data!.map((c) => DropdownMenuItem<int>(
            value: c['id'] as int,
            child: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedCustomerId = v),
          hint: 'اختر العميل',
        );
      },
    );
  }

  Widget _buildSupplierDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllSuppliers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedSupplierId,
          items: snap.data!.map((s) => DropdownMenuItem<int>(
            value: s['id'] as int,
            child: Text(s['name'] as String? ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedSupplierId = v),
          hint: 'اختر المورد',
        );
      },
    );
  }

  Widget _buildCashBoxDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllCashBoxes(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedCashBoxId,
          items: snap.data!.map((cb) => DropdownMenuItem<int>(
            value: cb['id'] as int,
            child: Text('${cb['name']} (${cb['currency']})', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _selectedCashBoxId = v),
          hint: 'اختر الصندوق',
        );
      },
    );
  }

  Widget _buildWarehouseDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllWarehouses(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final items = [DropdownMenuItem<int>(value: null, child: Text('كل المخازن', style: TextStyle(fontSize: 12)))];
        items.addAll(snap.data!.map((w) => DropdownMenuItem<int>(
          value: w['id'] as int,
          child: Text(w['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
        )));
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedWarehouseId,
          items: items,
          onChanged: (v) => setState(() => _selectedWarehouseId = v),
          hint: 'المخزن',
        );
      },
    );
  }

  Widget _buildCategoryDropdown(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllCategories(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final items = [DropdownMenuItem<int>(value: null, child: Text('كل الفئات', style: TextStyle(fontSize: 12)))];
        items.addAll(snap.data!.map((c) => DropdownMenuItem<int>(
          value: c['id'] as int,
          child: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
        )));
        return _buildDropdown<int>(
          theme: theme,
          value: _selectedCategoryId,
          items: items,
          onChanged: (v) => setState(() => _selectedCategoryId = v),
          hint: 'الفئة',
        );
      },
    );
  }

  Widget _buildAccountTypeDropdown(ThemeData theme) {
    return _buildDropdown<String>(
      theme: theme,
      value: _selectedAccountType,
      items: _accountTypes.map((e) => DropdownMenuItem<String>(
        value: e.key,
        child: Text(e.key, style: const TextStyle(fontSize: 12)),
      )).toList(),
      onChanged: (v) { if (v != null) setState(() => _selectedAccountType = v); },
      hint: 'نوع الحساب',
    );
  }

  Widget _buildDropdown<T>({
    required ThemeData theme,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required String hint,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          hint: Text(hint, style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.6))),
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Results Area
  // ══════════════════════════════════════════════════════════════

  Widget _buildResultsArea(ThemeData theme, bool isDark) {
    if (_selectedReportKey == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 64, color: AppColors.textHint.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('اختر نوع التقرير من الأعلى', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 4),
            Text('ثم حدد الفلاتر واضغط عرض التقرير', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 48, color: AppColors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('حدد الفلاتر واضغط "عرض التقرير"', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
          ],
        ),
      );
    }

    if (_reportRows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('لا توجد بيانات لهذا التقرير', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
          ],
        ),
      );
    }

    // Build table
    final columns = _reportRows.first.keys.toList();
    return Column(
      children: [
        // Totals bar
        if (_reportTotals.isNotEmpty) _buildTotalsBar(theme, isDark),
        // Data table
        Expanded(child: _buildDataTable(theme, isDark, columns)),
      ],
    );
  }

  Widget _buildTotalsBar(ThemeData theme, bool isDark) {
    final entries = _reportTotals.entries.where((e) => e.key != 'العدد' && e.key != 'عدد الحسابات' && e.key != 'عدد الأصناف' && e.key != 'عدد العملاء' && e.key != 'العميل' && e.key != 'المورد').toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: entries.map((e) {
          final isPositive = e.value >= 0;
          return Expanded(
            child: Column(
              children: [
                Text(e.key, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Text(
                  _fmtMoney(e.value.abs()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: e.value == 0 ? AppColors.textPrimary : (e.key.contains('ربح') || e.key.contains('إيرادات') || e.key.contains('مبيعات') || e.key.contains('البيع'))
                        ? (isPositive ? AppColors.success : AppColors.error)
                        : (e.key.contains('مشتريات') || e.key.contains('تكلفة') || e.key.contains('مصروف') || e.key.contains('دين'))
                            ? AppColors.error
                            : AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDataTable(ThemeData theme, bool isDark, List<String> columns) {
    // Identify numeric columns for right-alignment and formatting
    final numericKeys = <String>{};
    for (final row in _reportRows) {
      for (final key in columns) {
        final v = row[key];
        if (v is double || v is int) numericKeys.add(key);
      }
    }

    // Date-like keys for short formatting
    final dateKeys = {'التاريخ', 'تاريخ الفتح', 'تاريخ الإغلاق'};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
            headingTextStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 11),
            dataTextStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            columnSpacing: 16,
            horizontalMargin: 12,
            columns: columns.map((col) => DataColumn(
              label: Text(col, style: const TextStyle(fontWeight: FontWeight.w800)),
              numeric: numericKeys.contains(col),
            )).toList(),
            rows: _reportRows.map((row) {
              return DataRow(cells: columns.map((col) {
                final v = row[col];
                String display;
                if (v == null) {
                  display = '-';
                } else if (v is double) {
                  if (dateKeys.contains(col)) {
                    display = _fmtDate(v.toString());
                  } else if (numericKeys.contains(col) && (col.contains('الكمية') || col.contains('الوارد') || col.contains('الصادر') || col.contains('الصافي') || col.contains('الحد') || col.contains('عدد'))) {
                    display = _fmtNum(v);
                  } else if (col.contains('هامش')) {
                    display = '${v.toStringAsFixed(1)}%';
                  } else if (col.contains('سعر الصرف')) {
                    display = v.toStringAsFixed(4);
                  } else {
                    display = _fmtMoney(v);
                  }
                } else if (v is int) {
                  display = v.toString();
                } else {
                  final str = v.toString();
                  display = dateKeys.contains(col) ? _fmtDate(str) : str;
                }
                return DataCell(Text(display, textAlign: numericKeys.contains(col) ? TextAlign.left : TextAlign.right));
              }).toList());
            }).toList(),
          ),
        ),
      ),
    );
  }
}
