import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../widgets/bar_chart_widget.dart';
import '../../../core/constants/app_constants.dart';

// ═══════════════════════════════════════════════════════════════════
//  Reports Screen – Redesigned
// ═══════════════════════════════════════════════════════════════════

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

// ── Report category & type definitions ──────────────────────────

enum ReportCategory {
  sales('المبيعات والمشتريات', Icons.swap_horiz, AppColors.primary),
  accounting('المحاسبة والمالية', Icons.account_balance, AppColors.info),
  inventory('المخزون', Icons.inventory_2, AppColors.success),
  debts('الديون', Icons.people, AppColors.warning),
  links('روابط سريعة', Icons.link, AppColors.secondary);

  final String label;
  final IconData icon;
  final Color color;
  const ReportCategory(this.label, this.icon, this.color);
}

enum ReportType {
  // Sales
  sales('المبيعات', ReportCategory.sales, Icons.trending_up, AppColors.success),
  purchases('المشتريات', ReportCategory.sales, Icons.shopping_cart, AppColors.error),
  profitLoss('الأرباح والخسائر', ReportCategory.sales, Icons.assessment, AppColors.primary),
  invoiceProfit('ربح الفواتير', ReportCategory.sales, Icons.receipt_long, AppColors.secondary),
  // Accounting
  accountMovement('حركة حساب', ReportCategory.accounting, Icons.swap_horiz, AppColors.info),
  allAccountMovement('حركة جميع الحسابات', ReportCategory.accounting, Icons.view_list, AppColors.info),
  trialBalance('ميزان المراجعة', ReportCategory.accounting, Icons.balance, AppColors.primary),
  cashBox('حركة الصندوق', ReportCategory.accounting, Icons.account_balance_wallet, AppColors.success),
  accountsNoMovement('حسابات بدون حركة', ReportCategory.accounting, Icons.block, AppColors.textHint),
  // Inventory
  inventory('المخزون', ReportCategory.inventory, Icons.inventory_2, AppColors.success),
  inventoryMovement('حركة المخزون', ReportCategory.inventory, Icons.swap_vert, AppColors.primary),
  inventoryCost('تكلفة المخزون', ReportCategory.inventory, Icons.attach_money, AppColors.warning),
  // Debts
  customerDebts('ديون العملاء', ReportCategory.debts, Icons.people, AppColors.warning),
  supplierDebts('ديون الموردين', ReportCategory.debts, Icons.local_shipping, AppColors.error),
  // Links
  dailyOps('العمليات اليومية', ReportCategory.links, Icons.today, AppColors.primary),
  inventoryVoucher('سند الجرد', ReportCategory.links, Icons.assignment, AppColors.info),
  annualPosting('الترحيل السنوي', ReportCategory.links, Icons.calendar_today, AppColors.secondary);

  final String label;
  final ReportCategory category;
  final IconData icon;
  final Color color;
  const ReportType(this.label, this.category, this.icon, this.color);
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  ReportType _selectedReport = ReportType.sales;
  String _selectedCurrency = 'الكل';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _selectedAccountId;
  String _selectedAccountType = 'الكل';
  bool _isLoading = false;

