import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/expense_sub_account_repository.dart';
import '../../../data/datasources/repositories/expense_repository.dart';
import 'add_expense_screen.dart';

/// Expense Sub-Account Detail / Ledger Screen
/// Displays all expense transactions for a specific sub-account with
/// filtering, statistics, and running balance capabilities.
class ExpenseAccountDetailScreen extends StatefulWidget {
  final Map<String, dynamic> subAccount;

  const ExpenseAccountDetailScreen({super.key, required this.subAccount});

  @override
  State<ExpenseAccountDetailScreen> createState() =>
      _ExpenseAccountDetailScreenState();
}

class _ExpenseAccountDetailScreenState
    extends State<ExpenseAccountDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allExpenses = [];
  List<Map<String, dynamic>> _filteredExpenses = [];

  // Filter state
  int _selectedFilterIndex = 0;
  String? _selectedCurrency;
  DateTimeRange? _dateRange;

  // Statistics
  double _totalDebit = 0.0; // صرف
  double _totalCredit = 0.0; // قبض
  double _netBalance = 0.0;

  // Balances per currency
  Map<String, double> _balancesPerCurrency = {};

  // Sub-account data (refreshable)
  Map<String, dynamic>? _freshSubAccount;

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'الكل'),
    _FilterTab(key: 'صرف', label: 'صرف'),
    _FilterTab(key: 'قبض', label: 'قبض'),
  ];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('الكل', ''),
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  // ── Helpers ─────────────────────────────────────────────────────

  int get _subAccountId => widget.subAccount['id'] as int;
  String get _subAccountName =>
      widget.subAccount['name'] as String? ??
      widget.subAccount['name_ar'] as String? ??
      '';

  String get _subAccountDescription =>
      (widget.subAccount['description'] as String? ?? '').trim();

  String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      case 'YER':
      default:
        return 'ر.ي';
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freshSubAccount = widget.subAccount;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Refresh sub-account data
    final freshData = await locator<ExpenseSubAccountRepository>()
        .getSubAccountById(_subAccountId);
    if (freshData != null) {
      _freshSubAccount = freshData;
    }

    // Load balances per currency
    _balancesPerCurrency = await locator<ExpenseSubAccountRepository>()
        .getSubAccountTotalBalance(_subAccountId);

    // Load expenses
    await _loadExpenses();

    setState(() => _isLoading = false);
  }

  Future<void> _loadExpenses() async {
    final expenses = await locator<ExpenseRepository>()
        .getExpensesBySubAccountId(_subAccountId);

    // Sort by date ascending, then by id for stable ordering
    expenses.sort((a, b) {
      final dateA = a['expense_date'] as String? ??
          a['created_at'] as String? ??
          '';
      final dateB = b['expense_date'] as String? ??
          b['created_at'] as String? ??
          '';
      final cmp = dateA.compareTo(dateB);
      if (cmp != 0) return cmp;
      return (a['id'].toString()).compareTo(b['id'].toString());
    });

    // Calculate running balance for ALL expenses chronologically
    double runningBalance = 0.0;
    for (final e in expenses) {
      final amount = MoneyHelper.readMoney(e['amount']);
      final operationType = e['operation_type'] as String? ?? 'صرف';
      if (operationType == 'صرف') {
        runningBalance += amount;
      } else {
        runningBalance -= amount;
      }
      e['running_balance'] = runningBalance;
    }

    _allExpenses = expenses;
    _applyFilters();
  }

  // ── Filtering ───────────────────────────────────────────────────

  void _applyFilters() {
    var filtered = _allExpenses
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Apply tab filter (operation type)
    final filterKey = _filterTabs[_selectedFilterIndex].key;
    if (filterKey != 'all') {
      filtered = filtered
          .where((e) => e['operation_type'] == filterKey)
          .toList();
    }

    // Apply currency filter
    if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
      filtered = filtered
          .where((e) => e['currency'] == _selectedCurrency)
          .toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((e) {
        final dateStr = e['expense_date'] as String? ??
            e['created_at'] as String? ??
            '';
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_dateRange!.start) &&
              !date.isAfter(
                  _dateRange!.end.add(const Duration(days: 1)));
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // Preserve running balance from full calculation (_allExpenses)
    // instead of recalculating from filtered subset.
    final allBalances = <String, double>{};
    for (final e in _allExpenses) {
      final eId = e['id'] as String?;
      if (eId != null) {
        allBalances[eId] = MoneyHelper.readMoney(e['running_balance']);
      }
    }
    for (final e in filtered) {
      final eId = e['id'] as String?;
      if (eId != null && allBalances.containsKey(eId)) {
        e['running_balance'] = allBalances[eId];
      }
    }

    // Calculate totals from filtered expenses
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final e in filtered) {
      final amount = MoneyHelper.readMoney(e['amount']);
      final operationType = e['operation_type'] as String? ?? 'صرف';

      if (operationType == 'صرف') {
        totalDebit += amount;
      } else {
        totalCredit += amount;
      }
    }

    // Net balance from ALL expenses for the selected currency
    double netBalance = 0.0;
    for (final e in _allExpenses) {
      if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
        final eCurrency = e['currency'] as String? ?? 'YER';
        if (eCurrency != _selectedCurrency) continue;
      }
      final amount = MoneyHelper.readMoney(e['amount']);
      final operationType = e['operation_type'] as String? ?? 'صرف';
      if (operationType == 'صرف') {
        netBalance += amount;
      } else {
        netBalance -= amount;
      }
    }

    setState(() {
      _filteredExpenses = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = netBalance;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _applyFilters();
  }

  // ── Navigation ──────────────────────────────────────────────────

  Future<void> _navigateToAddExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          expenseSubAccountId: _subAccountId,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) _loadData();
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_subAccountName),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Header Card ─────────────────────────────────
                  _buildHeaderCard(theme, isLight),

                  // ── Filter Tabs ─────────────────────────────────
                  _buildFilterTabs(isLight),

                  // ── Date & Currency Filters ─────────────────────
                  _buildFilterBar(isLight),

                  // ── Summary Row ─────────────────────────────────
                  _buildSummaryRow(theme, isLight),

                  // ── Expense List ────────────────────────────────
                  Expanded(
                    child: _filteredExpenses.isEmpty
                        ? _buildEmptyState(theme)
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: _filteredExpenses.length,
                              itemBuilder: (context, index) {
                                return _buildExpenseCard(
                                  _filteredExpenses[index],
                                  theme,
                                  isLight,
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _navigateToAddExpense,
          backgroundColor: AppColors.primary,
          tooltip: 'إضافة مصروف جديد',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  // ── Header Card ─────────────────────────────────────────────────

  Widget _buildHeaderCard(ThemeData theme, bool isLight) {
    // ignore: unused_local_variable
    final subAccount = _freshSubAccount ?? widget.subAccount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _subAccountName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_subAccountDescription.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _subAccountDescription,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Balances per currency
            if (_balancesPerCurrency.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: _balancesPerCurrency.entries.map((entry) {
                  final balance = entry.value;
                  final isPositive = balance >= 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isPositive
                                    ? AppColors.success
                                    : AppColors.error)
                                .withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPositive ? 'صرف' : 'قبض',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${CurrencyFormatter.formatValue(balance.abs())} ${_currencySymbol(entry.key)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Filter Tabs ─────────────────────────────────────────────────

  Widget _buildFilterTabs(bool isLight) {
    return Container(
      height: 44,
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _filterTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return ChoiceChip(
            label: Text(_filterTabs[index].label),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedFilterIndex = index);
              _applyFilters();
            },
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            backgroundColor: isLight
                ? AppColors.surfaceVariant
                : AppColors.darkSurfaceVariant,
            selectedColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  // ── Date & Currency Filters ─────────────────────────────────────

  Widget _buildFilterBar(bool isLight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: Row(
        children: [
          // Date range picker
          Expanded(
            child: InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.date_range,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _dateRange != null
                            ? '${DateFormatter.formatDate(_dateRange!.start)} - ${DateFormatter.formatDate(_dateRange!.end)}'
                            : 'فترة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _dateRange != null
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_dateRange != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _clearDateRange,
                        child: const Icon(Icons.close,
                            size: 14, color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Currency filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedCurrency ?? '',
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _selectedCurrency != null
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              items: _currencyOptions
                  .map((opt) => DropdownMenuItem<String>(
                        value: opt.value,
                        child: Text(opt.key),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCurrency =
                      (value != null && value.isNotEmpty) ? value : null;
                });
                _applyFilters();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary Row ─────────────────────────────────────────────────

  Widget _buildSummaryRow(ThemeData theme, bool isLight) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Total Debit (صرف)
          Expanded(
            child: _buildSummaryItem(
              label: 'صرف (عليه)',
              value: CurrencyFormatter.format(_totalDebit),
              color: AppColors.error,
              icon: Icons.north_west,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isLight ? AppColors.divider : AppColors.darkDivider,
          ),
          // Total Credit (قبض)
          Expanded(
            child: _buildSummaryItem(
              label: 'قبض (له)',
              value: CurrencyFormatter.format(_totalCredit),
              color: AppColors.success,
              icon: Icons.south_east,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isLight ? AppColors.divider : AppColors.darkDivider,
          ),
          // Net Balance
          Expanded(
            child: _buildSummaryItem(
              label: 'الصافي',
              value: CurrencyFormatter.format(_netBalance),
              color: _netBalance >= 0 ? AppColors.primary : AppColors.error,
              icon: Icons.balance,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Expense Card ────────────────────────────────────────────────

  Widget _buildExpenseCard(
    Map<String, dynamic> expense,
    ThemeData theme,
    bool isLight,
  ) {
    final title = expense['title'] as String? ?? 'بدون عنوان';
    final operationType = expense['operation_type'] as String? ?? 'صرف';
    final currency = expense['currency'] as String? ?? 'YER';
    final amount = MoneyHelper.readMoney(expense['amount']);
    final beneficiary = expense['beneficiary'] as String? ?? '';
    final description = expense['description'] as String? ??
        expense['notes'] as String? ?? '';
    final runningBalance =
        (expense['running_balance'] as num?)?.toDouble() ?? 0.0;
    final isSarf = operationType == 'صرف';

    // Parse date
    DateTime? expenseDate;
    final dateStr = expense['expense_date'] as String? ??
        expense['created_at'] as String? ??
        '';
    try {
      expenseDate = DateTime.parse(dateStr);
    } catch (_) {
      expenseDate = null;
    }

    final formattedDate =
        expenseDate != null ? DateFormatter.formatDate(expenseDate) : '';
    final formattedTime =
        expenseDate != null ? DateFormatter.formatTime(expenseDate) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? AppColors.border : AppColors.darkBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Date & Operation Type badge & Running balance
          Row(
            children: [
              // Date badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (formattedTime.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Operation type badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isSarf ? AppColors.error : AppColors.success)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSarf ? Icons.north_west : Icons.south_east,
                      size: 12,
                      color: isSarf ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      operationType,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isSarf ? AppColors.error : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Running balance
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (runningBalance >= 0
                          ? AppColors.primary
                          : AppColors.error)
                      .withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  CurrencyFormatter.format(runningBalance),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: runningBalance >= 0
                        ? AppColors.primary
                        : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Title
          Row(
            children: [
              Icon(Icons.article, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isLight ? AppColors.textPrimary : AppColors.darkTextPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Row 3: Beneficiary (if present)
          if (beneficiary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    beneficiary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Row 4: Description (if present)
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.description, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Row 5: Amount & Currency
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isSarf ? AppColors.error : AppColors.success)
                      .withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSarf ? 'صرف' : 'قبض',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSarf ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${CurrencyFormatter.formatValue(amount)} ${_currencySymbol(currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSarf ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Currency tag
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currency,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.receipt_long,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد مصروفات',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم تسجيل أي مصروفات على هذا الحساب الفرعي بعد',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter Tab Model ──────────────────────────────────────────────

class _FilterTab {
  final String key;
  final String label;
  const _FilterTab({required this.key, required this.label});
}
