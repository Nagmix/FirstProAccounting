import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
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
      case 1: // مدينون – customers whose net position is debit (they owe us)
        filtered = filtered.where((c) {
          // A customer is a debtor if balanceType is 'debit' with positive balance,
          // or if balanceType is 'credit' but they have switched to debit position
          if (c.balanceType == 'debit' && c.balance > 0) return true;
          return false;
        }).toList();
        break;
      case 2: // دائنون – customers whose net position is credit (we owe them)
        filtered = filtered.where((c) {
          // A customer is a creditor if balanceType is 'credit' with positive balance
          if (c.balanceType == 'credit' && c.balance > 0) return true;
          return false;
        }).toList();
        break;
      // case 0: الكل – no additional filter
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة العملاء'),
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
                    hintText: 'بحث عن عميل...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
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
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final customer = filtered[index];
                          return _CustomerCard(
                            customer: customer,
                            avatarColor: _avatarColor(customer.name),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomerSheet,
        tooltip: 'إضافة عميل',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CUSTOMER CARD
// ═══════════════════════════════════════════════════════════════════
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.avatarColor,
    this.onTap,
    this.onDelete,
  });

  final Customer customer;
  final Color avatarColor;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    // Determine balance display based on balance + balanceType
    final isDebit = customer.balanceType == 'debit' && customer.balance > 0;
    final isCredit = customer.balanceType == 'credit' && customer.balance > 0;
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
                  customer.name.isNotEmpty ? customer.name[0] : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: avatarColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name, phone, balance ─────────────────────────
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
                          size: 14,
                          color: isLight
                              ? AppColors.textHint
                              : AppColors.darkTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          customer.phone ?? '—',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isLight
                                ? AppColors.textSecondary
                                : AppColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Balance ──────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${customer.balance.abs().toStringAsFixed(2)} ${AppConstants.currency}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDebit ? 'مدين' : isCredit ? 'دائن' : 'متساوي',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: balanceColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),

              // ── Arrow icon (RTL – points left visually) ─────
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