  // ── Report data ──
  double _totalRevenue = 0;
  double _totalPurchases = 0;
  double _totalOperatingExpenses = 0;
  double _netProfit = 0;
  double _grossProfit = 0;
  int _invoiceCount = 0;
  List<BarData> _dailySalesData = [];
  List<_TopProduct> _topProducts = [];
  List<_RecentInvoice> _recentInvoices = [];
  List<_AccountMovement> _accountMovements = [];
  List<_AllAccountMovement> _allAccountMovements = [];
  List<_TrialBalanceItem> _trialBalanceItems = [];
  double _totalDebit = 0;
  double _totalCredit = 0;
  List<_DebtItem> _debtItems = [];
  List<_CashBoxMovement> _cashBoxMovements = [];
  List<_InventoryItem> _inventoryItems = [];
  List<Map<String, dynamic>> _accountsWithoutMovements = [];
  List<Map<String, dynamic>> _invoiceProfitItems = [];
  List<Map<String, dynamic>> _inventoryMovementItems = [];
  List<Map<String, dynamic>> _inventoryCostItems = [];

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
    _tabController = TabController(length: 2, vsync: this);
    _loadSelectedReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _currencyCode() {
    switch (_selectedCurrency) {
      case 'ر.ي': return 'YER';
      case 'ر.س': return 'SAR';
      case r'$': return 'USD';
      default: return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Data Loading – Only load data for the selected report type
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadSelectedReport() async {
    setState(() => _isLoading = true);
    try {
      switch (_selectedReport) {
        case ReportType.sales:
        case ReportType.purchases:
          await _loadSalesData();
          break;
        case ReportType.profitLoss:
          await _loadProfitLossData();
          break;
        case ReportType.invoiceProfit:
          await _loadInvoiceProfitData();
          break;
        case ReportType.accountMovement:
          await _loadAccountMovementData();
          break;
        case ReportType.allAccountMovement:
          await _loadAllAccountMovementData();
          break;
        case ReportType.trialBalance:
          await _loadTrialBalanceData();
          break;
        case ReportType.cashBox:
          await _loadCashBoxData();
          break;
        case ReportType.accountsNoMovement:
          await _loadAccountsWithoutMovementData();
          break;
        case ReportType.inventory:
          await _loadInventoryData();
          break;
        case ReportType.inventoryMovement:
          await _loadInventoryMovementData();
          break;
        case ReportType.inventoryCost:
          await _loadInventoryCostData();
          break;
        case ReportType.customerDebts:
        case ReportType.supplierDebts:
          await _loadDebtData();
          break;
        case ReportType.dailyOps:
        case ReportType.inventoryVoucher:
        case ReportType.annualPosting:
          break; // Links – no data to load
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقرير: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _dateFilter({String column = 'created_at'}) {
    String f = '';
    if (_dateFrom != null) f += ' AND $column >= ?';
    if (_dateTo != null) f += ' AND $column < ?';
    return f;
  }

  List<dynamic> _dateArgs({bool addDay = false}) {
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

  Future<void> _loadSalesData() async {
    final db = await DatabaseHelper().database;
    final allArgs = [..._dateArgs(), ..._currencyArgs()];
    final df = _dateFilter();
    final cf = _currencyFilter();

    // Revenue
    final revRes = await db.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type IN ('sale','pos') AND is_return=0$df$cf", allArgs);
    _totalRevenue = (revRes.first['t'] as num?)?.toDouble() ?? 0;

    // Purchases
    final purRes = await db.rawQuery(
      "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type='purchase' AND is_return=0$df$cf", allArgs);
    _totalPurchases = (purRes.first['t'] as num?)?.toDouble() ?? 0;

    // Operating expenses
    final expRes = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE 1=1${_dateFilter(column: 'expense_date')}$cf",
      [..._dateArgs(), ..._currencyArgs()]);
    _totalOperatingExpenses = (expRes.first['t'] as num?)?.toDouble() ?? 0;

    _grossProfit = _totalRevenue - _totalPurchases;
    _netProfit = _grossProfit - _totalOperatingExpenses;

    // Invoice count
    final cntRes = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM invoices WHERE is_return=0$df$cf", allArgs);
    _invoiceCount = (cntRes.first['c'] as num?)?.toInt() ?? 0;

    // Daily sales chart (last 7 days)
    final now = DateTime.now();
    const dayLabels = ['السبت','الأحد','الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة'];
    _dailySalesData = [];
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final dayRes = await db.rawQuery(
        "SELECT COALESCE(SUM(total),0) AS t FROM invoices WHERE type IN ('sale','pos') AND is_return=0 AND created_at>=? AND created_at<?",
        [dayStart.toIso8601String(), dayEnd.toIso8601String()]);
      final dayTotal = (dayRes.first['t'] as num?)?.toDouble() ?? 0;
      int labelIndex;
      if (date.weekday == 6) labelIndex = 0;
      else if (date.weekday == 7) labelIndex = 1;
      else labelIndex = date.weekday + 1;
      _dailySalesData.add(BarData(label: dayLabels[labelIndex], value: dayTotal));
    }

    // Top products
    final topRes = await db.rawQuery(
      "SELECT ii.product_id, ii.product_name, SUM(ii.quantity) AS tq, SUM(ii.total_price) AS tr "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id=i.id "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0 "
      "GROUP BY ii.product_id ORDER BY tq DESC LIMIT 10");
    _topProducts = topRes.map((r) => _TopProduct(
      name: r['product_name'] as String? ?? 'غير معروف',
      quantity: (r['tq'] as num?)?.toInt() ?? 0,
      revenue: (r['tr'] as num?)?.toDouble() ?? 0,
    )).toList();

    // Recent invoices
    final recRes = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.is_return, i.created_at, i.currency, "
      "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name,'بدون عميل') "
      "WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name,'بدون مورد') "
      "ELSE 'بدون عميل' END AS entity_name "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id=c.id "
      "LEFT JOIN suppliers s ON i.supplier_id=s.id "
      "ORDER BY i.created_at DESC LIMIT 20");
    _recentInvoices = recRes.map((r) {
      final type = r['type'] as String? ?? 'sale';
      final isRet = (r['is_return'] as int?) == 1;
      return _RecentInvoice(
        id: r['id'] as String? ?? '',
        title: type == 'sale' || type == 'pos'
            ? (isRet ? 'مرتجع مبيعات' : 'فاتورة مبيعات')
            : (isRet ? 'مرتجع مشتريات' : 'فاتورة مشتريات'),
        subtitle: r['entity_name'] as String? ?? '',
        date: r['created_at'] as String? ?? '',
        total: (r['total'] as num?)?.toDouble() ?? 0,
        currency: r['currency'] as String? ?? 'YER',
        icon: type == 'sale' || type == 'pos'
            ? (isRet ? Icons.undo : Icons.receipt_long_outlined)
            : (isRet ? Icons.undo : Icons.shopping_cart_outlined),
        color: type == 'sale' || type == 'pos'
            ? (isRet ? AppColors.warning : AppColors.success)
            : (isRet ? AppColors.warning : AppColors.error),
      );
    }).toList();
  }

  Future<void> _loadProfitLossData() async {
    await _loadSalesData(); // Same data needed
  }

  Future<void> _loadInvoiceProfitData() async {
    final dbHelper = DatabaseHelper();
    _invoiceProfitItems = await dbHelper.getInvoiceProfitReport(
      startDate: _dateFrom, endDate: _dateTo);
  }

  Future<void> _loadAccountMovementData() async {
    if (_selectedAccountId == null) { _accountMovements = []; return; }
    final dbHelper = DatabaseHelper();
    final transactions = await dbHelper.getAccountTransactions(_selectedAccountId!);
    double running = 0;
    _accountMovements = transactions.map((tx) {
      final debit = (tx['debit'] as num?)?.toDouble() ?? 0;
      final credit = (tx['credit'] as num?)?.toDouble() ?? 0;
      running += (debit - credit);
      return _AccountMovement(
        date: tx['date'] as String? ?? '',
        description: tx['description'] as String? ?? '',
        debit: debit, credit: credit, balance: running,
      );
    }).toList();
  }

  Future<void> _loadAllAccountMovementData() async {
    final db = await DatabaseHelper().database;
    final args = [..._dateArgs()];
    String cf = '';
    if (_currencyCode() != null) { cf = ' AND a.currency = ?'; args.add(_currencyCode()!); }
    final allTx = await db.rawQuery(
      "SELECT t.id, t.account_id, t.debit, t.credit, t.description, t.date, t.created_at, "
      "a.name_ar AS account_name, a.account_code, a.currency "
      "FROM transactions t LEFT JOIN accounts a ON t.account_id=a.id "
      "WHERE 1=1${_dateFilter(column: 't.created_at')}$cf "
      "ORDER BY t.date DESC, t.created_at DESC", args);
    _allAccountMovements = allTx.map((tx) => _AllAccountMovement(
      date: tx['date'] as String? ?? '',
      accountName: tx['account_name'] as String? ?? 'غير معروف',
      accountCode: tx['account_code'] as String? ?? '',
      currency: tx['currency'] as String? ?? 'YER',
      description: tx['description'] as String? ?? '',
      debit: (tx['debit'] as num?)?.toDouble() ?? 0,
      credit: (tx['credit'] as num?)?.toDouble() ?? 0,
    )).toList();
  }

  Future<void> _loadTrialBalanceData() async {
    final dbHelper = DatabaseHelper();
    final accounts = await dbHelper.getAllAccounts();
    final cc = _currencyCode();
    _trialBalanceItems = [];
    _totalDebit = 0;
    _totalCredit = 0;
    for (final account in accounts) {
      if (cc != null && account['currency'] != cc) continue;
      final accountId = account['id'] as int;
      final balance = await dbHelper.getAccountBalance(accountId);
      if (balance == 0.0) continue;
      final isDebit = balance > 0;
      if (isDebit) _totalDebit += balance.abs();
      else _totalCredit += balance.abs();
      _trialBalanceItems.add(_TrialBalanceItem(
        accountId: accountId,
        accountName: account['name_ar'] as String? ?? '',
        accountCode: account['account_code'] as String? ?? '',
        accountType: account['account_type'] as String? ?? '',
        currency: account['currency'] as String? ?? 'YER',
        debit: isDebit ? balance.abs() : 0,
        credit: isDebit ? 0 : balance.abs(),
      ));
    }
  }

  Future<void> _loadCashBoxData() async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final cashBoxes = await dbHelper.getAllCashBoxes();
    final cc = _currencyCode();
    _cashBoxMovements = [];
    for (final cb in cashBoxes) {
      if (cc != null && cb['currency'] != cc) continue;
      final cbId = cb['id'] as int;
      final invRes = await db.rawQuery(
        "SELECT type, COUNT(*) as cnt, COALESCE(SUM(total),0) as total "
        "FROM invoices WHERE cash_box_id=? AND is_return=0${_dateFilter()}${_currencyFilter()} "
        "GROUP BY type", [cbId, ..._dateArgs(), ..._currencyArgs()]);
      double salesTotal = 0; int salesCount = 0;
      double purchaseTotal = 0; int purchaseCount = 0;
      for (final inv in invRes) {
        final t = inv['type'] as String? ?? '';
        final tot = (inv['total'] as num?)?.toDouble() ?? 0;
        final cnt = (inv['cnt'] as num?)?.toInt() ?? 0;
        if (t == 'sale' || t == 'pos') { salesTotal = tot; salesCount = cnt; }
        else if (t == 'purchase') { purchaseTotal = tot; purchaseCount = cnt; }
      }
      final trIn = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS t, COUNT(*) AS c FROM cash_transfers WHERE to_cash_box_id=?${_dateFilter()}",
        [cbId, ..._dateArgs()]);
      final trOut = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS t, COUNT(*) AS c FROM cash_transfers WHERE from_cash_box_id=?${_dateFilter()}",
        [cbId, ..._dateArgs()]);
      final exIn = await db.rawQuery(
        "SELECT COALESCE(SUM(to_amount),0) AS t, COUNT(*) AS c FROM currency_exchanges WHERE to_cash_box_id=?${_dateFilter()}",
        [cbId, ..._dateArgs()]);
      final exOut = await db.rawQuery(
        "SELECT COALESCE(SUM(from_amount),0) AS t, COUNT(*) AS c FROM currency_exchanges WHERE from_cash_box_id=?${_dateFilter()}",
        [cbId, ..._dateArgs()]);
      _cashBoxMovements.add(_CashBoxMovement(
        id: cbId, name: cb['name'] as String? ?? '',
        type: cb['type'] as String? ?? 'cash_box',
        balance: (cb['balance'] as num?)?.toDouble() ?? 0,
        balanceType: cb['balance_type'] as String? ?? 'credit',
        currency: cb['currency'] as String? ?? 'YER',
        salesTotal: salesTotal, salesCount: salesCount,
        purchaseTotal: purchaseTotal, purchaseCount: purchaseCount,
        transfersInTotal: (trIn.first['t'] as num?)?.toDouble() ?? 0,
        transfersInCount: (trIn.first['c'] as num?)?.toInt() ?? 0,
        transfersOutTotal: (trOut.first['t'] as num?)?.toDouble() ?? 0,
        transfersOutCount: (trOut.first['c'] as num?)?.toInt() ?? 0,
        exchangesInTotal: (exIn.first['t'] as num?)?.toDouble() ?? 0,
        exchangesInCount: (exIn.first['c'] as num?)?.toInt() ?? 0,
        exchangesOutTotal: (exOut.first['t'] as num?)?.toDouble() ?? 0,
        exchangesOutCount: (exOut.first['c'] as num?)?.toInt() ?? 0,
      ));
    }
  }

