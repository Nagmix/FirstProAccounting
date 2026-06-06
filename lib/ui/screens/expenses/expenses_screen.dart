import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
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
        if (mounted) setState(() => _searchQuery = _searchController.text.trim());
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف حساب المصروف'),
        content: Text('هل أنت متأكد من حذف حساب المصروف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await locator<ExpenseSubAccountRepository>()
          .deleteSubAccount(account['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف حساب المصروف "$name"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadData();
    }
  }

  // ── Avatar color based on name ────────────────────────────────
  static const List<Color> _avatarColors = [
    Color(0xFF1A237E),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1B5E20),
    Color(0xFF33691E),
  ];

  Color _avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return _avatarColors[hash % _avatarColors.length];
  }

  String _currencySymbol(String code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      default: return 'ر.ي';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابات المصروفات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'تصفية',
            onPressed: () {
              // TODO: Implement advanced filter dialog
            },
          ),
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
                          onAction: tabIndex == 0 ? _showAddSubAccountSheet : null,
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final account = filtered[index];
                          return _ExpenseCard(
                            account: account,
                            balanceCache: _balanceCache,
                            expenseCountCache: _expenseCountCache,
                            avatarColor: _avatarColor(
                                account['name'] as String? ?? ''),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ExpenseAccountDetailScreen(
                                      subAccount: account),
                                ),
                              ).then((_) => _loadData());
                            },
                            onDelete: () => _deleteSubAccount(account),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSubAccountSheet,
        tooltip: 'إضافة حساب مصروف',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
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

  String _currencySymbol(String code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      default: return 'ر.ي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final id = account['id'] as int;
    final name = account['name'] as String? ?? '';
    final description = account['description'] as String? ?? '';
    final phone = account['phone'] as String? ?? '';
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: avatarColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name, description, phone ─────────────────────
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
                        if (description.isNotEmpty) ...[
                          Icon(
                            Icons.description,
                            size: 14,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isLight
                                    ? AppColors.textSecondary
                                    : AppColors.darkTextSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else if (phone.isNotEmpty) ...[
                          Icon(
                            Icons.phone,
                            size: 14,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight
                                  ? AppColors.textSecondary
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                        ] else ...[
                          Icon(
                            Icons.receipt_long,
                            size: 14,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$expenseCount عملية',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight
                                  ? AppColors.textSecondary
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Balance ──────────────────────────────────────
              if (balances.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${CurrencyFormatter.format(primaryBalance.abs())} ${_currencySymbol(primaryCurrency)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDebit
                          ? 'عليه'
                          : isCredit
                              ? 'له'
                              : 'متساوي',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: balanceColor,
                      ),
                    ),
                    if (balances.length > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        '+${balances.length - 1} عملة',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isLight
                              ? AppColors.textHint
                              : AppColors.darkTextSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '0.00 ${AppConstants.currency}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isLight
                            ? AppColors.textSecondary
                            : AppColors.darkTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'لا عمليات',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isLight
                            ? AppColors.textHint
                            : AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 4),

              // ── Arrow icon ───────────────────────────────────
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
