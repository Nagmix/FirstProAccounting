import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/helpers/currency_constants.dart';
import '../../../core/helpers/avatar_helper.dart';
import '../../../core/helpers/delete_helper.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/models/customer_model.dart';
import '../../widgets/empty_state.dart';
import 'add_customer_sheet.dart';
import 'customer_detail_screen.dart';

/// Professional customers management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or phone.
/// - Tab bar: الكل / مدينون / دائنون.
/// - Customer list with avatar, name, phone, and balance.
/// - Compact filter button for currency selection.
/// - FAB for adding a new customer via [AddCustomerSheet].
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Customer> _customers = [];
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
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<CustomerRepository>().getAllCustomers();
      if (mounted) {
        setState(() {
          _customers = maps.map((m) => Customer.fromMap(m)).toList();
          _isLoading = false;
        });
        _loadCurrencyBalances();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Currency balance loading ──────────────────────────────────
  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);
    try {
      final newBalances = <int, double>{};
      final repo = locator<CustomerRepository>();

      final futures = _customers.map((c) async {
        if (c.id != null) {
          final balance = await repo.getCustomerBalanceForCurrency(c.id!, _selectedCurrency);
          return MapEntry(c.id!, balance);
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
  List<Customer> _filterCustomers(int tabIndex) {
    var filtered = _customers;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((c) {
        final nameMatch = c.name.toLowerCase().contains(q);
        final phoneMatch = c.phone?.toLowerCase().contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    // Apply tab filter based on currency-specific balance
    switch (tabIndex) {
      case 1: // مدينون — negative balance (عليه)
        filtered = filtered.where((c) {
          if (c.id == null) return false;
          final balance = _currencyBalances[c.id] ?? 0.0;
          return balance < 0;
        }).toList();
        break;
      case 2: // دائنون — positive balance (له)
        filtered = filtered.where((c) {
          if (c.id == null) return false;
          final balance = _currencyBalances[c.id] ?? 0.0;
          return balance > 0;
        }).toList();
        break;
    }

    return filtered;
  }

  // ── Open add-customer bottom sheet ────────────────────────────
  Future<void> _showAddCustomerSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddCustomerSheet(),
    );
    _loadCustomers();
  }

  // ── Delete customer ───────────────────────────────────────────
  Future<void> _deleteCustomer(Customer customer) async {
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: 'العميل',
      entityName: customer.name,
    );
    if (confirmed) {
      await locator<CustomerRepository>().deleteCustomer(customer.id!);
      if (mounted) {
        DeleteHelper.showDeleteSuccess(context, 'العميل', customer.name);
      }
      _loadCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة العملاء'),
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
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'إضافة عميل',
            onPressed: _showAddCustomerSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'مدينون'),
            Tab(text: 'دائنون'),
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
                    hintText: 'بحث عن عميل بالاسم أو الهاتف...',
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
                      Icon(Icons.people, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_customers.length} عميل',
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

                // ── Customer list ─────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterCustomers(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.people
                              : tabIndex == 1
                                  ? Icons.trending_down
                                  : Icons.trending_up,
                          title: tabIndex == 0
                              ? 'لا يوجد عملاء'
                              : tabIndex == 1
                                  ? 'لا يوجد عملاء مدينون'
                                  : 'لا يوجد عملاء دائنون',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة عملاء جدد لبدء إدارة حساباتك'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة عميل' : null,
                          onAction: tabIndex == 0 ? _showAddCustomerSheet : null,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadCustomers,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80, top: 2),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                          final customer = filtered[index];
                          return _CustomerCard(
                            customer: customer,
                            avatarColor: AvatarHelper.avatarColor(customer.name),
                            displayBalance: _currencyBalances[customer.id] ?? 0.0,
                            currencySymbol: CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
                            isLight: isLight,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailScreen(customer: customer),
                                ),
                              ).then((_) => _loadCustomers());
                            },
                            onDelete: () => _deleteCustomer(customer),
                          );
                        },
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerSheet,
        tooltip: 'إضافة عميل',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة عميل'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CUSTOMER CARD — Modern, Professional Design
// ═══════════════════════════════════════════════════════════════════
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.avatarColor,
    required this.displayBalance,
    required this.currencySymbol,
    required this.isLight,
    this.onTap,
    this.onDelete,
  });

  final Customer customer;
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
          color: isLight ? AppColors.border.withValues(alpha: 0.5) : AppColors.darkBorder.withValues(alpha: 0.5),
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
                // ── Avatar ───────────────────────────────────────
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
                      customer.name.isNotEmpty ? customer.name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Name, phone ──────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
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
                            Icons.phone,
                            size: 13,
                            color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone ?? '—',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Balance Section - الرصيد with color ──────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayBalance != 0
                          ? [balanceColor.withValues(alpha: 0.12), balanceColor.withValues(alpha: 0.04)]
                          : [Colors.grey.withValues(alpha: 0.06), Colors.grey.withValues(alpha: 0.02)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0 ? balanceColor.withValues(alpha: 0.25) : AppColors.border.withValues(alpha: 0.3),
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