  Future<void> _loadAccountsWithoutMovementData() async {
    _accountsWithoutMovements = await DatabaseHelper().getAccountsWithoutMovements();
  }

  Future<void> _loadInventoryData() async {
    final db = await DatabaseHelper().database;
    final prodRes = await db.rawQuery(
      "SELECT p.id, p.name_ar, p.barcode, p.item_code, p.current_stock, "
      "p.cost_price, p.sell_price, p.min_stock, p.warehouse_id, "
      "w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1 ORDER BY p.current_stock DESC");
    _inventoryItems = prodRes.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final minStock = (p['min_stock'] as num?)?.toDouble() ?? 0;
      return _InventoryItem(
        id: p['id'] as int, name: p['name_ar'] as String? ?? '',
        barcode: p['barcode'] as String?, itemCode: p['item_code'] as String?,
        currentStock: stock,
        costPrice: (p['cost_price'] as num?)?.toDouble() ?? 0,
        sellPrice: (p['sell_price'] as num?)?.toDouble() ?? 0,
        minStock: minStock,
        warehouseName: p['warehouse_name'] as String?,
        categoryName: p['category_name'] as String?,
        isLowStock: stock > 0 && stock <= minStock,
        isOutOfStock: stock <= 0,
      );
    }).toList();
  }

  Future<void> _loadInventoryMovementData() async {
    _inventoryMovementItems = await DatabaseHelper().getInventoryMovementReport(
      startDate: _dateFrom, endDate: _dateTo);
  }

  Future<void> _loadInventoryCostData() async {
    _inventoryCostItems = await DatabaseHelper().getInventoryCostReport();
  }

  Future<void> _loadDebtData() async {
    final dbHelper = DatabaseHelper();
    _debtItems = [];
    if (_selectedReport == ReportType.customerDebts) {
      final customers = await dbHelper.getAllCustomers();
      for (final c in customers) {
        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
        if (balance > 0) _debtItems.add(_DebtItem(
          name: c['name'] as String? ?? '', balance: balance,
          balanceType: c['balance_type'] as String? ?? 'credit',
          currency: c['currency'] as String? ?? 'YER',
          phone: c['phone'] as String?,
        ));
      }
    } else {
      final suppliers = await dbHelper.getAllSuppliers();
      for (final s in suppliers) {
        final balance = (s['balance'] as num?)?.toDouble() ?? 0;
        if (balance > 0) _debtItems.add(_DebtItem(
          name: s['name'] as String? ?? '', balance: balance,
          balanceType: s['balance_type'] as String? ?? 'debit',
          currency: s['currency'] as String? ?? 'YER',
          phone: s['phone'] as String?,
        ));
      }
    }
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
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'التقارير', icon: Icon(Icons.bar_chart, size: 20)),
              Tab(text: 'حركة الحسابات', icon: Icon(Icons.swap_horiz, size: 20)),
            ],
          ),
          actions: [
            if (_selectedReport.category != ReportCategory.links)
              IconButton(
                icon: const Icon(Icons.file_download),
                tooltip: 'تصدير Excel',
                onPressed: _exportToExcel,
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () { setState(() => _isLoading = true); _loadSelectedReport(); },
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildReportsTab(theme, isDark),
            _buildAccountMovementsTab(theme, isDark),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Reports Tab
  // ══════════════════════════════════════════════════════════════

  Widget _buildReportsTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 24),
      child: Column(
        children: [
          // Category & Report Selector
          _buildReportSelector(theme, isDark),
          const SizedBox(height: 8),
          // Filters
          _buildFilterBar(theme, isDark),
          const SizedBox(height: 12),
          // Content
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator())
          else
            _buildReportContent(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildReportSelector(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اختر التقرير', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // Category chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReportCategory.values.map((cat) {
              final isSelected = _selectedReport.category == cat;
              return ChoiceChip(
                avatar: Icon(cat.icon, size: 16, color: isSelected ? Colors.white : cat.color),
                label: Text(cat.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : null)),
                selected: isSelected,
                selectedColor: cat.color,
                onSelected: (_) {
                  // Switch to first report in this category
                  final first = ReportType.values.firstWhere((r) => r.category == cat);
                  setState(() { _selectedReport = first; });
                  _loadSelectedReport();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Report type dropdown within category
          DropdownButtonFormField<ReportType>(
            value: _selectedReport,
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: Icon(_selectedReport.icon, size: 20, color: _selectedReport.color),
            ),
            items: ReportType.values
                .where((r) => r.category == _selectedReport.category)
                .map((r) => DropdownMenuItem(
              value: r,
              child: Row(children: [
                Icon(r.icon, size: 18, color: r.color),
                const SizedBox(width: 8),
                Text(r.label, style: const TextStyle(fontSize: 13)),
              ]),
            )).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() { _selectedReport = val; });
                _loadSelectedReport();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Date from
          Expanded(
            child: InkWell(
              onTap: _pickDateFrom,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Flexible(child: Text(
                    _dateFrom != null ? DateFormatter.formatDate(_dateFrom!) : 'من',
                    style: theme.textTheme.bodySmall?.copyWith(color: _dateFrom != null ? null : AppColors.textHint),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.divider),
          // Date to
          Expanded(
            child: InkWell(
              onTap: _pickDateTo,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Flexible(child: Text(
                    _dateTo != null ? DateFormatter.formatDate(_dateTo!) : 'إلى',
                    style: theme.textTheme.bodySmall?.copyWith(color: _dateTo != null ? null : AppColors.textHint),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.divider),
          // Currency
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCurrency,
                  isDense: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  style: theme.textTheme.bodySmall,
                  items: _currencyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() { _selectedCurrency = val; });
                      _loadSelectedReport();
                    }
                  },
                ),
              ),
            ),
          ),
          // Clear filters
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
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Report Content Router
  // ══════════════════════════════════════════════════════════════

  Widget _buildReportContent(ThemeData theme, bool isDark) {
    switch (_selectedReport) {
      case ReportType.sales: return _buildSalesReport(theme, isDark);
      case ReportType.purchases: return _buildPurchasesReport(theme, isDark);
      case ReportType.profitLoss: return _buildProfitLossReport(theme, isDark);
      case ReportType.invoiceProfit: return _buildInvoiceProfitReport(theme, isDark);
      case ReportType.accountMovement: return _buildAccountMovementReport(theme, isDark);
      case ReportType.allAccountMovement: return _buildAllAccountMovementReport(theme, isDark);
      case ReportType.trialBalance: return _buildTrialBalanceReport(theme, isDark);
      case ReportType.cashBox: return _buildCashBoxReport(theme, isDark);
      case ReportType.accountsNoMovement: return _buildAccountsWithoutMovementsReport(theme, isDark);
      case ReportType.inventory: return _buildInventoryReport(theme, isDark);
      case ReportType.inventoryMovement: return _buildInventoryMovementReport(theme, isDark);
      case ReportType.inventoryCost: return _buildInventoryCostReport(theme, isDark);
      case ReportType.customerDebts:
      case ReportType.supplierDebts: return _buildDebtReport(theme, isDark);
      case ReportType.dailyOps: return _buildLinkCard(theme, 'العمليات اليومية', Icons.today, '/daily-operations');
      case ReportType.inventoryVoucher: return _buildLinkCard(theme, 'سند الجرد', Icons.assignment, '/vouchers/inventory');
      case ReportType.annualPosting: return _buildLinkCard(theme, 'الترحيل السنوي', Icons.calendar_today, AppConstants.annualPosting);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Individual Report Builders
  // ══════════════════════════════════════════════════════════════

  // ── Sales Report ──
  Widget _buildSalesReport(ThemeData theme, bool isDark) {
    return Column(children: [
      _buildSummaryRow(theme, isDark),
      const SizedBox(height: 16),
      if (_dailySalesData.isNotEmpty) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BarChartWidget(data: _dailySalesData, title: 'المبيعات اليومية (آخر 7 أيام)', barColor: AppColors.primary, height: 240),
      ),
      const SizedBox(height: 16),
      _buildTopProductsSection(theme, isDark),
      const SizedBox(height: 16),
      _buildRecentInvoicesSection(theme, isDark),
    ]);
  }

  Widget _buildSummaryRow(ThemeData theme, bool isDark) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final items = [
            ('إجمالي الإيرادات', _totalRevenue, AppColors.success, Icons.trending_up),
            ('إجمالي المصروفات', _totalPurchases + _totalOperatingExpenses, AppColors.error, Icons.trending_down),
            ('صافي الربح', _netProfit, _netProfit >= 0 ? AppColors.primary : AppColors.error, Icons.attach_money),
            ('عدد الفواتير', _invoiceCount.toDouble(), AppColors.info, Icons.receipt),
          ];
          final (title, value, color, icon) = items[i];
          return Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Expanded(child: Text(title, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                Text(
                  i == 3 ? value.toInt().toString() : CurrencyFormatter.formatCompactWithSymbol(value),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopProductsSection(ThemeData theme, bool isDark) {
    if (_topProducts.isEmpty) return const SizedBox.shrink();
    final maxQty = _topProducts.first.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('المنتجات الأكثر مبيعاً', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
          ),
          child: Column(children: _topProducts.asMap().entries.map((e) {
            final p = e.value;
            final progress = maxQty == 0 ? 0.0 : p.quantity / maxQty;
            final isLast = e.key == _topProducts.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Column(children: [
                Row(children: [
                  Container(width: 24, height: 24, decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Center(child: Text('${e.key+1}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${p.quantity} قطعة', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  Text(CurrencyFormatter.formatCompactWithSymbol(p.revenue), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ]),
                if (!isLast) const SizedBox(height: 8),
                if (!isLast) ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: AppColors.surfaceVariant, valueColor: AlwaysStoppedAnimation(AppColors.primary.withValues(alpha: 0.6))),
                ),
              ]),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _buildRecentInvoicesSection(ThemeData theme, bool isDark) {
    if (_recentInvoices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('آخر الفواتير', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._recentInvoices.take(10).map((inv) => Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: inv.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(inv.icon, size: 18, color: inv.color),
            ),
            title: Text(inv.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(inv.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(CurrencyFormatter.format(inv.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(_formatDateShort(inv.date), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── Purchases Report ──
  Widget _buildPurchasesReport(ThemeData theme, bool isDark) {
    final purchaseInvoices = _recentInvoices.where((i) => i.title.contains('مشتريات') && !i.title.contains('مرتجع')).toList();
    return Column(children: [
      _buildSummaryRow(theme, isDark),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shopping_cart, color: AppColors.error, size: 22),
          const SizedBox(width: 8),
          Text('فواتير المشتريات', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        if (purchaseInvoices.isEmpty)
          _buildEmptyState(theme, Icons.shopping_cart, 'لا توجد فواتير مشتريات')
        else
          ...purchaseInvoices.map((inv) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.shopping_cart, size: 18, color: AppColors.error)),
              title: Text(inv.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(inv.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(CurrencyFormatter.format(inv.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(_formatDateShort(inv.date), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
              ]),
            ),
          )),
      ])),
    ]);
  }

  // ── Profit & Loss Report ──
  Widget _buildProfitLossReport(ThemeData theme, bool isDark) {
    final profitPercent = _totalRevenue > 0 ? (_netProfit / _totalRevenue * 100) : 0.0;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _netProfit >= 0
              ? [AppColors.success.withValues(alpha: 0.1), AppColors.success.withValues(alpha: 0.05)]
              : [AppColors.error.withValues(alpha: 0.1), AppColors.error.withValues(alpha: 0.05)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Icon(_netProfit >= 0 ? Icons.trending_up : Icons.trending_down, size: 48, color: _netProfit >= 0 ? AppColors.success : AppColors.error),
          const SizedBox(height: 12),
          Text(_netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(CurrencyFormatter.formatWithSymbol(_netProfit.abs()),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: _netProfit >= 0 ? AppColors.success : AppColors.error)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('هامش الربح الصافي: ${profitPercent.toStringAsFixed(1)}%',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: _netProfit >= 0 ? AppColors.success : AppColors.error)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _buildPLRow(theme, 'إجمالي الإيرادات (المبيعات)', _totalRevenue, AppColors.success, Icons.arrow_outward),
      const SizedBox(height: 8),
      _buildPLRow(theme, 'تكلفة المشتريات', _totalPurchases, AppColors.error, Icons.south_east),
      const SizedBox(height: 8),
      _buildPLRow(theme, 'ربح إجمالي', _grossProfit, _grossProfit >= 0 ? AppColors.success : AppColors.error, _grossProfit >= 0 ? Icons.trending_up : Icons.trending_down),
      const SizedBox(height: 8),
      _buildPLRow(theme, 'المصاريف التشغيلية', _totalOperatingExpenses, AppColors.warning, Icons.remove),
    ]));
  }

  Widget _buildPLRow(ThemeData theme, String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        Text(CurrencyFormatter.formatWithSymbol(value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  // ── Invoice Profit Report ──
  Widget _buildInvoiceProfitReport(ThemeData theme, bool isDark) {
    if (_invoiceProfitItems.isEmpty) return _buildEmptyState(theme, Icons.receipt_long, 'لا توجد بيانات أرباح');
    double totalProfit = 0;
    for (final item in _invoiceProfitItems) {
      totalProfit += (item['profit'] as num?)?.toDouble() ?? 0;
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.08), AppColors.secondary.withValues(alpha: 0.08)]),
          borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(Icons.receipt_long, size: 32, color: AppColors.primary),
          const SizedBox(height: 8),
          Text('إجمالي أرباح الفواتير', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.formatWithSymbol(totalProfit), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
          Text('${_invoiceProfitItems.length} فاتورة', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
        ]),
      ),
      const SizedBox(height: 16),
      ..._invoiceProfitItems.map((item) {
        final profit = (item['profit'] as num?)?.toDouble() ?? 0;
        final total = (item['total'] as num?)?.toDouble() ?? 0;
        final cost = (item['total_cost'] as num?)?.toDouble() ?? 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(width: 38, height: 38, decoration: BoxDecoration(
              color: (profit >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(profit >= 0 ? Icons.trending_up : Icons.trending_down, size: 18, color: profit >= 0 ? AppColors.success : AppColors.error)),
            title: Text(item['invoice_id']?.toString().substring(0, (item['invoice_id']?.toString().length ?? 8).clamp(1, 12)) ?? 'فاتورة',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('إجمالي: ${CurrencyFormatter.format(total)} | تكلفة: ${CurrencyFormatter.format(cost)}',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
            trailing: Text(CurrencyFormatter.format(profit),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: profit >= 0 ? AppColors.success : AppColors.error)),
          ),
        );
      }),
    ]));
  }

  // ── Account Movement Report ──
  Widget _buildAccountMovementReport(ThemeData theme, bool isDark) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper().getAllAccounts(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          var filteredAccounts = snap.data!;
          if (_selectedAccountType != 'الكل') {
            final typeCode = _accountTypes.firstWhere((e) => e.key == _selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
            if (typeCode != 'الكل') filteredAccounts = filteredAccounts.where((a) => a['account_type'] == typeCode).toList();
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 36, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _accountTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_accountTypes[i].key, style: const TextStyle(fontSize: 12)),
                selected: _selectedAccountType == _accountTypes[i].key,
                onSelected: (_) => setState(() { _selectedAccountType = _accountTypes[i].key; }),
              ),
            )),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _selectedAccountId,
              decoration: InputDecoration(
                filled: true, fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
              ),
              items: filteredAccounts.map((acc) => DropdownMenuItem<int>(
                value: acc['id'] as int,
                child: Text("${acc['name_ar']} (${acc['currency']})", style: const TextStyle(fontSize: 13)),
              )).toList(),
              onChanged: (val) { setState(() { _selectedAccountId = val; }); _loadSelectedReport(); },
            ),
          ]);
        },
      ),
      const SizedBox(height: 16),
      if (_accountMovements.isNotEmpty) ...[
        _buildTableHeader(theme, ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'], [2, 3, 2, 2, 2]),
        ..._accountMovements.asMap().entries.map((e) => _buildTableRow(theme, isDark, e.key, [
          _formatDateShort(e.value.date),
          e.value.description,
          e.value.debit > 0 ? CurrencyFormatter.format(e.value.debit) : '-',
          e.value.credit > 0 ? CurrencyFormatter.format(e.value.credit) : '-',
          CurrencyFormatter.format(e.value.balance),
        ], [2, 3, 2, 2, 2], debitIndex: 2, creditIndex: 3, balanceValue: e.value.balance)),
      ] else
        _buildEmptyState(theme, Icons.swap_horiz, 'اختر حساباً لعرض حركته'),
    ]));
  }

  // ── All Account Movement Report ──
  Widget _buildAllAccountMovementReport(ThemeData theme, bool isDark) {
    if (_allAccountMovements.isEmpty) return _buildEmptyState(theme, Icons.swap_horiz, 'لا توجد حركات');
    final totalDebit = _allAccountMovements.fold(0.0, (s, m) => s + m.debit);
    final totalCredit = _allAccountMovements.fold(0.0, (s, m) => s + m.credit);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildTotalSummaryRow(theme, [
        _SummaryItem(title: 'إجمالي المدين', value: totalDebit, color: AppColors.error),
        _SummaryItem(title: 'إجمالي الدائن', value: totalCredit, color: AppColors.success),
        _SummaryItem(title: 'عدد الحركات', value: _allAccountMovements.length.toDouble(), color: AppColors.primary, isCount: true),
      ]),
      const SizedBox(height: 12),
      _buildTableHeader(theme, ['التاريخ', 'الحساب', 'البيان', 'مدين', 'دائن'], [2, 3, 3, 2, 2]),
      ..._allAccountMovements.asMap().entries.map((e) => _buildTableRow(theme, isDark, e.key, [
        _formatDateShort(e.value.date),
        '${e.value.accountName} (${e.value.currency})',
        e.value.description,
        e.value.debit > 0 ? CurrencyFormatter.format(e.value.debit) : '-',
        e.value.credit > 0 ? CurrencyFormatter.format(e.value.credit) : '-',
      ], [2, 3, 3, 2, 2], debitIndex: 3, creditIndex: 4)),
    ]));
  }

  // ── Trial Balance Report ──
  Widget _buildTrialBalanceReport(ThemeData theme, bool isDark) {
    if (_trialBalanceItems.isEmpty) return _buildEmptyState(theme, Icons.balance, 'لا توجد أرصدة');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildTotalSummaryRow(theme, [
        _SummaryItem(title: 'إجمالي المدين', value: _totalDebit, color: AppColors.error),
        _SummaryItem(title: 'إجمالي الدائن', value: _totalCredit, color: AppColors.success),
        _SummaryItem(title: 'الفرق', value: (_totalDebit - _totalCredit).abs(), color: AppColors.warning),
      ]),
      const SizedBox(height: 12),
      SizedBox(height: 36, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _accountTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ChoiceChip(
          label: Text(_accountTypes[i].key, style: const TextStyle(fontSize: 12)),
          selected: _selectedAccountType == _accountTypes[i].key,
          onSelected: (_) => setState(() { _selectedAccountType = _accountTypes[i].key; }),
        ),
      )),
      const SizedBox(height: 12),
      _buildTableHeader(theme, ['الكود', 'الحساب', 'العملة', 'مدين', 'دائن'], [1, 3, 1, 2, 2]),
      ..._getFilteredTrialItems().map((item) => _buildTableRow(theme, isDark, _trialBalanceItems.indexOf(item), [
        item.accountCode, item.accountName, item.currency,
        item.debit > 0 ? CurrencyFormatter.format(item.debit) : '-',
        item.credit > 0 ? CurrencyFormatter.format(item.credit) : '-',
      ], [1, 3, 1, 2, 2], debitIndex: 3, creditIndex: 4)),
      // Totals row
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          border: Border(top: BorderSide(width: 2, color: AppColors.primary))),
        child: Row(children: [
          Expanded(flex: 5, child: Text('الإجمالي', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary))),
          Expanded(flex: 2, child: Text(CurrencyFormatter.format(_totalDebit), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(CurrencyFormatter.format(_totalCredit), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success), textAlign: TextAlign.center)),
        ]),
      ),
    ]));
  }

  List<_TrialBalanceItem> _getFilteredTrialItems() {
    if (_selectedAccountType == 'الكل') return _trialBalanceItems;
    final typeCode = _accountTypes.firstWhere((e) => e.key == _selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
    if (typeCode == 'الكل') return _trialBalanceItems;
    return _trialBalanceItems.where((i) => i.accountType == typeCode).toList();
  }

  // ── Cash Box Report ──
  Widget _buildCashBoxReport(ThemeData theme, bool isDark) {
    if (_cashBoxMovements.isEmpty) return _buildEmptyState(theme, Icons.account_balance_wallet, 'لا توجد صناديق');
    final totalBalance = _cashBoxMovements.fold(0.0, (s, m) => s + (m.balanceType == 'credit' ? m.balance : -m.balance));
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.08), AppColors.secondary.withValues(alpha: 0.08)]),
          borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(Icons.account_balance_wallet, size: 36, color: AppColors.primary),
          const SizedBox(height: 8),
          Text('إجمالي الأرصدة', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.formatWithSymbol(totalBalance.abs()), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
          Text(totalBalance >= 0 ? 'له' : 'عليه', style: theme.textTheme.bodySmall?.copyWith(color: totalBalance >= 0 ? AppColors.success : AppColors.error, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(height: 16),
      ..._cashBoxMovements.map((cb) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(
              color: (cb.type == 'bank' ? AppColors.info : AppColors.primary).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(cb.type == 'bank' ? Icons.account_balance : Icons.account_balance_wallet, color: cb.type == 'bank' ? AppColors.info : AppColors.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cb.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('${cb.type == 'bank' ? 'بنك' : 'صندوق'} - ${cb.currency}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(CurrencyFormatter.format(cb.balance), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(cb.balanceType == 'credit' ? 'له' : 'عليه', style: theme.textTheme.bodySmall?.copyWith(color: cb.balanceType == 'credit' ? AppColors.success : AppColors.error, fontWeight: FontWeight.w600)),
            ]),
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: _buildStatMini(theme, 'المبيعات', cb.salesTotal, cb.salesCount, AppColors.success)),
            Container(width: 1, height: 40, color: AppColors.divider),
            Expanded(child: _buildStatMini(theme, 'المشتريات', cb.purchaseTotal, cb.purchaseCount, AppColors.error)),
          ]),
          if (cb.transfersInTotal > 0 || cb.transfersOutTotal > 0) ...[
            const Divider(height: 16),
            Row(children: [
              Expanded(child: _buildStatMini(theme, 'تحويلات واردة', cb.transfersInTotal, cb.transfersInCount, AppColors.info, 'تحويل')),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(child: _buildStatMini(theme, 'تحويلات صادرة', cb.transfersOutTotal, cb.transfersOutCount, AppColors.warning, 'تحويل')),
            ]),
          ],
          if (cb.exchangesInTotal > 0 || cb.exchangesOutTotal > 0) ...[
            const Divider(height: 16),
            Row(children: [
              Expanded(child: _buildStatMini(theme, 'صرافة واردة', cb.exchangesInTotal, cb.exchangesInCount, AppColors.info, 'عملية')),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(child: _buildStatMini(theme, 'صرافة صادرة', cb.exchangesOutTotal, cb.exchangesOutCount, AppColors.warning, 'عملية')),
            ]),
          ],
        ])),
      )),
    ]));
  }

  Widget _buildStatMini(ThemeData theme, String label, double total, int count, Color color, [String countLabel = 'فاتورة']) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(children: [
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(CurrencyFormatter.formatCompactWithSymbol(total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
      Text('$count $countLabel', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
    ]));
  }

  // ── Accounts Without Movement ──
  Widget _buildAccountsWithoutMovementsReport(ThemeData theme, bool isDark) {
    if (_accountsWithoutMovements.isEmpty) return _buildEmptyState(theme, Icons.account_balance, 'جميع الحسابات لديها حركات');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
        child: Row(children: [
          Icon(Icons.info_outline, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('${_accountsWithoutMovements.length} حساب بدون أي حركة مالية', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.warning))),
        ]),
      ),
      const SizedBox(height: 12),
      ..._accountsWithoutMovements.map((a) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          dense: true,
          leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.textHint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.account_balance, size: 18, color: AppColors.textHint)),
          title: Text(a['name_ar'] as String? ?? '', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text('${a['account_code'] ?? ''} | ${a['account_type'] ?? ''} | ${a['currency'] ?? 'YER'}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
        ),
      )),
    ]));
  }

  // ── Inventory Report ──
  Widget _buildInventoryReport(ThemeData theme, bool isDark) {
    final lowStock = _inventoryItems.where((i) => i.isLowStock).toList();
    final outOfStock = _inventoryItems.where((i) => i.isOutOfStock).toList();
    final totalValue = _inventoryItems.fold(0.0, (s, i) => s + (i.currentStock * i.costPrice));
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _buildStatCard(theme, 'إجمالي الأصناف', '${_inventoryItems.length}', AppColors.primary, Icons.inventory_2)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(theme, 'قيمة المخزون', CurrencyFormatter.formatCompactWithSymbol(totalValue), AppColors.success, Icons.attach_money)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(theme, 'نفذ المخزون', '${outOfStock.length}', AppColors.error, Icons.warning)),
      ]),
      const SizedBox(height: 12),
      if (outOfStock.isNotEmpty) ...[_buildAlertBanner(theme, 'أصناف نفذت (${outOfStock.length})', AppColors.error), const SizedBox(height: 8)],
      if (lowStock.isNotEmpty) ...[_buildAlertBanner(theme, 'أصناف قاربت على النفاد (${lowStock.length})', AppColors.warning), const SizedBox(height: 12)],
      if (_inventoryItems.isEmpty) _buildEmptyState(theme, Icons.inventory_2, 'لا توجد أصناف')
      else ..._inventoryItems.map((item) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(width: 38, height: 38, decoration: BoxDecoration(
            color: (item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(item.isOutOfStock ? Icons.error_outline : item.isLowStock ? Icons.warning : Icons.inventory_2,
              size: 18, color: item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success)),
          title: Row(children: [
            Expanded(child: Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (item.categoryName != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
              child: Text(item.categoryName!, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: AppColors.primary)),
            ),
          ]),
          subtitle: Text('${item.barcode ?? item.itemCode ?? ""}${item.warehouseName != null ? " | ${item.warehouseName}" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${item.currentStock.toStringAsFixed(item.currentStock == item.currentStock.roundToDouble() ? 0 : 1)} قطعة',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: item.isOutOfStock ? AppColors.error : item.isLowStock ? AppColors.warning : AppColors.success)),
            Text('تكلفة: ${CurrencyFormatter.format(item.costPrice)}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
          ]),
        ),
      )),
    ]));
  }

  // ── Inventory Movement Report ──
  Widget _buildInventoryMovementReport(ThemeData theme, bool isDark) {
    if (_inventoryMovementItems.isEmpty) return _buildEmptyState(theme, Icons.swap_vert, 'لا توجد حركات مخزون');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.06), AppColors.success.withValues(alpha: 0.06)]),
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.swap_vert, size: 28, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('حركة المخزون', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          Text('${_inventoryMovementItems.length} صنف', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
        ]),
      ),
      const SizedBox(height: 12),
      _buildTableHeader(theme, ['الصنف', 'الوارد', 'الصادر', 'الصافي'], [3, 2, 2, 2]),
      ..._inventoryMovementItems.asMap().entries.map((e) {
        final item = e.value;
        final qtyIn = (item['qty_in'] as num?)?.toDouble() ?? 0;
        final qtyOut = (item['qty_out'] as num?)?.toDouble() ?? 0;
        final net = qtyIn - qtyOut;
        return _buildTableRow(theme, isDark, e.key, [
          item['product_name'] as String? ?? '',
          qtyIn > 0 ? qtyIn.toStringAsFixed(qtyIn == qtyIn.roundToDouble() ? 0 : 1) : '-',
          qtyOut > 0 ? qtyOut.toStringAsFixed(qtyOut == qtyOut.roundToDouble() ? 0 : 1) : '-',
          net.toStringAsFixed(net == net.roundToDouble() ? 0 : 1),
        ], [3, 2, 2, 2], balanceOverride: net);
      }),
    ]));
  }

  // ── Inventory Cost Report ──
  Widget _buildInventoryCostReport(ThemeData theme, bool isDark) {
    if (_inventoryCostItems.isEmpty) return _buildEmptyState(theme, Icons.attach_money, 'لا توجد بيانات تكلفة');
    double totalCost = 0, totalSell = 0;
    for (final item in _inventoryCostItems) {
      totalCost += (item['stock_cost_value'] as num?)?.toDouble() ?? 0;
      totalSell += (item['stock_sell_value'] as num?)?.toDouble() ?? 0;
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _buildStatCard(theme, 'تكلفة المخزون', CurrencyFormatter.formatCompactWithSymbol(totalCost), AppColors.error, Icons.attach_money)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(theme, 'قيمة البيع', CurrencyFormatter.formatCompactWithSymbol(totalSell), AppColors.success, Icons.sell)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(theme, 'الربح المتوقع', CurrencyFormatter.formatCompactWithSymbol(totalSell - totalCost), AppColors.primary, Icons.trending_up)),
      ]),
      const SizedBox(height: 12),
      _buildTableHeader(theme, ['الصنف', 'الكمية', 'تكلفة الوحدة', 'تكلفة المخزون', 'قيمة البيع'], [3, 1, 2, 2, 2]),
      ..._inventoryCostItems.asMap().entries.map((e) {
        final item = e.value;
        final qty = (item['current_stock'] as num?)?.toDouble() ?? 0;
        return _buildTableRow(theme, isDark, e.key, [
          item['product_name'] as String? ?? '',
          qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1),
          CurrencyFormatter.format((item['cost_price'] as num?)?.toDouble() ?? 0),
          CurrencyFormatter.format((item['stock_cost_value'] as num?)?.toDouble() ?? 0),
          CurrencyFormatter.format((item['stock_sell_value'] as num?)?.toDouble() ?? 0),
        ], [3, 1, 2, 2, 2]);
      }),
    ]));
  }

  // ── Debt Report ──
  Widget _buildDebtReport(ThemeData theme, bool isDark) {
    final isCustomer = _selectedReport == ReportType.customerDebts;
    final debtsOwedToUs = _debtItems.where((i) => i.balanceType == 'debit').toList();
    final debtsWeOwe = _debtItems.where((i) => i.balanceType == 'credit').toList();
    final totalOwed = debtsOwedToUs.fold(0.0, (s, i) => s + i.balance);
    final totalWeOwe = debtsWeOwe.fold(0.0, (s, i) => s + i.balance);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.error.withValues(alpha: 0.08), AppColors.warning.withValues(alpha: 0.08)]),
          borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(isCustomer ? Icons.people : Icons.local_shipping, size: 32, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(isCustomer ? 'ملخص ديون العملاء' : 'ملخص مديونيات الموردين', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [
              Text('ديون لنا', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(CurrencyFormatter.formatCompactWithSymbol(totalOwed), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success)),
              Text('${debtsOwedToUs.length} ${isCustomer ? "عميل" : "مورد"}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
            ]),
            Container(width: 1, height: 50, color: AppColors.divider),
            Column(children: [
              Text('ديون علينا', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(CurrencyFormatter.formatCompactWithSymbol(totalWeOwe), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error)),
              Text('${debtsWeOwe.length} ${isCustomer ? "عميل" : "مورد"}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
            ]),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      if (debtsOwedToUs.isNotEmpty) ...[
        _buildSectionHeader(theme, 'ديون لنا (مبالغ مستحقة لنا)', AppColors.success, Icons.call_made),
        ...debtsOwedToUs.map((item) => Card(margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(isCustomer ? Icons.person : Icons.local_shipping, color: AppColors.success, size: 18)),
            title: Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('${item.currency}${item.phone != null ? " | ${item.phone}" : ""}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
            trailing: Text(CurrencyFormatter.format(item.balance), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
          ),
        )),
        const SizedBox(height: 12),
      ],
      if (debtsWeOwe.isNotEmpty) ...[
        _buildSectionHeader(theme, 'ديون علينا (مبالغ مستحقة علينا)', AppColors.error, Icons.call_received),
        ...debtsWeOwe.map((item) => Card(margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(isCustomer ? Icons.person : Icons.local_shipping, color: AppColors.error, size: 18)),
            title: Text(item.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('${item.currency}${item.phone != null ? " | ${item.phone}" : ""}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
            trailing: Text(CurrencyFormatter.format(item.balance), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
          ),
        )),
      ],
      if (debtsOwedToUs.isEmpty && debtsWeOwe.isEmpty)
        _buildEmptyState(theme, isCustomer ? Icons.people : Icons.local_shipping, 'لا توجد ${isCustomer ? "ديون عملاء" : "مديونيات موردين"}'),
    ]));
  }

  // ── Link Card ──
  Widget _buildLinkCard(ThemeData theme, String title, IconData icon, String route) {
    return Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 64, color: AppColors.primary),
      const SizedBox(height: 16),
      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: () => Navigator.pushNamed(context, route),
        icon: const Icon(Icons.arrow_forward),
        label: const Text('انتقل'),
      ),
    ])));
  }

  // ══════════════════════════════════════════════════════════════
  //  Account Movements Tab (2nd Tab)
  // ══════════════════════════════════════════════════════════════

  Widget _buildAccountMovementsTab(ThemeData theme, bool isDark) {
    return Column(children: [
      Container(
        margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? AppColors.darkSurface : AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اختر الحساب', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper().getAllAccounts(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<int>(
                value: _selectedAccountId,
                decoration: InputDecoration(filled: true, fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(Icons.account_balance_wallet, size: 20)),
                items: snap.data!.map((acc) => DropdownMenuItem<int>(
                  value: acc['id'] as int,
                  child: Text("${acc['name_ar']} (${acc['currency']})", style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (val) { setState(() { _selectedAccountId = val; _isLoading = true; }); _loadSelectedReport(); },
              );
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _buildDateChip('من', _dateFrom, _pickDateFrom, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _buildDateChip('إلى', _dateTo, _pickDateTo, isDark)),
          ]),
        ]),
      ),
      Expanded(
        child: _accountMovements.isEmpty
            ? _buildEmptyState(theme, Icons.swap_horiz, 'اختر حساباً لعرض حركته')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _accountMovements.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) return _buildTableHeader(theme, ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'], [2, 3, 2, 2, 2]);
                  final mov = _accountMovements[i - 1];
                  return _buildTableRow(theme, isDark, i - 1, [
                    _formatDateShort(mov.date), mov.description,
                    mov.debit > 0 ? CurrencyFormatter.format(mov.debit) : '-',
                    mov.credit > 0 ? CurrencyFormatter.format(mov.credit) : '-',
                    CurrencyFormatter.format(mov.balance),
                  ], [2, 3, 2, 2, 2], debitIndex: 2, creditIndex: 3, balanceValue: mov.balance);
                }),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Shared UI Helpers
  // ══════════════════════════════════════════════════════════════

  Widget _buildEmptyState(ThemeData theme, IconData icon, String message) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
      Icon(icon, size: 64, color: AppColors.textHint),
      const SizedBox(height: 16),
      Text(message, style: TextStyle(fontSize: 16, color: AppColors.textHint), textAlign: TextAlign.center),
    ])));
  }

  Widget _buildDateChip(String label, DateTime? date, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(date != null ? DateFormatter.formatDate(date) : label, style: TextStyle(fontSize: 13, color: date != null ? null : AppColors.textHint)),
        ]),
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        Text(title, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildAlertBanner(ThemeData theme, String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(color == AppColors.error ? Icons.error_outline : Icons.warning, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, Color color, IconData icon) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
    ]));
  }

  Widget _buildTotalSummaryRow(ThemeData theme, List<_SummaryItem> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
      child: Row(children: items.map((item) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(children: [
        Text(item.title, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(item.isCount ? item.value.toInt().toString() : CurrencyFormatter.formatCompactWithSymbol(item.value),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: item.color)),
      ])))).toList()),
    );
  }

  Widget _buildTableHeader(ThemeData theme, List<String> labels, List<int> flexes) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
      child: Row(children: List.generate(labels.length, (i) =>
        Expanded(flex: flexes[i], child: Text(labels[i], style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: i >= 2 ? TextAlign.center : TextAlign.right)))),
    );
  }

  Widget _buildTableRow(ThemeData theme, bool isDark, int index, List<String> cells, List<int> flexes, {
    int? debitIndex, int? creditIndex, double? balanceValue, double? balanceOverride
  }) {
    final bgColor = index.isEven
        ? (isDark ? AppColors.darkSurface : AppColors.surface)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: bgColor, border: Border(bottom: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border))),
      child: Row(children: List.generate(cells.length, (i) {
        Color? cellColor;
        if (i == debitIndex && cells[i] != '-') cellColor = AppColors.error;
        else if (i == creditIndex && cells[i] != '-') cellColor = AppColors.success;
        else if (i == cells.length - 1 && balanceValue != null) {
          cellColor = balanceValue >= 0 ? AppColors.primary : AppColors.error;
        } else if (balanceOverride != null && i == cells.length - 1) {
          cellColor = balanceOverride >= 0 ? AppColors.success : AppColors.error;
        }
        return Expanded(flex: flexes[i], child: Text(cells[i],
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: i == cells.length - 1 ? FontWeight.w700 : null, color: cellColor),
          textAlign: i >= 2 ? TextAlign.center : TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis));
      })),
    );
  }

  String _formatDateShort(String isoDate) {
    try { final dt = DateTime.parse(isoDate); return "${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}"; }
    catch (_) { return isoDate; }
  }

  // ══════════════════════════════════════════════════════════════
  //  Date Pickers & Filters
  // ══════════════════════════════════════════════════════════════

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(context: context, initialDate: _dateFrom ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)), locale: const Locale('ar'));
    if (picked != null) { setState(() { _dateFrom = picked; }); _loadSelectedReport(); }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(context: context, initialDate: _dateTo ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)), locale: const Locale('ar'));
    if (picked != null) { setState(() { _dateTo = picked; }); _loadSelectedReport(); }
  }

  void _clearFilters() {
    setState(() { _dateFrom = null; _dateTo = null; _selectedCurrency = 'الكل'; });
    _loadSelectedReport();
  }

  // ══════════════════════════════════════════════════════════════
  //  Export to Excel
  // ══════════════════════════════════════════════════════════════

  Future<void> _exportToExcel() async {
    try {
      String? result;
      switch (_selectedReport) {
        case ReportType.inventory:
          final data = _inventoryItems.map((i) => <String,dynamic>{
            'name_ar': i.name, 'barcode': i.barcode ?? '', 'item_code': i.itemCode ?? '',
            'current_stock': i.currentStock, 'cost_price': i.costPrice, 'sell_price': i.sellPrice,
            'category_name': i.categoryName ?? '', 'warehouse_name': i.warehouseName ?? '',
          }).toList();
          result = await ExcelExporter.exportInventoryToExcel(data);
          break;
        case ReportType.trialBalance:
          final data = _trialBalanceItems.map((i) => <String,dynamic>{
            'account_code': i.accountCode, 'name_ar': i.accountName, 'account_type': i.accountType,
            'currency': i.currency, 'debit': i.debit, 'credit': i.credit,
          }).toList();
          result = await ExcelExporter.exportAccountsToExcel(data);
          break;
        case ReportType.sales:
        case ReportType.purchases:
          final db = await DatabaseHelper().database;
          final invoices = await db.rawQuery("SELECT * FROM invoices ORDER BY created_at DESC LIMIT 500");
          result = await ExcelExporter.exportInvoicesToExcel(invoices);
          break;
        default:
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تصدير هذا التقرير غير مدعوم حالياً'), backgroundColor: AppColors.warning));
          return;
      }
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تصدير التقرير بنجاح'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في التصدير: $e'), backgroundColor: AppColors.error));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Data Models
// ═══════════════════════════════════════════════════════════════════

