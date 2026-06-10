import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/helpers/currency_constants.dart';
import '../../../core/helpers/avatar_helper.dart';
import '../../../core/helpers/delete_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/repositories/expense_sub_account_repository.dart';
import '../../../ui/widgets/empty_state.dart';
import 'expense_account_detail_screen.dart';
import 'add_expense_sub_account_sheet.dart';

/// Professional expense sub-accounts management screen.
///
/// Follows the same design pattern as [CustomersScreen]:
/// - Search bar for filtering by name.
/// - Tab bar: الكل / عليه / له.
/// - Expense sub-account list with avatar, name, and balance.
/// - FAB for adding a new sub-account via [AddExpenseSubAccountSheet].
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _subAccounts = [];
  final Map<int, Map<String, double>> _balanceCache = {};
  final Map<int, int> _expenseCountCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _searchQuery = _searchController.text.trim());
        }
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repo = locator<ExpenseSubAccountRepository>();
      final accounts = await repo.getAllSubAccounts();

      final balanceFutures = <Future<Map<String, double>>>[];
      final countFutures = <Future<int>>[];

      for (final a in accounts) {
        final id = a['id'] as int;
        balanceFutures.add(repo.getSubAccountTotalBalance(id));
        countFutures.add(repo.getSubAccountExpenseCount(id));
      }

      final balances = await Future.wait(balanceFutures);
      final counts = await Future.wait(countFutures);

      final balanceMap = <int, Map<String, double>>{};
      final countMap = <int, int>{};

      for (int i = 0; i < accounts.length; i++) {
        final id = accounts[i]['id'] as int;
        balanceMap[id] = balances[i];
        countMap[id] = counts[i];
      }

      if (mounted) {
        setState(() {
          _subAccounts = accounts;
          _balanceCache.clear();
          _balanceCache.addAll(balanceMap);
          _expenseCountCache.clear();
          _expenseCountCache.addAll(countMap);
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

  // ── Filter logic ──────────────────────────────────────────────
  List<Map<String, dynamic>> _filterSubAccounts(int tabIndex) {
    var filtered = _subAccounts;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        final desc = (a['description'] as String? ?? '').toLowerCase();
        return name.contains(q) || desc.contains(q);
      }).toList();
    }

    // Apply tab filter
    switch (tabIndex) {
      case 1: // عليه – sub-accounts with net debit balance
        filtered = filtered.where((a) {
          final id = a['id'] as int;
          final balances = _balanceCache[id] ?? {};
          final total = balances.values.fold(0.0, (s, v) => s + v);
          return total > 0; // positive = expense (عليه)
        }).toList();
        break;
      case 2: // له – sub-accounts with net credit balance
        filtered = filtered.where((a) {
          final id = a['id'] as int;
          final balances = _balanceCache[id] ?? {};
          final total = balances.values.fold(0.0, (s, v) => s + v);
          return total < 0; // negative = credit (له)
        }).toList();
        break;
      // case 0: الكل – no additional filter
    }

    return filtered;
  }

  // ── Open add-sub-account bottom sheet ─────────────────────────
  Future<void> _showAddSubAccountSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddExpenseSubAccountSheet(),
    );
    _loadData();
  }

  // ── Delete sub-account ────────────────────────────────────────
  Future<void> _deleteSubAccount(Map<String, dynamic> account) async {
    final name = account['name'] as String? ?? '';
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: 'حساب المصروف',
      entityName: name,
    );
    if (confirmed) {
      await locator<ExpenseSubAccountRepository>()
          .deleteSubAccount(account['id'] as int);
      if (mounted) {
        DeleteHelper.showDeleteSuccess(context, 'حساب المصروف', name);
      }
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابات المصروفات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'إضافة حساب',
            onPressed: _showAddSubAccountSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'عليه'),
            Tab(text: 'له'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن حساب مصروف...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Summary bar ───────────────────────────────────────
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLight
                        ? AppColors.surfaceVariant
                        : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            isLight ? AppColors.border : AppColors.darkBorder,
                        width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_subAccounts.length} حساب مصروف',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Sub-accounts list ──────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterSubAccounts(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.account_balance_wallet
                              : tabIndex == 1
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                          title: tabIndex == 0
                              ? 'لا يوجد حسابات مصروفات'
                              : tabIndex == 1
                                  ? 'لا يوجد حسابات عليه'
                                  : 'لا يوجد حسابات له',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة حسابات مصروفات جديدة لبدء إدارة مصاريفك'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة حساب' : null,
                          onAction:
                              tabIndex == 0 ? _showAddSubAccountSheet : null,
                        );
                      }

                      return RefreshIndicator(
                          onRefresh: _loadData,
                          color: AppColors.primary,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final account = filtered[index];
                              return _ExpenseCard(
                                account: account,
                                balanceCache: _balanceCache,
                                expenseCountCache: _expenseCountCache,
                                avatarColor: AvatarHelper.avatarColor(
                                    account['name'] as String? ?? ''),
                                onTap: () {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ExpenseAccountDetailScreen(
                                                  subAccount: account),
                                        ),
                                      )
                                      .then((_) => _loadData());
                                },
                                onDelete: () => _deleteSubAccount(account),
                              );
                            },
                          ));
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSubAccountSheet,
        tooltip: 'إضافة حساب مصروف',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة حساب'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EXPENSE SUB-ACCOUNT CARD – matches _CustomerCard pattern
