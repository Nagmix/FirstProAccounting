import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../widgets/bar_chart_widget.dart';

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
  ];

  static const List<String> _currencyOptions = ['الكل', 'ر.ي', 'ر.س', r'\$'];

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
  double _totalExpenses = 0.0;
  double _netProfit = 0.0;
  int _invoiceCount = 0;
  List<BarData> _dailySalesData = [];
  List<_TopProduct> _topProducts = [];
  List<_RecentInvoice> _recentInvoices = [];
  List<_AccountMovement> _accountMovements = [];
  List<_AllAccountMovement> _allAccountMovements = [];
  List<_TrialBalanceItem> _trialBalanceItems = [];
  List<_DebtItem> _debtItems = [];
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;

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
      case r'\$':
        return 'USD';
      default:
        return null;
    }
  }

  Future<void> _loadReportData() async {
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

    final revenueResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND is_return = 0"
          "$dateFilter$currencyFilter",
      allArgs,
    );
    final totalRevenue =
        (revenueResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final expenseResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'purchase' AND is_return = 0"
          "$dateFilter$currencyFilter",
      allArgs,
    );
    final totalExpenses =
        (expenseResult.first['total'] as num?)?.toDouble() ?? 0.0;

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

    final countResult = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE is_return = 0"
          "$dateFilter$currencyFilter",
      allArgs,
    );
    final invoiceCount =
        (countResult.first['cnt'] as num?)?.toInt() ?? 0;

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
        "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND is_return = 0 AND created_at >= ? AND created_at < ?",
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

    final topProductsResult = await db.rawQuery(
      "SELECT product_id, product_name, SUM(quantity) AS total_quantity, SUM(total_price) AS total_revenue FROM invoice_items GROUP BY product_id ORDER BY total_quantity DESC LIMIT 5",
    );
    final List<_TopProduct> topProducts =
        topProductsResult.map((row) => _TopProduct(
              name: row['product_name'] as String? ?? 'منتج غير معروف',
              quantity: (row['total_quantity'] as num?)?.toInt() ?? 0,
              revenue: (row['total_revenue'] as num?)?.toDouble() ?? 0.0,
            )).toList();

    final recentResult = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.is_return, i.created_at, CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') ELSE 'بدون عميل' END AS entity_name FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id LEFT JOIN suppliers s ON i.supplier_id = s.id ORDER BY i.created_at DESC LIMIT 5",
    );
    final List<_RecentInvoice> recentInvoices =
        recentResult.map((row) {
      final type = row['type'] as String? ?? 'sale';
      final isReturn = (row['is_return'] as int?) == 1;
      return _RecentInvoice(
        id: row['id'] as String? ?? '',
        title: type == 'sale'
            ? (isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات')
            : (isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات'),
        subtitle: row['entity_name'] as String? ?? '',
        date: row['created_at'] as String? ?? '',
        total: (row['total'] as num?)?.toDouble() ?? 0.0,
        icon: type == 'sale'
            ? (isReturn ? Icons.undo : Icons.receipt_long_outlined)
            : (isReturn ? Icons.undo : Icons.shopping_cart_outlined),
        color: type == 'sale'
            ? (isReturn ? AppColors.warning : AppColors.success)
            : (isReturn ? AppColors.warning : AppColors.error),
      );
    }).toList();

    // Account movements (single account)
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

    // All accounts movements
    List<_AllAccountMovement> allAccountMovements = [];
    {
      String allTxDateFilter = dateFilter.replaceAll('created_at', 't.created_at');
      final allTx = await db.rawQuery(
        "SELECT t.id, t.account_id, t.debit, t.credit, t.description, t.date, t.created_at, "
        "a.name_ar AS account_name, a.account_code, a.currency "
        "FROM transactions t "
        "LEFT JOIN accounts a ON t.account_id = a.id "
        "WHERE 1=1 $allTxDateFilter "
        "ORDER BY t.date DESC, t.created_at DESC",
        dateArgs,
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

    // Trial balance
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

    // Debt items
    List<_DebtItem> debtItems = [];
    if (_selectedReportType == 'ديون العملاء') {
      final customers = await dbHelper.getAllCustomers();
      for (final c in customers) {
        final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
        if (balance > 0) {
          debtItems.add(_DebtItem(
            name: c['name'] as String? ?? '',
            balance: balance,
            balanceType: c['balance_type'] as String? ?? 'credit',
            currency: c['currency'] as String? ?? 'YER',
            phone: c['phone'] as String?,
          ));
        }
      }
    } else if (_selectedReportType == 'ديون الموردين') {
      final suppliers = await dbHelper.getAllSuppliers();
      for (final s in suppliers) {
        final balance = (s['balance'] as num?)?.toDouble() ?? 0.0;
        if (balance > 0) {
          debtItems.add(_DebtItem(
            name: s['name'] as String? ?? '',
            balance: balance,
            balanceType: s['balance_type'] as String? ?? 'debit',
            currency: s['currency'] as String? ?? 'YER',
            phone: s['phone'] as String?,
          ));
        }
      }
    }

    if (mounted) {
      setState(() {
        _totalRevenue = totalRevenue;
        _totalExpenses = totalExpenses + actualExpenses;
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
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _dateTo = picked);
      _loadReportData();
    }
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
              Tab(text: 'التقارير', icon: Icon(PhosphorIconsRegular.chartBar, size: 20)),
              Tab(text: 'حركة الحسابات', icon: Icon(PhosphorIconsRegular.arrowsLeftRight, size: 20)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
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
                : SingleChildScrollView(
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
      case 'ديون العملاء':
      case 'ديون الموردين':
        return _buildDebtReport(theme, isDark);
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(theme, isDark),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: BarChartWidget(
                data: _dailySalesData,
                title: 'المبيعات اليومية',
                barColor: AppColors.primary,
                height: 240,
              ),
            ),
            const SizedBox(height: 20),
            _buildTopProductsSection(theme, isDark),
            const SizedBox(height: 20),
            _buildRecentInvoicesSection(theme, isDark),
          ],
        );
    }
  }

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
                      prefixIcon: const Icon(PhosphorIconsRegular.wallet,
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsRegular.arrowsLeftRight,
                          size: 64, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      Text('اختر حساباً لعرض حركته',
                          style: TextStyle(fontSize: 16, color: AppColors.textHint)),
                    ],
                  ),
                )
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
            Icon(PhosphorIconsRegular.calendar, size: 16, color: AppColors.primary),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.arrowsLeftRight, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('لا توجد حركات', style: TextStyle(fontSize: 16, color: AppColors.textHint)),
          ],
        ),
      );
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
          _buildMovementHeader(theme, isDark),
          ..._trialBalanceItems.map((item) => Container(
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
                      prefixIcon: const Icon(PhosphorIconsRegular.wallet, size: 20),
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
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(PhosphorIconsRegular.arrowsLeftRight, size: 64, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    Text('اختر حساباً لعرض حركته', style: TextStyle(fontSize: 16, color: AppColors.textHint)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDebtReport(ThemeData theme, bool isDark) {
    final isCustomer = _selectedReportType == 'ديون العملاء';
    final totalDebt = _debtItems.fold(0.0, (sum, item) => sum + item.balance);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                Icon(isCustomer ? PhosphorIconsRegular.users : PhosphorIconsRegular.truck, size: 32, color: AppColors.error),
                const SizedBox(height: 8),
                Text(
                  'إجمالي ${isCustomer ? "ديون العملاء" : "مديونيات الموردين"}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.formatCompactWithSymbol(totalDebt),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error)),
                const SizedBox(height: 4),
                Text('${_debtItems.length} ${isCustomer ? "عميل" : "مورد"}',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._debtItems.map((item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(isCustomer ? PhosphorIconsRegular.user : PhosphorIconsRegular.truck, color: AppColors.error, size: 22),
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
                      Text(item.balanceType == 'credit' ? 'له' : 'عليه',
                          style: theme.textTheme.bodySmall?.copyWith(color: item.balanceType == 'credit' ? AppColors.success : AppColors.error)),
                    ],
                  ),
                ],
              ),
            ),
          )),
          if (_debtItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(PhosphorIconsRegular.checkCircle, size: 64, color: AppColors.success),
                    const SizedBox(height: 16),
                    Text('لا توجد ${isCustomer ? "ديون على العملاء" : "مديونيات للموردين"}',
                        style: TextStyle(fontSize: 16, color: AppColors.success)),
                  ],
                ),
              ),
            ),
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
                    Icon(PhosphorIconsRegular.calendar, size: 16, color: AppColors.primary),
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
                    Icon(PhosphorIconsRegular.calendar, size: 16, color: AppColors.primary),
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
      _SummaryCardData(title: 'إجمالي الإيرادات', value: _totalRevenue, icon: PhosphorIconsRegular.trendUp, color: AppColors.success, lightBg: AppColors.successLight),
      _SummaryCardData(title: 'إجمالي المصروفات', value: _totalExpenses, icon: PhosphorIconsRegular.trendDown, color: AppColors.error, lightBg: AppColors.errorLight),
      _SummaryCardData(title: 'صافي الربح', value: _netProfit, icon: PhosphorIconsRegular.currencyDollar, color: AppColors.secondaryDark, lightBg: const Color(0xFFFFF8E1)),
      _SummaryCardData(title: 'عدد الفواتير', value: _invoiceCount.toDouble(), icon: PhosphorIconsRegular.receipt, color: AppColors.info, lightBg: AppColors.infoLight, isCount: true),
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
          ..._recentInvoices.map((invoice) => _RecentInvoiceCard(invoice: invoice, isDark: isDark)),
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
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(rank <= 3 ? AppColors.secondary : AppColors.primaryLight),
            ),
          ),
          if (!isLast) const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RecentInvoice {
  const _RecentInvoice({required this.id, required this.title, required this.subtitle, required this.date, required this.total, required this.icon, required this.color});
  final String id;
  final String title;
  final String subtitle;
  final String date;
  final double total;
  final IconData icon;
  final Color color;
}

class _RecentInvoiceCard extends StatelessWidget {
  const _RecentInvoiceCard({required this.invoice, required this.isDark});
  final _RecentInvoice invoice;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: invoice.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(invoice.icon, color: invoice.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(invoice.subtitle, style: theme.textTheme.labelSmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(CurrencyFormatter.format(invoice.total), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: invoice.color)),
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
  const _AllAccountMovement({
    required this.date,
    required this.accountName,
    required this.accountCode,
    required this.currency,
    required this.description,
    required this.debit,
    required this.credit,
  });
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