class _TopProduct {
  final String name;
  final int quantity;
  final double revenue;
  _TopProduct({required this.name, required this.quantity, required this.revenue});
}

class _RecentInvoice {
  final String id, title, subtitle, date;
  final double total;
  final String currency;
  final IconData icon;
  final Color color;
  _RecentInvoice({required this.id, required this.title, required this.subtitle, required this.date, required this.total, required this.currency, required this.icon, required this.color});
}

class _AccountMovement {
  final String date, description;
  final double debit, credit, balance;
  _AccountMovement({required this.date, required this.description, required this.debit, required this.credit, required this.balance});
}

class _AllAccountMovement {
  final String date, accountName, accountCode, currency, description;
  final double debit, credit;
  _AllAccountMovement({required this.date, required this.accountName, required this.accountCode, required this.currency, required this.description, required this.debit, required this.credit});
}

class _TrialBalanceItem {
  final int accountId;
  final String accountName, accountCode, accountType, currency;
  final double debit, credit;
  _TrialBalanceItem({required this.accountId, required this.accountName, required this.accountCode, required this.accountType, required this.currency, required this.debit, required this.credit});
}

class _DebtItem {
  final String name, balanceType, currency;
  final double balance;
  final String? phone;
  _DebtItem({required this.name, required this.balance, required this.balanceType, required this.currency, this.phone});
}