// ═══════════════════════════════════════════════════════════════════
class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.account,
    required this.balanceCache,
    required this.expenseCountCache,
    required this.avatarColor,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> account;
  final Map<int, Map<String, double>> balanceCache;
  final Map<int, int> expenseCountCache;
  final Color avatarColor;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  String _currencySymbol(String code) => CurrencyConstants.currencySymbol(code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final id = account['id'] as int;
    final name = account['name'] as String? ?? '';
    final description = account['description'] as String? ?? '';
    final balances = balanceCache[id] ?? {};
    final expenseCount = expenseCountCache[id] ?? 0;

    // Compute total balance across all currencies
    final totalBalance = balances.values.fold(0.0, (s, v) => s + v);
    final isDebit = totalBalance > 0;
    final isCredit = totalBalance < 0;

    // Get primary currency and balance for display
    String primaryCurrency = 'YER';
    double primaryBalance = 0.0;
    if (balances.isNotEmpty) {
      primaryCurrency = balances.keys.first;
      primaryBalance = balances[primaryCurrency] ?? 0.0;
    }

    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    final balanceAbs = CurrencyFormatter.formatValue(primaryBalance.abs());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? AppColors.border.withValues(alpha: 0.5)
              : AppColors.darkBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── Avatar (matches CustomerCard/EmployeeCard style) ────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarColor, avatarColor.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Name, description ──────────────────────────
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            description.isNotEmpty
                                ? Icons.description
                                : Icons.receipt_long,
                            size: 13,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              description.isNotEmpty
                                  ? description
                                  : '$expenseCount عملية',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isLight
                                    ? AppColors.textSecondary
                                    : AppColors.darkTextSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Balance Section (gradient badge) ────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: totalBalance != 0
                          ? [
                              balanceColor.withValues(alpha: 0.12),
                              balanceColor.withValues(alpha: 0.04)
                            ]
                          : [
                              Colors.grey.withValues(alpha: 0.06),
                              Colors.grey.withValues(alpha: 0.02)
                            ],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: totalBalance != 0
                          ? balanceColor.withValues(alpha: 0.25)
                          : AppColors.border.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDebit
                            ? Icons.trending_up
                            : isCredit
                                ? Icons.trending_down
                                : Icons.remove,
                        size: 14,
                        color: totalBalance != 0
                            ? balanceColor
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balanceAbs ${_currencySymbol(primaryCurrency)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: totalBalance != 0
                              ? balanceColor
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // ── Arrow icon ──────────────────────────────────
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isLight
                        ? AppColors.surfaceVariant
                        : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 12,
                    color: isLight
                        ? AppColors.textHint
                        : AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
