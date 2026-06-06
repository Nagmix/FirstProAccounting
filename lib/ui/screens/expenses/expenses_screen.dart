import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/expense_sub_account_repository.dart';
import 'expense_account_detail_screen.dart';
import 'add_expense_sub_account_sheet.dart';

/// Expense sub-accounts management screen.
///
/// Lists all active expense sub-accounts from the `expense_sub_accounts`
/// table. Each card displays the sub-account name, balance per currency
/// (computed from the expenses table), and the expense count.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

// ── Sorting enum ─────────────────────────────────────────────────────
enum _SortOption { name, date, balance }

class _ExpensesScreenState extends State<ExpensesScreen> {
  // ── Data ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _subAccounts = [];
  final Map<int, Map<String, double>> _balanceCache = {};
  final Map<int, int> _expenseCountCache = {};
  bool _isLoading = true;

  // ── Filters & sorting ──────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  String _currencyFilter = 'all'; // 'all' | 'YER' | 'SAR' | 'USD'
  _SortOption _sortOption = _SortOption.name;

  // ── Totals for summary header ──────────────────────────────────
  final Map<String, double> _totalBalances = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  DATA LOADING
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final repo = locator<ExpenseSubAccountRepository>();
      final accounts = await repo.getAllSubAccounts();

      // Load balances & expense counts in parallel
      final balanceFutures = <Future<Map<String, double>>>[];
      final countFutures = <Future<int>>[];

      for (final a in accounts) {
        final id = a['id'] as int;
        balanceFutures.add(repo.getSubAccountTotalBalance(id));
        countFutures.add(repo.getSubAccountExpenseCount(id));
      }

      final balances = await Future.wait(balanceFutures);
      final counts = await Future.wait(countFutures);

      // Aggregate totals
      final totals = <String, double>{};
      final balanceMap = <int, Map<String, double>>{};
      final countMap = <int, int>{};

      for (int i = 0; i < accounts.length; i++) {
        final id = accounts[i]['id'] as int;
        balanceMap[id] = balances[i];
        countMap[id] = counts[i];
        for (final entry in balances[i].entries) {
          totals[entry.key] = (totals[entry.key] ?? 0.0) + entry.value;
        }
      }