class _CashBoxMovement {
  final int id;
  final String name, type, balanceType, currency;
  final double balance;
  final double salesTotal; final int salesCount;
  final double purchaseTotal; final int purchaseCount;
  final double transfersInTotal; final int transfersInCount;
  final double transfersOutTotal; final int transfersOutCount;
  final double exchangesInTotal; final int exchangesInCount;
  final double exchangesOutTotal; final int exchangesOutCount;
  _CashBoxMovement({required this.id, required this.name, required this.type, required this.balance, required this.balanceType, required this.currency,
    required this.salesTotal, required this.salesCount, required this.purchaseTotal, required this.purchaseCount,
    required this.transfersInTotal, required this.transfersInCount, required this.transfersOutTotal, required this.transfersOutCount,
    required this.exchangesInTotal, required this.exchangesInCount, required this.exchangesOutTotal, required this.exchangesOutCount});
}

class _InventoryItem {
  final int id;
  final String name;
  final String? barcode, itemCode, warehouseName, categoryName;
  final double currentStock, costPrice, sellPrice, minStock;
  final bool isLowStock, isOutOfStock;
  _InventoryItem({required this.id, required this.name, this.barcode, this.itemCode, required this.currentStock,
    required this.costPrice, required this.sellPrice, required this.minStock, this.warehouseName, this.categoryName,
    required this.isLowStock, required this.isOutOfStock});
}

class _SummaryItem {
  final String title;
  final double value;
  final Color color;
  final bool isCount;
  _SummaryItem({required this.title, required this.value, required this.color, this.isCount = false});
}
