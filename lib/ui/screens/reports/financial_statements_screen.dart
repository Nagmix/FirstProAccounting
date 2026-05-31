import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/report_service.dart';

// ═══════════════════════════════════════════════════════════════════
//  Financial Statements Screen (القوائم المالية)
//  Tab 1: Income Statement (قائمة الدخل)
//  Tab 2: Balance Sheet (قائمة المركزية المالي)
// ═══════════════════════════════════════════════════════════════════

class FinancialStatementsScreen extends StatefulWidget {
  const FinancialStatementsScreen({super.key});

  @override
  State<FinancialStatementsScreen> createState() => _FinancialStatementsScreenState();
}

class _FinancialStatementsScreenState extends State<FinancialStatementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String _selectedCurrency = 'ر.ي';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Income Statement data
  double _revenue = 0;
  double _cost = 0;
  double _expenses = 0;
  double _grossProfit = 0;
  double _netProfit = 0;
  List<Map<String, dynamic>> _revenueAccounts = [];
  List<Map<String, dynamic>> _costAccounts = [];
  List<Map<String, dynamic>> _expenseAccounts = [];

  // Balance Sheet data
  double _assets = 0;
  double _liabilities = 0;
  double _equity = 0;
  bool _isBalanced = false;
  List<Map<String, dynamic>> _assetAccounts = [];
  List<Map<String, dynamic>> _liabilityAccounts = [];
  List<Map<String, dynamic>> _equityAccounts = [];

  static const _currencyOptions = ['ر.ي', 'ر.س', r'$'];

  String? _currencyCode() {
    switch (_selectedCurrency) {
      case 'ر.ي': return 'YER';
      case 'ر.س': return 'SAR';
      case r'$': return 'USD';
      default: return null;
    }
  }

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final cc = _currencyCode();

      // Build date filter args for ReportService
      final accountTypes = ['REVENUE', 'COST', 'EXPENSE', 'ASSET', 'LIABILITY', 'EQUITY'];
      final results = await locator<ReportService>().getFinancialStatementsData(
        accountTypes: accountTypes,
        currency: cc,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

      double revenue = 0, cost = 0, expenses = 0;
      double assets = 0, liabilities = 0, equityFromAccounts = 0;
      final revenueAccounts = <Map<String, dynamic>>[];
      final costAccounts = <Map<String, dynamic>>[];
      final expenseAccounts = <Map<String, dynamic>>[];
      final assetAccounts = <Map<String, dynamic>>[];
      final liabilityAccounts = <Map<String, dynamic>>[];
      final equityAccountsList = <Map<String, dynamic>>[];

      for (final row in results) {
        // Use readCalculatedMoney for SQL SUM results which may be REAL
        final totalDebitRaw = MoneyHelper.readCalculatedMoney(row['total_debit']);
        final totalCreditRaw = MoneyHelper.readCalculatedMoney(row['total_credit']);
        final netBalance = totalDebitRaw - totalCreditRaw;
        final accountType = row['account_type'] as String? ?? '';
        final balanceType = row['balance_type'] as String? ?? 'credit';

        if (MoneyHelper.isZero(netBalance)) continue;

        // For income statement accounts:
        // REVENUE (credit-type): net credit balance is the revenue amount
        // COST (debit-type): net debit balance is the cost amount
        // EXPENSE (debit-type): net debit balance is the expense amount
        //
        // For balance sheet accounts:
        // ASSET (debit-type): net debit balance is the asset amount
        // LIABILITY (credit-type): net credit balance is the liability amount

        double balanceAmount;
        switch (accountType) {
          case 'REVENUE':
            // Revenue is credit-type: credit - debit = revenue
            balanceAmount = totalCreditRaw - totalDebitRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              revenue += balanceAmount.abs();
              revenueAccounts.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
          case 'COST':
            // Cost is debit-type: debit - credit = cost
            balanceAmount = totalDebitRaw - totalCreditRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              cost += balanceAmount.abs();
              costAccounts.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
          case 'EXPENSE':
            // Expense is debit-type: debit - credit = expense
            balanceAmount = totalDebitRaw - totalCreditRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              expenses += balanceAmount.abs();
              expenseAccounts.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
          case 'ASSET':
            // Asset is debit-type: debit - credit = asset value
            balanceAmount = totalDebitRaw - totalCreditRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              assets += balanceAmount.abs();
              assetAccounts.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
          case 'LIABILITY':
            // Liability is credit-type: credit - debit = liability
            balanceAmount = totalCreditRaw - totalDebitRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              liabilities += balanceAmount.abs();
              liabilityAccounts.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
          case 'EQUITY':
            // Equity is credit-type: credit - debit = equity
            balanceAmount = totalCreditRaw - totalDebitRaw;
            if (!MoneyHelper.isZero(balanceAmount)) {
              equityFromAccounts += balanceAmount.abs();
              equityAccountsList.add({
                'account_code': row['account_code'] as String? ?? '',
                'name_ar': row['name_ar'] as String? ?? '',
                'balance': balanceAmount.abs(),
              });
            }
        }
      }

      final grossProfit = revenue - cost;
      final netProfit = grossProfit - expenses;
      // Equity = actual equity accounts + net profit (from income statement)
      // Balance Sheet equation: Assets = Liabilities + Equity
      final equity = equityFromAccounts + netProfit;
      final isBalanced = MoneyHelper.isZero(assets - (liabilities + equity));

      if (mounted) {
        setState(() {
          _revenue = revenue;
          _cost = cost;
          _expenses = expenses;
          _grossProfit = grossProfit;
          _netProfit = netProfit;
          _revenueAccounts = revenueAccounts;
          _costAccounts = costAccounts;
          _expenseAccounts = expenseAccounts;
          _assets = assets;
          _liabilities = liabilities;
          _equity = equity;
          _isBalanced = isBalanced;
          _assetAccounts = assetAccounts;
          _liabilityAccounts = liabilityAccounts;
          _equityAccounts = equityAccountsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Financial statements error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات: ${e.toString().length > 80 ? e.toString().substring(0, 80) + '...' : e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dateFrom = picked);
      _loadData();
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dateTo = picked);
      _loadData();
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '---';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('القوائم المالية'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadData,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'قائمة الدخل', icon: Icon(Icons.assessment, size: 18)),
              Tab(text: 'قائمة المركزية المالي', icon: Icon(Icons.account_balance, size: 18)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildIncomeStatementTab(theme, isDark),
                  _buildBalanceSheetTab(theme, isDark),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Shared Filters
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFiltersBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Currency
          Text('العملة:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCurrency,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, size: 14),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                items: _currencyOptions.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: const TextStyle(fontSize: 12)),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCurrency = val);
                    _loadData();
                  }
                },
              ),
            ),
          ),
          const Spacer(),
          // Date range
          InkWell(
            onTap: _pickDateFrom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('من: ${_fmtDate(_dateFrom)}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _pickDateTo,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('إلى: ${_fmtDate(_dateTo)}', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Income Statement Tab
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildIncomeStatementTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFiltersBar(theme),
          const SizedBox(height: 8),

          // ── Summary Card ──
          _buildIncomeSummaryCard(theme, isDark),
          const SizedBox(height: 16),

          // ── Revenue Section ──
          _buildAccountSection(theme, isDark, 'الإيرادات', _revenueAccounts, AppColors.success, Icons.trending_up),
          const SizedBox(height: 12),

          // ── Cost Section ──
          _buildAccountSection(theme, isDark, 'التكاليف (تكلفة البضاعة المباعة + المشتريات)', _costAccounts, AppColors.error, Icons.south_east),
          const SizedBox(height: 12),

          // ── Gross Profit ──
          _buildProfitCard(theme, isDark, 'مجمل الربح', _grossProfit, _grossProfit >= 0 ? AppColors.success : AppColors.error),
          const SizedBox(height: 12),

          // ── Expenses Section ──
          _buildAccountSection(theme, isDark, 'المصاريف التشغيلية', _expenseAccounts, AppColors.warning, Icons.remove_circle_outline),
          const SizedBox(height: 12),

          // ── Net Profit ──
          _buildNetProfitCard(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildIncomeSummaryCard(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (_netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.08),
            (_netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.assessment, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('ملخص قائمة الدخل', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMiniSummary(theme, 'الإيرادات', _revenue, AppColors.success)),
              const SizedBox(width: 8),
              Expanded(child: _buildMiniSummary(theme, 'التكاليف', _cost, AppColors.error)),
              const SizedBox(width: 8),
              Expanded(child: _buildMiniSummary(theme, 'المصاريف', _expenses, AppColors.warning)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_netProfit >= 0 ? AppColors.success : AppColors.error).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(_netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                    size: 28, color: _netProfit >= 0 ? AppColors.success : AppColors.error),
                const SizedBox(height: 4),
                Text(_netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.format(_netProfit.abs(), symbol: _selectedCurrency),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _netProfit >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSummary(ThemeData theme, String title, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(title, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.format(value, symbol: _selectedCurrency),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildProfitCard(ThemeData theme, bool isDark, String title, double value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.calculate, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          Text(
            '${title == 'مجمل الربح' ? 'الإيرادات - التكاليف' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(width: 8),
          Text(CurrencyFormatter.format(value, symbol: _selectedCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildNetProfitCard(ThemeData theme, bool isDark) {
    final color = _netProfit >= 0 ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(_netProfit >= 0 ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('مجمل الربح - المصاريف',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
          const SizedBox(width: 8),
          Text(CurrencyFormatter.format(_netProfit, symbol: _selectedCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Balance Sheet Tab
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildBalanceSheetTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFiltersBar(theme),
          const SizedBox(height: 8),

          // ── Balance Check Card ──
          _buildBalanceCheckCard(theme, isDark),
          const SizedBox(height: 16),

          // ── Assets Section ──
          _buildAccountSection(theme, isDark, 'الأصول', _assetAccounts, AppColors.info, Icons.account_balance_wallet),
          const SizedBox(height: 12),

          // ── Liabilities Section ──
          _buildAccountSection(theme, isDark, 'الخصوم', _liabilityAccounts, AppColors.error, Icons.local_shipping),
          const SizedBox(height: 12),

          // ── Equity Section ──
          _buildAccountSection(theme, isDark, 'حقوق الملكية', _equityAccounts, AppColors.accentPurple, Icons.account_balance),
          const SizedBox(height: 12),

          // ── Equity Summary (includes net profit) ──
          _buildEquityCard(theme, isDark),

          const SizedBox(height: 12),

          // ── Balance Equation ──
          _buildBalanceEquationCard(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildBalanceCheckCard(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (_isBalanced ? AppColors.success : AppColors.error).withOpacity(0.08),
            (_isBalanced ? AppColors.success : AppColors.error).withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (_isBalanced ? AppColors.success : AppColors.error).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('ملخص قائمة المركزية المالي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_isBalanced ? AppColors.success : AppColors.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isBalanced ? Icons.check_circle : Icons.warning, size: 14,
                        color: _isBalanced ? AppColors.success : AppColors.error),
                    const SizedBox(width: 4),
                    Text(
                      _isBalanced ? 'متوازن' : 'غير متوازن',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _isBalanced ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMiniSummary(theme, 'الأصول', _assets, AppColors.info)),
              const SizedBox(width: 8),
              Expanded(child: _buildMiniSummary(theme, 'الخصوم', _liabilities, AppColors.error)),
              const SizedBox(width: 8),
              Expanded(child: _buildMiniSummary(theme, 'حقوق الملكية', _equity,
                  _equity >= 0 ? AppColors.success : AppColors.error)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquityCard(ThemeData theme, bool isDark) {
    final color = _equity >= 0 ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.account_balance, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('حقوق الملكية', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          Text('الأصول - الخصوم', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
          const SizedBox(width: 8),
          Text(CurrencyFormatter.format(_equity, symbol: _selectedCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildBalanceEquationCard(ThemeData theme, bool isDark) {
    final totalLiabilitiesEquity = _liabilities + _equity;
    final balanced = MoneyHelper.isZero(_assets - totalLiabilitiesEquity);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.functions, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('المعادلة المحاسبية', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          _buildEquationRow(theme, 'الأصول', _assets, AppColors.info),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('=', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w900, color: AppColors.primary)),
              const SizedBox(width: 12),
            ],
          ),
          _buildEquationRow(theme, 'الخصوم', _liabilities, AppColors.error),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('+', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w900, color: AppColors.primary)),
              const SizedBox(width: 12),
            ],
          ),
          _buildEquationRow(theme, 'حقوق الملكية', _equity, _equity >= 0 ? AppColors.success : AppColors.error),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الخصوم + حقوق الملكية', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(CurrencyFormatter.format(totalLiabilitiesEquity, symbol: _selectedCurrency),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (balanced ? AppColors.success : AppColors.error).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(balanced ? Icons.verified : Icons.error_outline, size: 18,
                    color: balanced ? AppColors.success : AppColors.error),
                const SizedBox(width: 6),
                Text(
                  balanced ? 'الميزانية متوازنة ✓' : 'الميزانية غير متوازنة - يرجى المراجعة',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: balanced ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquationRow(ThemeData theme, String label, double value, Color color) {
    return Row(
      children: [
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        Text(CurrencyFormatter.format(value, symbol: _selectedCurrency),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Shared Account Section Builder
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAccountSection(ThemeData theme, bool isDark, String title,
      List<Map<String, dynamic>> accounts, Color color, IconData icon) {
    final total = accounts.fold(0.0, (sum, a) => sum + (a['balance'] as double? ?? 0.0));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color))),
              Text(CurrencyFormatter.format(total, symbol: _selectedCurrency),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('لا توجد حسابات', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
              ),
            )
          else ...[
            const Divider(height: 20),
            ...accounts.map((account) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(account['account_code'] as String? ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(account['name_ar'] as String? ?? '',
                        style: theme.textTheme.bodySmall),
                  ),
                  Text(CurrencyFormatter.format(account['balance'] as double? ?? 0.0, symbol: _selectedCurrency),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}
