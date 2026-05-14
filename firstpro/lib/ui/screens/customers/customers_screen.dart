import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/customer_model.dart';
import '../../widgets/empty_state.dart';
import 'add_customer_sheet.dart';

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

  // ── Demo data (will be replaced by real data source) ─────────
  final List<Customer> _customers = [
    Customer(
      id: 1,
      name: 'أحمد محمد العلي',
      phone: '0501234567',
      address: 'الرياض - حي النزهة',
      email: 'ahmed@example.com',
      balance: -1500.00,
      gender: 'male',
    ),
    Customer(
      id: 2,
      name: 'فاطمة عبدالله السعيد',
      phone: '0559876543',
      address: 'جدة - حي الروضة',
      email: 'fatima@example.com',
      balance: 3200.00,
      gender: 'female',
    ),
    Customer(
      id: 3,
      name: 'خالد سعد الدوسري',
      phone: '0541112233',
      address: 'الدمام - حي الفيصلية',
      balance: -750.50,
    ),
    Customer(
      id: 4,
      name: 'نورة إبراهيم القحطاني',
      phone: '0567891234',
      email: 'noura@example.com',
      balance: 0.0,
      gender: 'female',
    ),
    Customer(
      id: 5,
      name: 'محمد يوسف الحربي',
      phone: '0533334444',
      address: 'مكة - العزيزية',
      balance: 4500.00,
      gender: 'male',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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

    // Apply tab filter
    switch (tabIndex) {
      case 1: // مدينون (debtors – negative balance)
        filtered = filtered.where((c) => c.balance < 0).toList();
        break;
      case 2: // دائنون (creditors – positive balance)
        filtered = filtered.where((c) => c.balance > 0).toList();
        break;
      // case 0: الكل – no additional filter
    }

    return filtered;
  }

  // ── Open add-customer bottom sheet ────────────────────────────
  void _showAddCustomerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddCustomerSheet(),
    );
  }

  // ── Avatar color based on name ────────────────────────────────
  static const List<Color> _avatarColors = [
    Color(0xFF1B5E20),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1A237E),
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
              // Focus the search bar below
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
      body: Column(
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
                        ? Icons.people_outline
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
                        // TODO: Navigate to customer detail screen
                      },
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
  });

  final Customer customer;
  final Color avatarColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final isDebtor = customer.balance < 0;
    final isCreditor = customer.balance > 0;
    final balanceColor = isDebtor
        ? AppColors.error
        : isCreditor
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withValues(alpha: 0.15),
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
                          Icons.phone_android,
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
                    isDebtor ? 'مدين' : isCreditor ? 'دائن' : 'متساوي',
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
