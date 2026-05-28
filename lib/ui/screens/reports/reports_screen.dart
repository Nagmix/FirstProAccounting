import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/database_helper.dart';
import 'trial_balance_screen.dart';
import 'financial_statements_screen.dart';

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

// ── Date Preset ─────────────────────────────────────────────────

enum _DatePreset {
  today,
  thisWeek,
  thisMonth,
  thisQuarter,
  thisYear,
  custom,
}

// ── State ───────────────────────────────────────────────────────

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late List<_ReportGroup> _groups;
  String? _selectedReportKey;
  bool _isLoading = false;
  bool _hasData = false;

  // Filters
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _selectedCurrency = 'ر.ي';
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

  // New UI state
  late TabController _tabController;
  _DatePreset _selectedDatePreset = _DatePreset.thisMonth;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  String _searchQuery = '';

  static const _currencyOptions = ['ر.ي', 'ر.س', r'$'];
  static const _accountTypes = [
    MapEntry('الكل', 'الكل'),
    MapEntry('أصول', 'ASSET'),
    MapEntry('خصوم', 'LIABILITY'),
    MapEntry('حقوق الملكية', 'EQUITY'),
    MapEntry('تكاليف', 'COST'),
    MapEntry('إيرادات', 'REVENUE'),
    MapEntry('مصاريف', 'EXPENSE'),
  ];

  @override
  void initState() {
    super.initState();
    _initGroups();
    _tabController = TabController(length: _groups.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _applyDatePreset(_selectedDatePreset);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          const _ReportItem(name: 'ميزان المراجعة (شاشة كاملة)', icon: Icons.balance, color: AppColors.primary, key: 'trial_balance_screen'),
          const _ReportItem(name: 'القوائم المالية', icon: Icons.account_balance, color: AppColors.info, key: 'financial_statements'),
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
  //  Date Preset Helpers
  // ══════════════════════════════════════════════════════════════

  void _applyDatePreset(_DatePreset preset) {
    final now = DateTime.now();
    setState(() {
      _selectedDatePreset = preset;
      switch (preset) {
        case _DatePreset.today:
          _dateFrom = DateTime(now.year, now.month, now.day);
          _dateTo = DateTime(now.year, now.month, now.day);
        case _DatePreset.thisWeek:
          final weekday = now.weekday;
          final weekStart = now.subtract(Duration(days: weekday - 1));
          _dateFrom = DateTime(weekStart.year, weekStart.month, weekStart.day);
          _dateTo = DateTime(now.year, now.month, now.day);
        case _DatePreset.thisMonth:
          _dateFrom = DateTime(now.year, now.month, 1);
          _dateTo = DateTime(now.year, now.month, now.day);
        case _DatePreset.thisQuarter:
          final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
          _dateFrom = DateTime(now.year, quarterStartMonth, 1);
          _dateTo = DateTime(now.year, now.month, now.day);
        case _DatePreset.thisYear:
          _dateFrom = DateTime(now.year, 1, 1);
          _dateTo = DateTime(now.year, now.month, now.day);
        case _DatePreset.custom:
          // Don't change dates – let user pick
          break;
      }
    });
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
      case 'EQUITY': return 'حقوق الملكية';
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
    if (picked != null) {
      setState(() {
        _dateFrom = picked;
        _selectedDatePreset = _DatePreset.custom;
      });
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dateTo = picked;
        _selectedDatePreset = _DatePreset.custom;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedCurrency = 'ر.ي';
      _selectedAccountId = null;
      _selectedCustomerId = null;
      _selectedSupplierId = null;
      _selectedCashBoxId = null;
      _selectedWarehouseId = null;
      _selectedCategoryId = null;
      _selectedAccountType = 'الكل';
      _selectedDatePreset = _DatePreset.custom;
      _searchQuery = '';
      _sortColumnIndex = null;
      _sortAscending = true;
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
        debugPrint('Report error ($_selectedReportKey): $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل التقرير: ${e.toString().length > 80 ? e.toString().substring(0, 80) + '...' : e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
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
      final total = MoneyHelper.readMoney(r['total']);
      final paid = MoneyHelper.readMoney(r['paid_amount']);
      final remaining = MoneyHelper.readMoney(r['remaining']);
      totalAmount += total;
      totalPaid += paid;
      totalRemaining += remaining;
      return {
        'رقم الفاتورة': () { final idStr = (r['id'] as String?) ?? ''; return idStr.length > 12 ? idStr.substring(0, 12) : idStr; }(),
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
    final revenue = MoneyHelper.readMoney(revRes.first['t']);

    final purRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type='purchase' AND is_return=0$df$cf", allArgs);
    final purchases = MoneyHelper.readMoney(purRes.first['t']);

    final retSaleRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type IN ('sale','pos') AND is_return=1$df$cf", allArgs);
    final salesReturns = MoneyHelper.readMoney(retSaleRes.first['t']);

    final retPurRes = await database.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type='purchase' AND is_return=1$df$cf", allArgs);
    final purchaseReturns = MoneyHelper.readMoney(retPurRes.first['t']);

    final expArgs = <dynamic>[];
    if (_dateFrom != null) expArgs.add(_dateFrom!.toIso8601String());
    if (_dateTo != null) expArgs.add(_dateTo!.add(const Duration(days: 1)).toIso8601String());
    expArgs.addAll(_currencyArgs());
    final expRes = await database.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE 1=1${_dateFilter(column: 'expense_date')}$cf", expArgs);
    final expenses = MoneyHelper.readMoney(expRes.first['t']);

    final netSales = revenue - salesReturns;
    final netPurchases = purchases - purchaseReturns;

    // ── COGS Calculation ──
    // Method: Calculate COGS directly from invoice_items using stored unit_cost
    // This is more accurate than the inventory-based formula because:
    // 1. unit_cost is captured at time of sale (not current cost_price which may have changed)
    // 2. It handles partial-period correctly without needing beginning inventory
    // 3. Works even when stock_movements data is incomplete
    double cogs = 0.0;
    try {
      // COGS from sales: sum of (base_quantity * unit_cost) for all sale/pos items
      final cogsSaleArgs = <dynamic>[];
      String cogsDateF = '';
      if (_dateFrom != null) { cogsDateF += ' AND i.created_at >= ?'; cogsSaleArgs.add(_dateFrom!.toIso8601String()); }
      if (_dateTo != null) { cogsDateF += ' AND i.created_at < ?'; cogsSaleArgs.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
      if (_currencyCode() != null) { cogsDateF += ' AND i.currency = ?'; cogsSaleArgs.add(_currencyCode()!); }

      final cogsRes = await database.rawQuery(
        "SELECT COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END "
        "), 0) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = 0$cogsDateF",
        cogsSaleArgs,
      );
      cogs = MoneyHelper.readMoney(cogsRes.first['total_cogs']);

      // Subtract COGS from sales returns (inventory comes back)
      if (salesReturns > 0) {
        final cogsRetArgs = <dynamic>[];
        String cogsRetF = '';
        if (_dateFrom != null) { cogsRetF += ' AND i.created_at >= ?'; cogsRetArgs.add(_dateFrom!.toIso8601String()); }
        if (_dateTo != null) { cogsRetF += ' AND i.created_at < ?'; cogsRetArgs.add(_dateTo!.add(const Duration(days: 1)).toIso8601String()); }
        if (_currencyCode() != null) { cogsRetF += ' AND i.currency = ?'; cogsRetArgs.add(_currencyCode()!); }

        final cogsRetRes = await database.rawQuery(
          "SELECT COALESCE(SUM("
          "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
          "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END "
          "), 0) AS total_cogs "
          "FROM invoice_items ii "
          "INNER JOIN invoices i ON ii.invoice_id = i.id "
          "LEFT JOIN products p ON ii.product_id = p.id "
          "WHERE i.type IN ('sale','pos') AND i.is_return = 1$cogsRetF",
          cogsRetArgs,
        );
        cogs -= MoneyHelper.readMoney(cogsRetRes.first['total_cogs']);
      }
    } catch (e) {
      debugPrint('COGS calculation error: $e');
      // Fallback: use simple purchase-based estimate
      cogs = netPurchases;
    }

    final grossProfit = netSales - cogs;
    final netProfit = grossProfit - expenses;

    _reportRows = [
      {'البند': 'إجمالي المبيعات', 'المبلغ': revenue, 'ملاحظة': 'فواتير البيع'},
      {'البند': 'مرتجعات المبيعات', 'المبلغ': -salesReturns, 'ملاحظة': 'فواتير المرتجع'},
      {'البند': 'صافي المبيعات', 'المبلغ': netSales, 'ملاحظة': ''},
      {'البند': 'تكلفة البضاعة المباعة', 'المبلغ': cogs, 'ملاحظة': 'محسوبة من تكلفة الأصناف المباعة'},
      {'البند': 'مجمل الربح', 'المبلغ': grossProfit, 'ملاحظة': 'صافي المبيعات - تكلفة البضاعة'},
      {'البند': 'المصاريف التشغيلية', 'المبلغ': -expenses, 'ملاحظة': ''},
      {'البند': 'صافي الربح', 'المبلغ': netProfit, 'ملاحظة': 'مجمل الربح - المصاريف'},
    ];
    _reportTotals = {'صافي المبيعات': netSales, 'تكلفة البضاعة': cogs, 'صافي الربح': netProfit};
  }

  Future<void> _loadInvoiceProfitReport(DatabaseHelper db) async {
    final items = await db.getInvoiceProfitReport(startDate: _dateFrom, endDate: _dateTo);
    double totalProfit = 0, totalRevenue = 0, totalCost = 0;
    _reportRows = items.map((item) {
      final profit = MoneyHelper.readMoney(item['profit']);
      final total = MoneyHelper.readMoney(item['sale_total']);
      final cost = MoneyHelper.readMoney(item['cost_total']);
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

    // Include cost and profit per product using unit_cost from invoice_items
    final results = await database.rawQuery(
      "SELECT ii.product_name, SUM(ii.quantity) AS qty, SUM(ii.total_price) AS revenue, "
      "SUM("
      "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
      "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
      ") AS cost_total, "
      "COUNT(DISTINCT ii.invoice_id) AS inv_count "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id=i.id "
      "LEFT JOIN products p ON ii.product_id=p.id $catJoin "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0$dateF$curF$catFilter "
      "GROUP BY ii.product_id ORDER BY revenue DESC",
      args,
    );
    double totalRevenue = 0, totalCost = 0, totalProfit = 0;
    int totalQty = 0;
    _reportRows = results.map((r) {
      final rev = MoneyHelper.readMoney(r['revenue']);
      final cost = MoneyHelper.readMoney(r['cost_total']);
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      final profit = rev - cost;
      totalRevenue += rev;
      totalCost += cost;
      totalProfit += profit;
      totalQty += qty.toInt();
      return {
        'المنتج': r['product_name'] as String? ?? '',
        'الكمية المباعة': qty,
        'إجمالي المبيعات': rev,
        'تكلفة المبيعات': cost,
        'الربح': profit,
        'هامش الربح': rev > 0 ? (profit / rev * 100) : 0.0,
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    _reportTotals = {'إجمالي المبيعات': totalRevenue, 'إجمالي التكلفة': totalCost, 'إجمالي الربح': totalProfit, 'إجمالي الكمية': totalQty.toDouble(), 'عدد الأصناف': _reportRows.length.toDouble()};
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
      final sales = MoneyHelper.readMoney(r['total_sales']);
      totalSales += sales;
      return {
        'العميل': r['customer_name'] as String,
        'العملة': r['currency'] as String? ?? 'YER',
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
        'إجمالي المبيعات': sales,
        'المدفوع': MoneyHelper.readMoney(r['total_paid']),
        'المتبقي': MoneyHelper.readMoney(r['total_remaining']),
      };
    }).toList();
    _reportTotals = {'إجمالي المبيعات': totalSales, 'عدد العملاء': _reportRows.length.toDouble()};
  }

  Future<void> _loadAccountMovementReport(DatabaseHelper db) async {
    if (_selectedAccountId == null) return;
    // Use raw query with date filter instead of getAccountTransactions
    // which ignores date range completely (BUG FIX)
    final database = await db.database;
    final args = <dynamic>[_selectedAccountId!];
    args.addAll(_dateArgs());
    final transactions = await database.rawQuery(
      "SELECT id, account_id, debit, credit, description, date, created_at "
      "FROM transactions "
      "WHERE account_id = ?${_dateFilter(column: 'date')}"
      " ORDER BY date ASC, created_at ASC",
      args,
    );
    double running = 0;
    double totalDebit = 0, totalCredit = 0;
    _reportRows = [];
    for (final tx in transactions) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
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
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
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
    final database = await db.database;
    final accounts = await db.getAllAccounts();
    final cc = _currencyCode();
    double totalDebit = 0, totalCredit = 0;
    _reportRows = [];

    // Build date filter for trial balance query
    final dateFilter = _dateFilter(column: 'date');
    final dateArgs = _dateArgs();

    for (final account in accounts) {
      if (cc != null && account['currency'] != cc) continue;
      if (_selectedAccountType != 'الكل') {
        final typeCode = _accountTypes.firstWhere((e) => e.key == _selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
        if (typeCode != 'الكل' && account['account_type'] != typeCode) continue;
      }
      final accountId = account['id'] as int;

      // Calculate balance from transactions with date filter
      // instead of using cached accounts.balance or getAccountBalance
      // which ignores date range (BUG FIX)
      final balanceArgs = <dynamic>[accountId];
      balanceArgs.addAll(dateArgs);
      final result = await database.rawQuery(
        "SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS balance "
        "FROM transactions "
        "WHERE account_id = ?$dateFilter",
        balanceArgs,
      );
      final balance = MoneyHelper.readMoney(result.first['balance']);

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
      final balance = MoneyHelper.readMoney(cb['balance']);
      final isCredit = (cb['balance_type'] as String? ?? 'credit') == 'credit';
      final signedBalance = isCredit ? balance : -balance;
      totalBalance += signedBalance;

      final invRes = await database.rawQuery(
        "SELECT type, COALESCE(SUM(total),0) as total FROM invoices WHERE cash_box_id=? AND is_return=0${_dateFilter()} GROUP BY type",
        [cbId, ..._dateArgs()]);
      double salesTotal = 0, purchaseTotal = 0;
      for (final inv in invRes) {
        final t = inv['type'] as String? ?? '';
        final tot = MoneyHelper.readMoney(inv['total']);
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
    _reportTotals = {'إجمالي الأرصدة': totalBalance.abs(), 'عدد الصناديق': _reportRows.length.toDouble()}; // totalBalance is computed from already-converted values
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

    // Try to find the customer's receivable account by exact name first, then fallback to LIKE
    var acctRes = await database.rawQuery(
      "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1", [custName, custCurrency]);
    if (acctRes.isEmpty && custName.isNotEmpty) {
      acctRes = await database.rawQuery(
        "SELECT id FROM accounts WHERE (name_ar LIKE ? OR name_ar LIKE ?) AND currency=? LIMIT 1",
        ['%$custName%', '%$custName%', custCurrency]);
    }
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
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
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

    // Try to find the supplier's payable account by exact name first, then fallback to LIKE
    var acctRes = await database.rawQuery(
      "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1", [supName, supCurrency]);
    if (acctRes.isEmpty && supName.isNotEmpty) {
      acctRes = await database.rawQuery(
        "SELECT id FROM accounts WHERE (name_ar LIKE ? OR name_ar LIKE ?) AND currency=? LIMIT 1",
        ['%$supName%', '%$supName%', supCurrency]);
    }
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
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
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
      final amount = MoneyHelper.readMoney(r['amount']);
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
      "p.min_stock, p.currency, w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1$whereExtra ORDER BY p.name_ar", args);
    double totalValue = 0;
    _reportRows = results.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final cost = MoneyHelper.readMoney(p['cost_price']);
      final value = stock * cost;
      totalValue += value;
      return {
        'الصنف': p['name_ar'] as String? ?? '',
        'الباركود': p['barcode'] as String? ?? '',
        'الكمية': stock,
        'سعر التكلفة': cost,
        'سعر البيع': MoneyHelper.readMoney(p['sell_price']),
        'قيمة المخزون': value,
        'العملة': p['currency'] as String? ?? 'YER',
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
      final costVal = MoneyHelper.readMoney(item['stock_cost_value']);
      final sellVal = MoneyHelper.readMoney(item['stock_sell_value']);
      totalCost += costVal;
      totalSell += sellVal;
      return {
        'الصنف': item['product_name'] as String? ?? '',
        'الكمية': (item['current_stock'] as num?)?.toDouble() ?? 0,
        'سعر التكلفة': MoneyHelper.readMoney(item['cost_price']),
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
      'سعر التكلفة': MoneyHelper.readMoney(p['cost_price']),
      'سعر البيع': MoneyHelper.readMoney(p['sell_price']),
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
        'سعر التكلفة': MoneyHelper.readMoney(p['cost_price']),
        'سعر البيع': MoneyHelper.readMoney(p['sell_price']),
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
        final balance = MoneyHelper.readMoney(c['balance']);
        if (balance > 0) {
          totalBalance += balance;
          _reportRows.add({
            'الاسم': c['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (c['balance_type'] as String? ?? 'credit') == 'credit' ? 'له (علينا)' : 'عليه (لنا)',
            'العملة': c['currency'] as String? ?? 'YER',
            'الهاتف': c['phone'] as String? ?? '',
            'سقف الدين': MoneyHelper.readMoney(c['debt_ceiling']),
          });
        }
      }
    } else {
      final suppliers = await db.getAllSuppliers();
      for (final s in suppliers) {
        final balance = MoneyHelper.readMoney(s['balance']);
        if (balance > 0) {
          totalBalance += balance;
          _reportRows.add({
            'الاسم': s['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (s['balance_type'] as String? ?? 'debit') == 'debit' ? 'عليه (لنا)' : 'له (علينا)',
            'العملة': s['currency'] as String? ?? 'YER',
            'الهاتف': s['phone'] as String? ?? '',
            'سقف الدين': MoneyHelper.readMoney(s['debt_ceiling']),
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
      final amount = MoneyHelper.readMoney(r['amount']);
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
      'المبلغ المصروف': MoneyHelper.readMoney(r['from_amount']),
      'المبلغ المستلم': MoneyHelper.readMoney(r['to_amount']),
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
      final amount = MoneyHelper.readMoney(r['total_amount']);
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
      'المبيعات': MoneyHelper.readMoney(r['total_sales']),
      'المرتجعات': MoneyHelper.readMoney(r['total_returns']),
      'الخصومات': MoneyHelper.readMoney(r['total_discounts']),
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
          SnackBar(content: Text('حدث خطأ أثناء التصدير'), backgroundColor: AppColors.error),
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
  //  Dropdown Helpers (preserved)
  // ══════════════════════════════════════════════════════════════

  Widget _buildCurrencyDropdown(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
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
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          hint: Text(hint, style: TextStyle(fontSize: 11, color: AppColors.primary.withOpacity(0.6))),
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Build – NEW UI
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildSliverAppBar(theme, isDark),
          ],
          body: _buildBody(theme, isDark),
        ),
        floatingActionButton: _hasData && _reportRows.isNotEmpty
            ? _buildExportFab(theme, isDark)
            : null,
      ),
    );
  }

  // ── SliverAppBar with TabBar ──────────────────────────────────

  Widget _buildSliverAppBar(ThemeData theme, bool isDark) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 60,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
      foregroundColor: Colors.white,
      title: const Text('التقارير', style: TextStyle(fontWeight: FontWeight.w700)),
      centerTitle: false,
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppColors.secondary,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.6),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        tabAlignment: TabAlignment.start,
        tabs: _groups.map((g) => Tab(
          icon: Icon(g.icon, size: 18),
          text: g.name,
          height: 52,
        )).toList(),
      ),
    );
  }

  // ── Body Content ─────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, bool isDark) {
    return TabBarView(
      controller: _tabController,
      children: _groups.asMap().entries.map((entry) {
        final group = entry.value;
        return _buildTabContent(theme, isDark, group);
      }).toList(),
    );
  }

  Widget _buildTabContent(ThemeData theme, bool isDark, _ReportGroup group) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report cards grid
          _buildReportCardsGrid(theme, isDark, group),
          // Filters section (only when a report is selected from this group)
          if (_selectedReportKey != null && group.items.any((i) => i.key == _selectedReportKey)) ...[
            const SizedBox(height: 12),
            _buildFiltersSection(theme, isDark),
            const SizedBox(height: 12),
            _buildLoadButton(theme, isDark),
            const SizedBox(height: 16),
            // Results area
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildResultsArea(theme, isDark),
            ),
          ],
        ],
      ),
    );
  }

  // ── Report Cards Grid ────────────────────────────────────────

  Widget _buildReportCardsGrid(ThemeData theme, bool isDark, _ReportGroup group) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: group.items.length,
      itemBuilder: (context, index) {
        final item = group.items[index];
        final isSelected = _selectedReportKey == item.key;
        return _buildReportCard(theme, isDark, item, isSelected);
      },
    );
  }

  Widget _buildReportCard(ThemeData theme, bool isDark, _ReportItem item, bool isSelected) {
    final bgColor = isSelected
        ? item.color.withOpacity(isDark ? 0.25 : 0.1)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant);
    final borderColor = isSelected ? item.color : (isDark ? AppColors.darkBorder : AppColors.border);
    final iconColor = isSelected ? item.color : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);

    return GestureDetector(
      onTap: () => _onReportSelected(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: item.color.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(item.icon, size: 28, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? item.color
                          : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, size: 18, color: item.color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _getReportDescription(item.key),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getReportDescription(String key) {
    const descriptions = {
      'sales': 'تفاصيل فواتير المبيعات',
      'purchases': 'تفاصيل فواتير المشتريات',
      'sales_returns': 'فواتير المرتجعات للمبيعات',
      'purchase_returns': 'فواتير المرتجعات للمشتريات',
      'profit_loss': 'ملخص الأرباح والخسائر',
      'invoice_profit': 'ربح كل فاتورة بالتفصيل',
      'sales_by_product': 'ترتيب المنتجات حسب المبيعات',
      'sales_by_customer': 'ترتيب العملاء حسب المشتريات',
      'account_movement': 'حركة حساب محدد بالتفصيل',
      'all_account_movement': 'كل حركات الحسابات',
      'trial_balance': 'ميزان المراجعة للتحقق',
      'trial_balance_screen': 'شاشة كاملة لميزان المراجعة',
      'financial_statements': 'قائمة الدخل والمركزية المالي',
      'cash_box': 'أرصدة وحركة الصناديق',
      'accounts_no_movement': 'حسابات بلا قيود',
      'customer_statement': 'كشف حساب عميل',
      'supplier_statement': 'كشف حساب مورد',
      'expenses': 'تفاصيل المصروفات',
      'inventory': 'حالة المخزون الحالية',
      'inventory_movement': 'وارد وصادر المخزون',
      'inventory_cost': 'تكلفة وقيمة المخزون',
      'out_of_stock': 'أصناف نفدت من المخزون',
      'low_stock': 'أصناف تحت الحد الأدنى',
      'customer_debts': 'ديون العملاء المستحقة',
      'supplier_debts': 'ديون الموردين المستحقة',
      'cash_transfers': 'التحويلات بين الصناديق',
      'currency_exchanges': 'عمليات صرافة العملات',
      'vouchers': 'سندات القبض والصرف',
      'shifts': 'تقرير الورديات',
    };
    return descriptions[key] ?? 'تقرير';
  }

  void _onReportSelected(_ReportItem item) {
    // Navigate to standalone screens for dedicated report views
    if (item.key == 'trial_balance_screen') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TrialBalanceScreen()));
      return;
    }
    if (item.key == 'financial_statements') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialStatementsScreen()));
      return;
    }
    setState(() {
      _selectedReportKey = item.key;
      _hasData = false;
      _reportRows = [];
      _reportTotals = {};
      _searchQuery = '';
      _sortColumnIndex = null;
      _sortAscending = true;
    });
  }

  // ── Filters Section ──────────────────────────────────────────

  Widget _buildFiltersSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick date presets
          if (_needsDateFilter()) ...[
            _buildDatePresetsRow(theme, isDark),
            const SizedBox(height: 8),
            // Custom date pickers (show only when custom is selected)
            if (_selectedDatePreset == _DatePreset.custom)
              _buildCustomDateRow(theme, isDark),
          ],
          // Currency and entity filters
          if (_needsCurrencyFilter() || _needsAccountFilter() || _needsCustomerFilter() ||
              _needsSupplierFilter() || _needsCashBoxFilter() || _needsWarehouseFilter() ||
              _needsCategoryFilter() || _needsAccountTypeFilter()) ...[
            const SizedBox(height: 8),
            _buildEntityFiltersRow(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildDatePresetsRow(ThemeData theme, bool isDark) {
    final presets = [
      (_DatePreset.today, 'اليوم'),
      (_DatePreset.thisWeek, 'هذا الأسبوع'),
      (_DatePreset.thisMonth, 'هذا الشهر'),
      (_DatePreset.thisQuarter, 'هذا الربع'),
      (_DatePreset.thisYear, 'هذا العام'),
      (_DatePreset.custom, 'مخصص'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((p) {
          final isSelected = _selectedDatePreset == p.$1;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(p.$2),
              selected: isSelected,
              selectedColor: AppColors.primary.withOpacity(0.2),
              backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
              side: BorderSide(
                color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.border),
              ),
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _applyDatePreset(p.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCustomDateRow(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildFilterChip(theme, Icons.calendar_today,
            _dateFrom != null ? _fmtDate(_dateFrom!.toIso8601String()) : 'من تاريخ', _pickDateFrom),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildFilterChip(theme, Icons.calendar_today,
            _dateTo != null ? _fmtDate(_dateTo!.toIso8601String()) : 'إلى تاريخ', _pickDateTo),
        ),
        if (_dateFrom != null || _dateTo != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.clear, size: 18, color: AppColors.error),
            tooltip: 'مسح التاريخ',
            onPressed: () {
              setState(() {
                _dateFrom = null;
                _dateTo = null;
              });
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }

  Widget _buildEntityFiltersRow(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_needsCurrencyFilter())
          SizedBox(width: 100, child: _buildCurrencyDropdown(theme)),
        if (_needsAccountFilter())
          SizedBox(width: 180, child: _buildAccountDropdown(theme)),
        if (_needsCustomerFilter())
          SizedBox(width: 180, child: _buildCustomerDropdown(theme)),
        if (_needsSupplierFilter())
          SizedBox(width: 180, child: _buildSupplierDropdown(theme)),
        if (_needsCashBoxFilter())
          SizedBox(width: 180, child: _buildCashBoxDropdown(theme)),
        if (_needsWarehouseFilter())
          SizedBox(width: 140, child: _buildWarehouseDropdown(theme)),
        if (_needsCategoryFilter())
          SizedBox(width: 140, child: _buildCategoryDropdown(theme)),
        if (_needsAccountTypeFilter())
          SizedBox(width: 140, child: _buildAccountTypeDropdown(theme)),
      ],
    );
  }

  Widget _buildFilterChip(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600,
              ), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  // ── Load Button ──────────────────────────────────────────────

  Widget _buildLoadButton(ThemeData theme, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _loadReport,
        icon: _isLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.search, size: 20),
        label: Text(_isLoading ? 'جاري التحميل...' : 'عرض التقرير'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }

  // ── Results Area ─────────────────────────────────────────────

  Widget _buildResultsArea(ThemeData theme, bool isDark) {
    // No report selected yet
    if (_selectedReportKey == null || !_groups.any((g) => g.items.any((i) => i.key == _selectedReportKey))) {
      return _buildEmptyState(
        icon: Icons.description_outlined,
        title: 'اختر تقريراً للبدء',
        subtitle: 'اختر نوع التقرير من البطاقات أعلاه',
        color: AppColors.textHint,
      );
    }

    // Loading state with shimmer
    if (_isLoading) {
      return _buildShimmerLoading(theme, isDark);
    }

    // Report selected but not yet loaded
    if (!_hasData) {
      return _buildEmptyState(
        icon: Icons.filter_list_alt,
        title: 'حدد الفلاتر واضغط "عرض التقرير"',
        subtitle: 'اختر الفترة والعملة ثم اضغط العرض',
        color: AppColors.primary,
      );
    }

    // Loaded but no data
    if (_reportRows.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inbox_outlined,
        title: 'لا توجد بيانات',
        subtitle: 'جرّب تغيير الفلاتر أو اختيار فترة مختلفة',
        color: AppColors.warning,
      );
    }

    // Has data: KPI cards + search + sortable table
    return Column(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Summary Cards
        if (_reportTotals.isNotEmpty) ...[
          _buildKPICards(theme, isDark),
          const SizedBox(height: 12),
        ],
        // Search bar
        _buildSearchBar(theme, isDark),
        const SizedBox(height: 8),
        // Sortable data table
        _buildSortableDataTable(theme, isDark),
      ],
    );
  }

  // ── Empty / Illustration States ──────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: color,
            )),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(
              fontSize: 13, color: color.withOpacity(0.6),
            ), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Shimmer Loading ──────────────────────────────────────────

  Widget _buildShimmerLoading(ThemeData theme, bool isDark) {
    final baseColor = isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;
    final highlightColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return Column(
      children: [
        // KPI shimmer cards
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => _shimmerBox(baseColor, highlightColor, 140, 80),
          ),
        ),
        const SizedBox(height: 12),
        // Table shimmer rows
        ...List.generate(6, (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _shimmerBox(baseColor, highlightColor, double.infinity, 36),
        )),
      ],
    );
  }

  Widget _shimmerBox(Color base, Color highlight, double width, double height) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base.withOpacity(0.3 + value * 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
      onEnd: () {}, // Rebuild will restart animation via setState from loading
    );
  }

  // ── KPI Summary Cards ────────────────────────────────────────

  Widget _buildKPICards(ThemeData theme, bool isDark) {
    final entries = _reportTotals.entries
        .where((e) => e.key != 'العدد' && e.key != 'عدد الحسابات' &&
                      e.key != 'عدد الأصناف' && e.key != 'عدد العملاء' &&
                      e.key != 'عدد الصناديق' && e.key != 'العميل' && e.key != 'المورد')
        .take(4)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _buildKPICard(theme, isDark, entry.key, entry.value);
        },
      ),
    );
  }

  Widget _buildKPICard(ThemeData theme, bool isDark, String label, double value) {
    // Determine color based on label semantics
    Color cardColor;
    IconData cardIcon;
    if (label.contains('ربح') || label.contains('إيرادات') || label.contains('مبيعات') ||
        label.contains('البيع') || label.contains('الوارد')) {
      cardColor = value >= 0 ? AppColors.success : AppColors.error;
      cardIcon = value >= 0 ? Icons.trending_up : Icons.trending_down;
    } else if (label.contains('مشتريات') || label.contains('تكلفة') ||
               label.contains('مصروف') || label.contains('دين') || label.contains('متبقي') ||
               label.contains('الصادر') || label.contains('خسائر')) {
      cardColor = AppColors.error;
      cardIcon = Icons.trending_down;
    } else {
      cardColor = AppColors.primary;
      cardIcon = Icons.analytics_outlined;
    }

    final bgColor = cardColor.withOpacity(isDark ? 0.2 : 0.08);
    final borderColor = cardColor.withOpacity(isDark ? 0.4 : 0.3);

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(cardIcon, size: 16, color: cardColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label, style: theme.textTheme.labelSmall?.copyWith(
                  color: cardColor, fontWeight: FontWeight.w600, fontSize: 10,
                ), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _fmtMoney(value.abs()),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w900, color: cardColor, fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Search Bar ───────────────────────────────────────────────

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return TextField(
      onChanged: (val) => setState(() => _searchQuery = val),
      decoration: InputDecoration(
        hintText: 'بحث في النتائج...',
        hintStyle: TextStyle(color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(Icons.search, size: 20, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear, size: 18, color: AppColors.textHint),
                onPressed: () => setState(() => _searchQuery = ''),
              )
            : null,
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      style: theme.textTheme.bodyMedium,
    );
  }

  // ── Sortable Data Table ──────────────────────────────────────

  List<Map<String, dynamic>> get _filteredRows {
    if (_searchQuery.isEmpty) return _reportRows;
    final q = _searchQuery.toLowerCase();
    return _reportRows.where((row) {
      return row.values.any((v) => v.toString().toLowerCase().contains(q));
    }).toList();
  }

  List<Map<String, dynamic>> get _sortedRows {
    final rows = List<Map<String, dynamic>>.from(_filteredRows);
    if (_sortColumnIndex == null) return rows;
    final columns = rows.first.keys.toList();
    final sortCol = columns[_sortColumnIndex!];
    rows.sort((a, b) {
      final va = a[sortCol];
      final vb = b[sortCol];
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else {
        cmp = va.toString().compareTo(vb.toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  Widget _buildSortableDataTable(ThemeData theme, bool isDark) {
    final filteredRows = _filteredRows;
    if (filteredRows.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: 'لا توجد نتائج',
        subtitle: 'جرّب كلمة بحث مختلفة',
        color: AppColors.textHint,
      );
    }

    final columns = filteredRows.first.keys.toList();
    final sortedRows = _sortedRows;

    // Identify numeric columns
    final numericKeys = <String>{};
    for (final row in _reportRows) {
      for (final key in columns) {
        final v = row[key];
        if (v is double || v is int) numericKeys.add(key);
      }
    }

    final dateKeys = {'التاريخ', 'تاريخ الفتح', 'تاريخ الإغلاق'};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: DataTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: WidgetStateProperty.all(
              AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
            ),
            headingTextStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 11,
            ),
            dataTextStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            columnSpacing: 16,
            horizontalMargin: 12,
            columns: columns.asMap().entries.map((entry) {
              final idx = entry.key;
              final col = entry.value;
              return DataColumn(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(col, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (_sortColumnIndex == idx)
                      Icon(
                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14, color: AppColors.primary,
                      ),
                  ],
                ),
                numeric: numericKeys.contains(col),
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              );
            }).toList(),
            rows: sortedRows.map((row) {
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
                // Color negative values in red
                Color? textColor;
                if (v is double && v < 0 && numericKeys.contains(col) && !dateKeys.contains(col)) {
                  textColor = AppColors.error;
                }
                return DataCell(Text(
                  display,
                  style: textColor != null ? TextStyle(color: textColor) : null,
                  textAlign: numericKeys.contains(col) ? TextAlign.left : TextAlign.right,
                ));
              }).toList());
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Export FAB / PopupMenu ───────────────────────────────────

  Widget _buildExportFab(ThemeData theme, bool isDark) {
    return PopupMenuButton<String>(
      offset: const Offset(0, -80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      onSelected: (value) {
        switch (value) {
          case 'excel':
            _exportToExcel();
          case 'print':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('طباعة – قريباً'), backgroundColor: AppColors.info),
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.table_chart, size: 20, color: AppColors.success),
              const SizedBox(width: 8),
              Text('تصدير Excel', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('طباعة', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('تصدير', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_up, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
