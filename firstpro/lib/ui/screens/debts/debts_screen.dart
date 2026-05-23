import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  DEBTS SCREEN – FirstPro Arabic Accounting App
//  شاشة الديون - تتبع ديون العملاء وديون صاحب العمل
// ═══════════════════════════════════════════════════════════════════════════════

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Data ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allCustomers = [];
  List<Map<String, dynamic>> _allSuppliers = [];
  List<Map<String, dynamic>> _liabilityAccounts = [];
  bool _isLoading = true;

  // ── Filters ───────────────────────────────────────────────────────
  String _selectedCurrency = 'الكل';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Currency display info ─────────────────────────────────────────
  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  static const List<String> _currencyFilters = ['الكل', 'YER', 'SAR', 'USD'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final customers = await db.getAllCustomers();
    final suppliers = await db.getAllSuppliers();
    final liabilityAccounts = await db.getAccountsByType('LIABILITY');

    if (!mounted) return;

    setState(() {
      _allCustomers = customers;
      _allSuppliers = suppliers;
      _liabilityAccounts = liabilityAccounts;
      _isLoading = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ACCOUNTING LOGIC
  // ═══════════════════════════════════════════════════════════════════

  /// Customers with debit balance (balance_type = 'debit' && balance > 0)
  /// means the customer owes the business money (receivable / ديون العملاء)
  List<Map<String, dynamic>> get _debtCustomers {
    return _allCustomers.where((c) {
      final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = c['balance_type'] as String? ?? 'credit';
      final matchesCurrency = _selectedCurrency == 'الكل' ||
          (c['currency'] as String? ?? 'YER') == _selectedCurrency;
      final matchesSearch = _searchQuery.isEmpty ||
          ((c['name'] as String? ?? '').contains(_searchQuery) ||
              (c['phone'] as String? ?? '').contains(_searchQuery));
      return balance > 0 && balanceType == 'debit' && matchesCurrency && matchesSearch;
    }).toList();
  }

  /// Suppliers with debit balance (balance_type = 'debit' && balance > 0)
  /// means the business owes the supplier money (payable / ديون صاحب العمل)
  List<Map<String, dynamic>> get _debtSuppliers {
    return _allSuppliers.where((s) {
      final balance = (s['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = s['balance_type'] as String? ?? 'debit';
      final matchesCurrency = _selectedCurrency == 'الكل' ||
          (s['currency'] as String? ?? 'YER') == _selectedCurrency;
      final matchesSearch = _searchQuery.isEmpty ||
          ((s['name'] as String? ?? '').contains(_searchQuery) ||
              (s['phone'] as String? ?? '').contains(_searchQuery));
      return balance > 0 && balanceType == 'debit' && matchesCurrency && matchesSearch;
    }).toList();
  }

  /// Expense accounts that represent business debts (LIABILITY accounts with balance > 0)
  List<Map<String, dynamic>> get _debtExpenseAccounts {
    return _liabilityAccounts.where((a) {
      final balance = (a['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = a['balance_type'] as String? ?? 'credit';
      final matchesCurrency = _selectedCurrency == 'الكل' ||
          (a['currency'] as String? ?? 'YER') == _selectedCurrency;
      // Liability accounts with credit balance mean the business owes money
      return balance > 0 && balanceType == 'credit' && matchesCurrency;
    }).toList();
  }

  /// Total customer debt per currency
  Map<String, double> get _customerDebtTotals {
    final totals = <String, double>{};
    for (final c in _debtCustomers) {
      final currency = c['currency'] as String? ?? 'YER';
      final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
      totals[currency] = (totals[currency] ?? 0.0) + balance;
    }
    return totals;
  }

  /// Total business debt (suppliers + expense accounts) per currency
  Map<String, double> get _businessDebtTotals {
    final totals = <String, double>{};
    for (final s in _debtSuppliers) {
      final currency = s['currency'] as String? ?? 'YER';
      final balance = (s['balance'] as num?)?.toDouble() ?? 0.0;
      totals[currency] = (totals[currency] ?? 0.0) + balance;
    }
    for (final a in _debtExpenseAccounts) {
      final currency = a['currency'] as String? ?? 'YER';
      final balance = (a['balance'] as num?)?.toDouble() ?? 0.0;
      totals[currency] = (totals[currency] ?? 0.0) + balance;
    }
    return totals;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════
  String _currencySymbol(String code) =>
      _currencyInfo[code]?['symbol'] ?? code;

  String _formatWithSymbol(double amount, String currency) {
    final symbol = _currencySymbol(currency);
    return '${CurrencyFormatter.formatValue(amount)} $symbol';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet, size: 22),
              const SizedBox(width: 8),
              const Text('الديون', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.person_remove, size: 20),
                text: 'ديون العملاء',
              ),
              Tab(
                icon: Icon(Icons.business, size: 20),
                text: 'ديون صاحب العمل',
              ),
            ],
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Search & Filter Bar ──────────────────────────
                  _buildSearchAndFilterBar(theme),

                  // ── Tab Content ──────────────────────────────────
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCustomerDebtsTab(theme),
                        _buildBusinessDebtsTab(theme),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SEARCH & FILTER BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildSearchAndFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        children: [
          // Search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو رقم الهاتف...',
              hintStyle: TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 10),

          // Currency filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _currencyFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _currencyFilters[index];
                final isSelected = _selectedCurrency == filter;
                return _buildFilterChip(filter, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedCurrency = label),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: AppConstants.animationDurationShort,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CUSTOMER DEBTS TAB (ديون العملاء)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildCustomerDebtsTab(ThemeData theme) {
    final debtCustomers = _debtCustomers;
    final totals = _customerDebtTotals;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Total Summary Card ──────────────────────────────────
          SliverToBoxAdapter(
            child: _buildTotalSummaryCard(
              theme: theme,
              totals: totals,
              title: 'إجمالي ديون العملاء',
              icon: Icons.person_remove,
              accentColor: AppColors.error,
              count: debtCustomers.length,
              countLabel: 'عميل مدين',
            ),
          ),

          // ── Customer Debt List ──────────────────────────────────
          if (debtCustomers.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(
                icon: Icons.emoji_emotions,
                title: 'لا توجد ديون عملاء',
                subtitle: 'جميع العملاء ليس لديهم رصيد مستحق',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList.separated(
                itemCount: debtCustomers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _buildCustomerDebtCard(theme, debtCustomers[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomerDebtCard(ThemeData theme, Map<String, dynamic> customer) {
    final name = customer['name'] as String? ?? 'بدون اسم';
    final phone = customer['phone'] as String? ?? '';
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = customer['currency'] as String? ?? 'YER';
    final creditLimit = (customer['credit_limit'] as num?)?.toDouble() ?? 0.0;
    final hasCreditLimit = creditLimit > 0;
    final isOverLimit = hasCreditLimit && balance > creditLimit;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isOverLimit
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showCustomerInvoices(context, customer),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1) : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOverLimit) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'تجاوز الحد',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ],
                    if (hasCreditLimit) ...[
                      const SizedBox(height: 4),
                      _buildCreditLimitBar(balance, creditLimit),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatValue(balance),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currencySymbol(currency),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 6),
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUSINESS OWNER DEBTS TAB (ديون صاحب العمل)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildBusinessDebtsTab(ThemeData theme) {
    final debtSuppliers = _debtSuppliers;
    final debtAccounts = _debtExpenseAccounts;
    final totals = _businessDebtTotals;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Total Summary Card ──────────────────────────────────
          SliverToBoxAdapter(
            child: _buildTotalSummaryCard(
              theme: theme,
              totals: totals,
              title: 'إجمالي ديون صاحب العمل',
              icon: Icons.business,
              accentColor: AppColors.warning,
              count: debtSuppliers.length + debtAccounts.length,
              countLabel: 'مورد/حساب مستحق',
            ),
          ),

          // ── Supplier Debts Section ──────────────────────────────
          if (debtSuppliers.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        size: 16,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ديون الموردين',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${debtSuppliers.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList.separated(
                itemCount: debtSuppliers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _buildSupplierDebtCard(theme, debtSuppliers[index]),
              ),
            ),
          ],

          // ── Expense/Debt Accounts Section ───────────────────────
          if (debtAccounts.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.bookmark,
                        size: 16,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'حسابات الخصوم المستحقة',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${debtAccounts.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList.separated(
                itemCount: debtAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _buildDebtAccountCard(theme, debtAccounts[index]),
              ),
            ),
          ],

          // ── Empty State ─────────────────────────────────────────
          if (debtSuppliers.isEmpty && debtAccounts.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(
                icon: Icons.emoji_emotions,
                title: 'لا توجد ديون على صاحب العمل',
                subtitle: 'لا يوجد رصيد مستحق للموردين أو حسابات الخصوم',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSupplierDebtCard(ThemeData theme, Map<String, dynamic> supplier) {
    final name = supplier['name'] as String? ?? 'بدون اسم';
    final phone = supplier['phone'] as String? ?? '';
    final balance = (supplier['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = supplier['currency'] as String? ?? 'YER';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showSupplierInvoices(context, supplier),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.local_shipping,
                    size: 20,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatValue(balance),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currencySymbol(currency),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 6),
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebtAccountCard(ThemeData theme, Map<String, dynamic> account) {
    final name = account['name_ar'] as String? ?? 'حساب بدون اسم';
    final balance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = account['currency'] as String? ?? 'YER';
    final accountCode = account['account_code'] as String? ?? '';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  Icons.bookmark,
                  size: 20,
                  color: AppColors.info,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 13,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        accountCode,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'خصم',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.formatValue(balance),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.info,
                  ),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currencySymbol(currency),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SHARED COMPONENTS
  // ═══════════════════════════════════════════════════════════════════

  /// Total debt summary card shown at top of each tab
  Widget _buildTotalSummaryCard({
    required ThemeData theme,
    required Map<String, double> totals,
    required String title,
    required IconData icon,
    required Color accentColor,
    required int count,
    required String countLabel,
  }) {
    final grandTotal = totals.values.fold(0.0, (sum, v) => sum + v);
    final hasMultipleCurrencies = totals.length > 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.1),
            accentColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
              // Count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count $countLabel',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Currency breakdowns
          if (totals.isEmpty)
            Text(
              '0.00',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
              textDirection: TextDirection.ltr,
            )
          else if (!hasMultipleCurrencies)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  CurrencyFormatter.formatValue(grandTotal),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                  ),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currencySymbol(totals.keys.first),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: totals.entries.map((entry) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        CurrencyFormatter.formatValue(entry.value),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currencySymbol(entry.key),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accentColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// Credit limit progress bar
  Widget _buildCreditLimitBar(double balance, double creditLimit) {
    final percentage = (balance / creditLimit).clamp(0.0, 1.5);
    final isOverLimit = balance > creditLimit;

    Color barColor;
    if (percentage <= 0.5) {
      barColor = AppColors.success;
    } else if (percentage <= 0.8) {
      barColor = AppColors.warning;
    } else {
      barColor = AppColors.error;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'سقف الدين: ${CurrencyFormatter.formatValue(creditLimit)}',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
              ),
              textDirection: TextDirection.ltr,
            ),
            const Spacer(),
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isOverLimit ? AppColors.error : barColor,
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage > 1.0 ? 1.0 : percentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              isOverLimit ? AppColors.error : barColor,
            ),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  /// Empty state widget
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INVOICE DETAIL BOTTOM SHEETS
  // ═══════════════════════════════════════════════════════════════════

  /// Show invoices for a specific customer
  void _showCustomerInvoices(
      BuildContext context, Map<String, dynamic> customer) {
    final customerId = customer['id'] as int;
    final name = customer['name'] as String? ?? 'بدون اسم';
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = customer['currency'] as String? ?? 'YER';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CustomerInvoicesSheet(
        customerId: customerId,
        customerName: name,
        balance: balance,
        currency: currency,
      ),
    );
  }

  /// Show invoices for a specific supplier
  void _showSupplierInvoices(
      BuildContext context, Map<String, dynamic> supplier) {
    final supplierId = supplier['id'] as int;
    final name = supplier['name'] as String? ?? 'بدون اسم';
    final balance = (supplier['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = supplier['currency'] as String? ?? 'YER';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SupplierInvoicesSheet(
        supplierId: supplierId,
        supplierName: name,
        balance: balance,
        currency: currency,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CUSTOMER INVOICES BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
class _CustomerInvoicesSheet extends StatefulWidget {
  final int customerId;
  final String customerName;
  final double balance;
  final String currency;

  const _CustomerInvoicesSheet({
    required this.customerId,
    required this.customerName,
    required this.balance,
    required this.currency,
  });

  @override
  State<_CustomerInvoicesSheet> createState() => _CustomerInvoicesSheetState();
}

class _CustomerInvoicesSheetState extends State<_CustomerInvoicesSheet> {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'symbol': 'ر.ي'},
    'SAR': {'symbol': 'ر.س'},
    'USD': {'symbol': '\$'},
  };

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    final db = DatabaseHelper();
    // Get sale invoices for this customer
    final allSaleInvoices = await db.getInvoicesByType('sale');
    final customerInvoices = allSaleInvoices.where(
      (inv) => inv['customer_id'] == widget.customerId,
    ).toList();

    if (!mounted) return;
    setState(() {
      _invoices = customerInvoices;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = _currencyInfo[widget.currency]?['symbol'] ?? widget.currency;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.receipt,
                        size: 18,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'فواتير ${widget.customerName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'إجمالي المستحق',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '${CurrencyFormatter.formatValue(widget.balance)} $symbol',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.error,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Invoice list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _invoices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt,
                                  size: 40,
                                  color: AppColors.textHint,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد فواتير',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _invoices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildInvoiceTile(theme, _invoices[index]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInvoiceTile(ThemeData theme, Map<String, dynamic> invoice) {
    final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
    final remaining = (invoice['remaining'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = invoice['created_at'] as String? ?? '';
    final isPaid = remaining <= 0;
    final invoiceCurrency =
        invoice['currency'] as String? ?? widget.currency;
    final symbol =
        _currencyInfo[invoiceCurrency]?['symbol'] ?? invoiceCurrency;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPaid
            ? AppColors.success.withValues(alpha: 0.04)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt,
                size: 16,
                color: isPaid ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'فاتورة #${invoice['id']?.toString().substring(0, invoice['id'].toString().length > 8 ? 8 : invoice['id'].toString().length) ?? ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isPaid ? 'مدفوعة' : 'غير مكتملة',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isPaid ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'الإجمالي: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${CurrencyFormatter.formatValue(total)} $symbol',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(width: 16),
              Text(
                'المدفوع: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${CurrencyFormatter.formatValue(paidAmount)} $symbol',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          if (!isPaid) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'المتبقي: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatValue(remaining)} $symbol',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ],
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              createdAt.substring(0, createdAt.length > 16 ? 16 : createdAt.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textHint,
                fontSize: 10,
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SUPPLIER INVOICES BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
class _SupplierInvoicesSheet extends StatefulWidget {
  final int supplierId;
  final String supplierName;
  final double balance;
  final String currency;

  const _SupplierInvoicesSheet({
    required this.supplierId,
    required this.supplierName,
    required this.balance,
    required this.currency,
  });

  @override
  State<_SupplierInvoicesSheet> createState() => _SupplierInvoicesSheetState();
}

class _SupplierInvoicesSheetState extends State<_SupplierInvoicesSheet> {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'symbol': 'ر.ي'},
    'SAR': {'symbol': 'ر.س'},
    'USD': {'symbol': '\$'},
  };

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    final db = DatabaseHelper();
    // Get purchase invoices for this supplier
    final allPurchaseInvoices = await db.getInvoicesByType('purchase');
    final supplierInvoices = allPurchaseInvoices.where(
      (inv) => inv['supplier_id'] == widget.supplierId,
    ).toList();

    if (!mounted) return;
    setState(() {
      _invoices = supplierInvoices;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = _currencyInfo[widget.currency]?['symbol'] ?? widget.currency;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.receipt,
                        size: 18,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'فواتير ${widget.supplierName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'إجمالي المستحق',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '${CurrencyFormatter.formatValue(widget.balance)} $symbol',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.warning,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Invoice list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _invoices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt,
                                  size: 40,
                                  color: AppColors.textHint,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد فواتير مشتريات',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _invoices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildInvoiceTile(theme, _invoices[index]),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInvoiceTile(ThemeData theme, Map<String, dynamic> invoice) {
    final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
    final remaining = (invoice['remaining'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = invoice['created_at'] as String? ?? '';
    final isPaid = remaining <= 0;
    final invoiceCurrency =
        invoice['currency'] as String? ?? widget.currency;
    final symbol =
        _currencyInfo[invoiceCurrency]?['symbol'] ?? invoiceCurrency;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPaid
            ? AppColors.success.withValues(alpha: 0.04)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt,
                size: 16,
                color: isPaid ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'فاتورة مشتريات #${invoice['id']?.toString().substring(0, invoice['id'].toString().length > 8 ? 8 : invoice['id'].toString().length) ?? ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isPaid ? 'مدفوعة' : 'غير مكتملة',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isPaid ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'الإجمالي: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${CurrencyFormatter.formatValue(total)} $symbol',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(width: 16),
              Text(
                'المدفوع: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${CurrencyFormatter.formatValue(paidAmount)} $symbol',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          if (!isPaid) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'المتبقي: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatValue(remaining)} $symbol',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ],
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              createdAt.substring(0, createdAt.length > 16 ? 16 : createdAt.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textHint,
                fontSize: 10,
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
        ],
      ),
    );
  }
}
