import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
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

  /// Currency display info.
  static const _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  /// Currency filter options.
  static const _currencyOptions = ['YER', 'SAR', 'USD'];

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
      final q = _searchQuery;
      filtered = filtered.where((c) {
        final nameMatch = c.name.contains(q);
        final phoneMatch = c.phone?.contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    // Apply tab filter based on balance and balance_type
    switch (tabIndex) {
      case 1: // مدينون
        filtered = filtered.where((c) {
          if (c.balanceType == 'debit' && c.balance > 0) return true;
          return false;
        }).toList();
        break;
      case 2: // دائنون
        filtered = filtered.where((c) {
          if (c.balanceType == 'credit' && c.balance > 0) return true;
          return false;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف العميل'),
        content: Text('هل أنت متأكد من حذف العميل "${customer.name}"؟'),
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
      await locator<CustomerRepository>().deleteCustomer(customer.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف العميل "${customer.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadCustomers();
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

  // ── Show currency filter popup ────────────────────────────────
  void _showCurrencyFilterPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تصفية حسب العملة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ..._currencyOptions.map((option) {
                final isSelected = _selectedCurrency == option;
                final label = _currencyInfo[option]?['label'] ?? option;
                final symbol = _currencyInfo[option]?['symbol'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _onCurrencyChanged(option);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.circle_outlined,
                            color: isSelected ? AppColors.primary : AppColors.textHint,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$label ($option)',
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            symbol,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

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
              onPressed: _showCurrencyFilterPopup,
              backgroundColor: AppColors.primary.withOpacity(0.08),
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
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

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80, top: 2),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final customer = filtered[index];
                          return _CustomerCard(
                            customer: customer,
                            avatarColor: _avatarColor(customer.name),
                            displayBalance: _currencyBalances[customer.id] ?? 0.0,
                            currencySymbol: _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
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

    final balanceAbs = displayBalance.abs().toStringAsFixed(2);
    final directionLabel = isDebit ? 'عليه' : isCredit ? 'له' : '—';
    final directionColor = isDebit ? AppColors.error : isCredit ? AppColors.success : AppColors.textHint;

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

                // ── Balance Section ──────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: balanceColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$balanceAbs $currencySymbol',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: balanceColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      directionLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: directionColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),

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