      if (mounted) {
        setState(() {
          _subAccounts = accounts;
          _balanceCache.clear();
          _balanceCache.addAll(balanceMap);
          _expenseCountCache.clear();
          _expenseCountCache.addAll(countMap);
          _totalBalances.clear();
          _totalBalances.addAll(totals);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  FILTERING & SORTING
  // ══════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> get _filteredAccounts {
    var list = List<Map<String, dynamic>>.from(_subAccounts);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      list = list.where((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        final desc = (a['description'] as String? ?? '').toLowerCase();
        final phone = (a['phone'] as String? ?? '').toLowerCase();
        return name.contains(q.toLowerCase()) ||
            desc.contains(q.toLowerCase()) ||
            phone.contains(q.toLowerCase());
      }).toList();
    }

    // Currency filter: only show sub-accounts that have a balance in that currency
    if (_currencyFilter != 'all') {
      list = list.where((a) {
        final id = a['id'] as int;
        final balances = _balanceCache[id] ?? {};
        return balances.containsKey(_currencyFilter);
      }).toList();
    }

    // Sort
    switch (_sortOption) {
      case _SortOption.name:
        list.sort((a, b) =>
            (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
      case _SortOption.date:
        list.sort((a, b) {
          final da = a['created_at'] as String? ?? '';
          final db = b['created_at'] as String? ?? '';
          return db.compareTo(da); // newest first
        });
      case _SortOption.balance:
        list.sort((a, b) {
          final idA = a['id'] as int;
          final idB = b['id'] as int;
          final totalA =
              (_balanceCache[idA] ?? {}).values.fold(0.0, (s, v) => s + v);
          final totalB =
              (_balanceCache[idB] ?? {}).values.fold(0.0, (s, v) => s + v);
          return totalB.compareTo(totalA); // highest first
        });
    }

    return list;
  }

  // ══════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════

  String _currencySymbol(String code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      default:
        return 'ر.ي';
    }
  }

  Color _currencyColor(String code) {
    switch (code) {
      case 'SAR':
        return AppColors.accentGreen;
      case 'USD':
        return AppColors.accentOrange;
      default:
        return AppColors.primary;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حسابات المصروفات'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // ── Summary header ──────────────────────────────
                    SliverToBoxAdapter(child: _buildSummaryHeader(theme, isDark)),

                    // ── Search bar ─────────────────────────────────
                    SliverToBoxAdapter(child: _buildSearchBar(theme, isDark)),

                    // ── Filter & sort row ──────────────────────────
                    SliverToBoxAdapter(child: _buildFilterRow(theme, isDark)),

                    // ── Sub-accounts list ──────────────────────────
                    _filteredAccounts.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(theme),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildSubAccountCard(
                                _filteredAccounts[index],
                                theme,
                                isDark,
                              ),
                              childCount: _filteredAccounts.length,
                            ),
                          ),

                    // Bottom padding for FAB
                    SliverToBoxAdapter(child: SizedBox(height: 100 + bottomPadding)),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddSubAccountSheet,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  WIDGETS
  // ══════════════════════════════════════════════════════════════

  Widget _buildSummaryHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي المصروفات',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTotalBalances(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
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
              _buildSummaryChip(
                icon: Icons.folder_open,
                label: 'عدد الحسابات',
                value: _subAccounts.length.toString(),
              ),
              const SizedBox(width: 12),
              _buildSummaryChip(
                icon: Icons.receipt_long,
                label: 'عدد العمليات',
                value: _expenseCountCache.values
                    .fold(0, (sum, c) => sum + c)
                    .toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Formats the total balances map into a compact multi-currency display.
  String _formatTotalBalances() {
    if (_totalBalances.isEmpty) return CurrencyFormatter.format(0);
    if (_totalBalances.length == 1) {
      final entry = _totalBalances.entries.first;
      return CurrencyFormatter.format(
        entry.value.abs(),
        symbol: _currencySymbol(entry.key),
      );
    }
    // Multi-currency: show each on one line — but for the header we show the
    // first currency and a count.
    final entries = _totalBalances.entries.toList();
    final first = entries.first;
    return '${CurrencyFormatter.format(first.value.abs(), symbol: _currencySymbol(first.key))} +${entries.length - 1}';
  }

  // ── Search bar ────────────────────────────────────────────────

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SearchBar(
        controller: _searchController,
        hintText: 'بحث عن حساب مصروف...',
        leading: const Icon(Icons.search),
        trailing: _searchQuery.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              ]
            : null,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  // ── Filter & sort row ─────────────────────────────────────────

  Widget _buildFilterRow(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          // Currency filter dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currencyFilter,
                  isExpanded: true,
                  icon: const Icon(Icons.filter_list, size: 18),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل العملات')),
                    DropdownMenuItem(value: 'YER', child: Text('ر.ي يمني')),
                    DropdownMenuItem(value: 'SAR', child: Text('ر.س سعودي')),
                    DropdownMenuItem(value: 'USD', child: Text('\$ دولار')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _currencyFilter = val);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Sort dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_SortOption>(
                  value: _sortOption,
                  isExpanded: true,
                  icon: const Icon(Icons.sort, size: 18),
                  items: const [
                    DropdownMenuItem(
                      value: _SortOption.name,
                      child: Text('حسب الاسم'),
                    ),
                    DropdownMenuItem(
                      value: _SortOption.date,
                      child: Text('حسب التاريخ'),
                    ),
                    DropdownMenuItem(
                      value: _SortOption.balance,
                      child: Text('حسب الرصيد'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sortOption = val);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-account card ──────────────────────────────────────────

  Widget _buildSubAccountCard(
    Map<String, dynamic> account,
    ThemeData theme,
    bool isDark,
  ) {
    final id = account['id'] as int;
    final name = account['name'] as String? ?? '';
    final description = account['description'] as String? ?? '';
    final debtCeiling = MoneyHelper.readMoney(account['debt_ceiling']);
    final phone = account['phone'] as String? ?? '';
    final contactMethod = account['contact_method'] as String? ?? '';
    final balances = _balanceCache[id] ?? {};
    final expenseCount = _expenseCountCache[id] ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : AppColors.primary.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(account),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Name + expense count ────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_open,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Expense count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long, size: 14, color: AppColors.info),
                        const SizedBox(width: 4),
                        Text(
                          '$expenseCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_back_ios, size: 16, color: AppColors.textHint),
                ],
              ),

              // ── Row 2: Balances per currency ───────────────────
              if (balances.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: balances.entries.map((entry) {
                    final currencyCode = entry.key;
                    final balance = entry.value;
                    final color = _currencyColor(currencyCode);
                    final symbol = _currencySymbol(currencyCode);
                    final isPositive = balance >= 0;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isPositive ? AppColors.error : AppColors.success)
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isPositive ? AppColors.error : AppColors.success)
                              .withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              symbol,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyFormatter.format(balance.abs()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isPositive ? AppColors.error : AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isPositive ? AppColors.error : AppColors.success)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPositive ? 'عليه' : 'له',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isPositive ? AppColors.error : AppColors.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppColors.textHint),
                      const SizedBox(width: 6),
                      Text(
                        'لا توجد عمليات مسجلة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Row 3: Debt ceiling + phone ────────────────────
              if (debtCeiling > 0 || phone.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (debtCeiling > 0) ...[
                      Icon(Icons.shield, size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'سقف: ${CurrencyFormatter.format(debtCeiling)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (debtCeiling > 0 && phone.isNotEmpty)
                      const SizedBox(width: 16),
                    if (phone.isNotEmpty) ...[
                      Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        phone,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (contactMethod == 'whatsapp') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chat, size: 14, color: AppColors.accentGreen),
                      ] else if (contactMethod == 'sms') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.sms, size: 14, color: AppColors.info),
                      ],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.account_balance_wallet,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _currencyFilter != 'all'
                  ? 'لا توجد نتائج'
                  : 'لا توجد حسابات مصروفات',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _currencyFilter != 'all'
                  ? 'جرّب تغيير معايير البحث أو التصفية'
                  : 'أضف حساب مصروف جديد بالضغط على زر الإضافة',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  ACTIONS
  // ══════════════════════════════════════════════════════════════

  Future<void> _navigateToDetail(Map<String, dynamic> account) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseAccountDetailScreen(subAccount: account),
      ),
    );
    if (!mounted) return;
    if (result == true) _loadData();
  }

  Future<void> _showAddSubAccountSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddExpenseSubAccountSheet(),
    );
    // Refresh data after sheet closes (may have added a sub-account)
    if (mounted) _loadData();
  }
}
