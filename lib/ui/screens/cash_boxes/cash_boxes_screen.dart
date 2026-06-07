import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/models/cash_box_model.dart';
import 'add_cash_box_sheet.dart';
import 'cash_box_detail_screen.dart';

class CashBoxesScreen extends StatefulWidget {
  const CashBoxesScreen({super.key});

  @override
  State<CashBoxesScreen> createState() => _CashBoxesScreenState();
}

class _CashBoxesScreenState extends State<CashBoxesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CashBox> _cashBoxes = [];
  bool _isLoading = true;

  // Currency filter state
  String _selectedCurrency = 'الكل'; // 'الكل', 'YER', 'SAR', 'USD'
  bool _isBalancesLoading = false;

  // Cached balances per cash box for the selected currency
  // Key: cashBoxId, Value: balance for the selected currency
  Map<int, double> _currencyBalances = {};

  /// Currency display info.
  static const _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  /// Currency filter options.
  static const _currencyOptions = ['الكل', 'YER', 'SAR', 'USD'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCashBoxes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCashBoxes() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<CashBoxService>().getAllCashBoxes();
      if (mounted) {
        setState(() {
          _cashBoxes = maps.map((m) => CashBox.fromMap(m)).toList();
          _isLoading = false;
        });
        // Load currency balances if a specific currency is selected
        if (_selectedCurrency != 'الكل') {
          _loadCurrencyBalances();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('حدث خطأ أثناء تحميل البيانات'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Load balances for all cash boxes filtered by the selected currency.
  Future<void> _loadCurrencyBalances() async {
    if (_selectedCurrency == 'الكل') {
      // No need for async balances when showing stored balance
      setState(() {
        _currencyBalances = {};
        _isBalancesLoading = false;
      });
      return;
    }

    setState(() => _isBalancesLoading = true);

    try {
      final newBalances = <int, double>{};
      final service = locator<CashBoxService>();

      // Load balances for all cash boxes in parallel
      final futures = _cashBoxes.map((cb) async {
        if (cb.id != null) {
          final balance = await service.getCashBoxBalanceForCurrency(
            cb.id!,
            _selectedCurrency,
          );
          return MapEntry(cb.id!, balance);
        }
        return null;
      });

      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry != null) {
          newBalances[entry.key] = entry.value;
        }
      }

      if (mounted) {
        setState(() {
          _currencyBalances = newBalances;
          _isBalancesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBalancesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('حدث خطأ أثناء تحميل الأرصدة'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Get the balance for a cash box based on the selected currency filter.
  double _getCashBoxBalance(CashBox cashBox) {
    if (_selectedCurrency == 'الكل') {
      // Use stored balance from CashBox model
      return cashBox.balanceType == 'credit' ? cashBox.balance : -cashBox.balance;
    } else {
      // Use the computed currency balance
      return _currencyBalances[cashBox.id] ?? 0.0;
    }
  }

  /// Get the currency symbol to display based on selected filter.
  String _getCurrencySymbol() {
    if (_selectedCurrency == 'الكل') {
      return 'ر.ي'; // Default symbol for "all" view
    }
    return _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';
  }

  /// Handle currency filter change.
  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    if (currency != 'الكل') {
      _loadCurrencyBalances();
    } else {
      setState(() {
        _currencyBalances = {};
        _isBalancesLoading = false;
      });
    }
  }

  List<CashBox> _filterByTab(int tabIndex) {
    switch (tabIndex) {
      case 1:
        return _cashBoxes.where((c) => c.isCashBox).toList();
      case 2:
        return _cashBoxes.where((c) => c.isBank).toList();
      default:
        return _cashBoxes;
    }
  }

  Future<void> _showAddSheet({CashBox? existing}) async {
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      builder: (context) => AddCashBoxSheet(existing: existing),
    );
    _loadCashBoxes();
  }

  Future<void> _deleteCashBox(CashBox cashBox) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف الصندوق'),
        content: Text('هل أنت متأكد من حذف "${cashBox.name}"؟'),
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
      await locator<CashBoxService>().deleteCashBox(cashBox.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف "${cashBox.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadCashBoxes();
    }
  }

  /// Navigate to CashBoxDetailScreen.
  void _openDetail(CashBox cashBox) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CashBoxDetailScreen(
          cashBox: cashBox,
          initialCurrency: _selectedCurrency,
        ),
      ),
    )
        .then((_) => _loadCashBoxes());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencySymbol = _getCurrencySymbol();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصناديق والبنوك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة',
            onPressed: () => _showAddSheet(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'صناديق'),
            Tab(text: 'بنوك'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Currency Filter Row ──────────────────────────────
                _buildCurrencyFilter(theme, isDark),

                // ── Tab Content ──────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterByTab(tabIndex);

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet,
                                  size: 72, color: AppColors.textHint),
                              const SizedBox(height: 16),
                              Text(
                                tabIndex == 0
                                    ? 'لا توجد صناديق أو بنوك'
                                    : tabIndex == 1
                                        ? 'لا توجد صناديق'
                                        : 'لا توجد بنوك',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () => _showAddSheet(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة جديدة'),
                              ),
                            ],
                          ),
                        );
                      }

                      // Compute total balance for the selected currency
                      double totalBalance = 0;
                      if (!_isBalancesLoading) {
                        for (final cb in filtered) {
                          totalBalance += _getCashBoxBalance(cb);
                        }
                      }

                      return Column(
                        children: [
                          // ── Total balance card ───────────────────────
                          _buildTotalBalanceCard(
                            theme,
                            totalBalance,
                            currencySymbol,
                          ),

                          // ── Cash boxes list ──────────────────────────
                          Expanded(
                            child: _isBalancesLoading
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(top: 32),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 80),
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final cashBox = filtered[index];
                                      final balance =
                                          _getCashBoxBalance(cashBox);
                                      return _CashBoxCard(
                                        cashBox: cashBox,
                                        isDark: isDark,
                                        balance: balance,
                                        currencySymbol: currencySymbol,
                                        onTap: () => _openDetail(cashBox),
                                        onDelete: () =>
                                            _deleteCashBox(cashBox),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة صندوق أو بنك',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ── Currency Filter Widget ────────────────────────────────────────
  Widget _buildCurrencyFilter(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.currency_exchange,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'العملة:',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _currencyOptions.map((option) {
                  final isSelected = _selectedCurrency == option;
                  final label = option == 'الكل'
                      ? 'الكل'
                      : '${_currencyInfo[option]?['symbol'] ?? ''} $option';
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) => _onCurrencyChanged(option),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                      ),
                      backgroundColor: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      selectedColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Total Balance Card Widget ─────────────────────────────────────
  Widget _buildTotalBalanceCard(
    ThemeData theme,
    double totalBalance,
    String currencySymbol,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.account_balance_wallet, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCurrency == 'الكل'
                      ? 'إجمالي الرصيد'
                      : 'إجمالي الرصيد (${_currencyInfo[_selectedCurrency]?['label'] ?? _selectedCurrency})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(totalBalance.abs(),
                      symbol: currencySymbol),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            totalBalance >= 0 ? 'له' : 'عليه',
            style: theme.textTheme.labelLarge?.copyWith(
              color: totalBalance >= 0 ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CASH BOX CARD
// ═══════════════════════════════════════════════════════════════════
class _CashBoxCard extends StatelessWidget {
  const _CashBoxCard({
    required this.cashBox,
    required this.isDark,
    required this.balance,
    required this.currencySymbol,
    this.onTap,
    this.onDelete,
  });

  final CashBox cashBox;
  final bool isDark;
  final double balance;
  final String currencySymbol;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = balance >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ── Icon ────────────────────────────────────────────
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cashBox.isBank
                      ? AppColors.info.withOpacity(0.12)
                      : AppColors.secondaryDark.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  cashBox.isBank
                      ? Icons.account_balance
                      : Icons.account_balance_wallet,
                  color: cashBox.isBank ? AppColors.info : AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 14),

              // ── Name & info ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            cashBox.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cashBox.isBank
                                ? AppColors.info.withOpacity(0.1)
                                : AppColors.secondaryDark.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cashBox.typeAr,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cashBox.isBank
                                  ? AppColors.info
                                  : AppColors.secondaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (cashBox.isBank && cashBox.bankName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${cashBox.bankName}${cashBox.bankBranch != null ? ' - ${cashBox.bankBranch}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Balance ─────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(balance.abs(),
                        symbol: currencySymbol),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCredit ? 'له' : 'عليه',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isCredit ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),

              // ── Arrow icon ─────────────────────────────────────
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color:
                    isDark ? AppColors.darkTextSecondary : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
