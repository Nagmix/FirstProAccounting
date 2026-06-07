import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/helpers/currency_constants.dart';
import '../../../core/helpers/avatar_helper.dart';
import '../../../core/helpers/delete_helper.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/models/cash_box_model.dart';
import '../../widgets/empty_state.dart';
import 'add_cash_box_sheet.dart';
import 'cash_box_detail_screen.dart';

/// Professional Cash Boxes / Banks management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name.
/// - Tab bar: الكل / صناديق / بنوك.
/// - Cash box list with avatar, name, type badge, bank info, and balance.
/// - Compact filter button for currency selection.
/// - FAB for adding a new cash box or bank via [AddCashBoxSheet].
class CashBoxesScreen extends StatefulWidget {
  const CashBoxesScreen({super.key});

  @override
  State<CashBoxesScreen> createState() => _CashBoxesScreenState();
}

class _CashBoxesScreenState extends State<CashBoxesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<CashBox> _cashBoxes = [];
  bool _isLoading = true;

  // Currency filter state
  String _selectedCurrency = 'YER';
  bool _isBalancesLoading = false;
  Map<int, double> _currencyBalances = {};

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
    _loadCashBoxes();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
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
        _loadCurrencyBalances();
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

  // ── Currency balance loading ──────────────────────────────────
  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);
    try {
      final newBalances = <int, double>{};
      final service = locator<CashBoxService>();

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
      if (mounted) setState(() => _isBalancesLoading = false);
    }
  }

  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    _loadCurrencyBalances();
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<CashBox> _filterCashBoxes(int tabIndex) {
    var filtered = _cashBoxes;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((cb) {
        final nameMatch = cb.name.toLowerCase().contains(q);
        final bankMatch = cb.bankName?.toLowerCase().contains(q) ?? false;
        return nameMatch || bankMatch;
      }).toList();
    }

    // Apply tab filter
    switch (tabIndex) {
      case 1:
        filtered = filtered.where((c) => c.isCashBox).toList();
        break;
      case 2:
        filtered = filtered.where((c) => c.isBank).toList();
        break;
    }

    return filtered;
  }

  // ── Open add-cash-box bottom sheet ────────────────────────────
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

  // ── Delete cash box ───────────────────────────────────────────
  Future<void> _deleteCashBox(CashBox cashBox) async {
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: 'الصندوق',
      entityName: cashBox.name,
    );
    if (confirmed) {
      await locator<CashBoxService>().deleteCashBox(cashBox.id!);
      if (mounted) {
        DeleteHelper.showDeleteSuccess(context, 'الصندوق', cashBox.name);
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
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصناديق والبنوك'),
        actions: [
          // Filter button (currency)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              avatar: Icon(Icons.currency_exchange, size: 16, color: AppColors.primary),
              label: Text(
                '$currentSymbol $_selectedCurrency',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
              onPressed: () => CurrencyConstants.showCurrencyFilterPopup(
                context: context,
                selectedCurrency: _selectedCurrency,
                onSelected: _onCurrencyChanged,
              ),
              backgroundColor: AppColors.primary.withOpacity(0.08),
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة صندوق أو بنك',
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
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن صندوق أو بنك...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Summary bar ───────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isLight ? AppColors.border : AppColors.darkBorder, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_cashBoxes.length} صندوق وبنك',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (_isBalancesLoading)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else ...[
                        Icon(Icons.account_balance_wallet, size: 16, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          'العملة: $_selectedCurrency',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textHint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calculate, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'الإجمالي: ${CurrencyFormatter.formatValue(_currencyBalances.values.fold(0.0, (sum, b) => sum + b))} $currentSymbol',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Cash box list ─────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterCashBoxes(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.account_balance_wallet
                              : tabIndex == 1
                                  ? Icons.account_balance_wallet
                                  : Icons.account_balance,
                          title: tabIndex == 0
                              ? 'لا توجد صناديق أو بنوك'
                              : tabIndex == 1
                                  ? 'لا توجد صناديق'
                                  : 'لا توجد بنوك',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة صناديق أو بنوك جديدة لبدء إدارة أموالك'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة صندوق أو بنك' : null,
                          onAction: tabIndex == 0 ? () => _showAddSheet() : null,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadCashBoxes,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80, top: 2),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                          final cashBox = filtered[index];
                          return _CashBoxCard(
                            cashBox: cashBox,
                            avatarColor: AvatarHelper.avatarColor(cashBox.name),
                            displayBalance: _currencyBalances[cashBox.id] ?? 0.0,
                            currencySymbol: CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
                            isLight: isLight,
                            onTap: () => _openDetail(cashBox),
                            onDelete: () => _deleteCashBox(cashBox),
                          );
                        },
                        )
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة صندوق أو بنك',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة صندوق أو بنك'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CASH BOX CARD — Modern, Professional Design (matches _CustomerCard)
// ═══════════════════════════════════════════════════════════════════
class _CashBoxCard extends StatelessWidget {
  const _CashBoxCard({
    required this.cashBox,
    required this.avatarColor,
    required this.displayBalance,
    required this.currencySymbol,
    required this.isLight,
    this.onTap,
    this.onDelete,
  });

  final CashBox cashBox;
  final Color avatarColor;
  final double displayBalance;
  final String currencySymbol;
  final bool isLight;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDebit = displayBalance < 0;
    final isCredit = displayBalance > 0;
    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    final balanceAbs = CurrencyFormatter.formatValue(displayBalance.abs());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppColors.border.withOpacity(0.5) : AppColors.darkBorder.withOpacity(0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.04 : 0.2),
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
                // ── Avatar ───────────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarColor, avatarColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      cashBox.isBank
                          ? Icons.account_balance
                          : Icons.account_balance_wallet,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Name, type badge, bank info ──────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cashBox.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                                color: cashBox.isBank ? AppColors.info : AppColors.secondaryDark,
                              ),
                            ),
                          ),
                          if (cashBox.isBank && cashBox.bankName != null && cashBox.bankName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.business,
                              size: 13,
                              color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                cashBox.bankName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Balance Section with gradient ──────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayBalance != 0
                          ? [balanceColor.withOpacity(0.12), balanceColor.withOpacity(0.04)]
                          : [Colors.grey.withOpacity(0.06), Colors.grey.withOpacity(0.02)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0 ? balanceColor.withOpacity(0.25) : AppColors.border.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDebit ? Icons.trending_down : isCredit ? Icons.trending_up : Icons.remove,
                        size: 14,
                        color: displayBalance != 0 ? balanceColor : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balanceAbs $currencySymbol',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: displayBalance != 0 ? balanceColor : AppColors.textHint,
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
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 12,
                    color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
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
