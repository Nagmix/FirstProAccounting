import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/theme/design_system.dart';
import 'package:firstpro/ui/navigation/app_router.dart';
import 'package:firstpro/ui/screens/dashboard/dashboard_screen.dart';
import 'package:firstpro/ui/screens/customers/customers_screen.dart';
import 'package:firstpro/ui/screens/invoices/invoices_screen.dart';
import 'package:firstpro/ui/widgets/custom_bottom_bar.dart';

/// LazyIndexedStack — only builds tabs when they are first selected.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const LazyIndexedStack(
      {super.key, required this.index, required this.children});

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _builtIndices;

  @override
  void initState() {
    super.initState();
    _builtIndices = {widget.index};
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      setState(() {
        _builtIndices.add(widget.index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _builtIndices.contains(i)
              ? widget.children[i]
              : const SizedBox.shrink(),
      ],
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _drawerAnimController;

  final List<Widget> _pages = const [
    DashboardScreen(),
    CustomersScreen(),
    InvoicesScreen(),
    _MoreTab(),
  ];

  // Only 4 items: 2 left (الرئيسية, العملاء) + center FAB + 2 right (الفواتير, المزيد)
  static const _bottomBarItems = [
    CustomBottomBarItem(
      icon: Icons.home,
      activeIcon: Icons.home,
      label: 'الرئيسية',
    ),
    CustomBottomBarItem(
      icon: Icons.people,
      activeIcon: Icons.people,
      label: 'العملاء',
    ),
    CustomBottomBarItem(
      icon: Icons.receipt,
      activeIcon: Icons.receipt,
      label: 'الفواتير',
    ),
    CustomBottomBarItem(
      icon: Icons.more_vert,
      activeIcon: Icons.more_vert,
      label: 'المزيد',
    ),
  ];

  final _drawerItems = const <_DrawerMenuItem>[
    _DrawerMenuItem(
        icon: Icons.receipt,
        label: 'فاتورة بيع جديدة',
        route: AppConstants.newSaleInvoice,
        color: AppColors.accentBlue),
    _DrawerMenuItem(
        icon: Icons.shopping_cart,
        label: 'فاتورة شراء جديدة',
        route: AppConstants.newPurchaseInvoice,
        color: AppColors.accentPink),
    _DrawerMenuItem(
        icon: Icons.description,
        label: 'عروض الأسعار',
        route: AppConstants.quotations,
        color: Colors.purple),
    _DrawerMenuItem(
        icon: Icons.shopping_cart,
        label: 'طلبات الشراء',
        route: AppConstants.purchaseOrders,
        color: Colors.teal),
    _DrawerMenuItem(
        icon: Icons.inventory_2,
        label: 'طلبات البيع',
        route: AppConstants.salesOrders,
        color: Colors.indigo),
    _DrawerMenuItem(
        icon: Icons.history,
        label: 'الورديات',
        route: AppConstants.shifts,
        color: Colors.brown),
    _DrawerMenuItem(
        icon: Icons.people,
        label: 'قائمة العملاء',
        route: AppConstants.customers,
        color: AppColors.primaryLight),
    _DrawerMenuItem(
        icon: Icons.inventory_2,
        label: 'المنتجات والمخزون',
        route: AppConstants.products,
        color: AppColors.secondary),
    _DrawerMenuItem(
        icon: Icons.attach_money,
        label: 'المصروفات',
        route: AppConstants.expenses,
        color: AppColors.error),
    _DrawerMenuItem(
        icon: Icons.person,
        label: 'الموظفين',
        route: AppConstants.employees,
        color: AppColors.accentBlue),
    _DrawerMenuItem(
        icon: Icons.account_balance_wallet,
        label: 'الصناديق والبنوك',
        route: AppConstants.cashBoxes,
        color: AppColors.success),
    // ── New: Currency Exchange, Cash Transfers, Debt Tracking ─────
    _DrawerMenuItem(
        icon: Icons.swap_horiz,
        label: 'مصارفة عملات',
        route: AppConstants.currencyExchange,
        color: Color(0xFF00ACC1)),
    _DrawerMenuItem(
        icon: Icons.swap_horiz,
        label: 'تحويل بين الصناديق',
        route: AppConstants.cashTransfers,
        color: Color(0xFF1E88E5)),
    _DrawerMenuItem(
        icon: Icons.savings,
        label: 'تتبع الديون',
        route: AppConstants.debts,
        color: Color(0xFFE65100)),
    // ───────────────────────────────────────────────────────────────
    _DrawerMenuItem(
        icon: Icons.receipt_long,
        label: 'السندات',
        route: AppConstants.vouchers,
        color: Color(0xFF7B1FA2)),
    _DrawerMenuItem(
        icon: Icons.repeat,
        label: 'الفواتير المتكررة',
        route: AppConstants.recurringInvoices,
        color: Color(0xFF00897B)),
    _DrawerMenuItem(
        icon: Icons.local_shipping,
        label: 'الموردين',
        route: AppConstants.suppliers,
        color: AppColors.info),
    _DrawerMenuItem(
        icon: Icons.warehouse,
        label: 'المستودعات',
        route: AppConstants.warehouses,
        color: AppColors.secondaryDark),
    _DrawerMenuItem(
        icon: Icons.pie_chart,
        label: 'دليل الحسابات',
        route: AppConstants.chartOfAccounts,
        color: AppColors.primary),
    _DrawerMenuItem(
        icon: Icons.balance,
        label: 'التسوية البنكية',
        route: AppConstants.bankReconciliation,
        color: Color(0xFF00897B)),
    _DrawerMenuItem(
        icon: Icons.attach_money,
        label: 'إدارة العملات',
        route: AppConstants.currencies,
        color: AppColors.success),
    _DrawerMenuItem(
        icon: Icons.show_chart,
        label: 'تقرير المبيعات اليومية',
        route: AppConstants.dailySalesReport,
        color: AppColors.warning),
    _DrawerMenuItem(
        icon: Icons.settings,
        label: 'الإعدادات',
        route: AppConstants.settings,
        color: AppColors.textSecondary),
  ];

  @override
  void initState() {
    super.initState();
    _drawerAnimController = AnimationController(
      vsync: this,
      duration: DesignSystem.animMedium,
    );
  }

  @override
  void dispose() {
    _drawerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: _currentIndex == 0
          ? null
          : AppBar(
              centerTitle: false,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    width: 28,
                    height: 28,
                    colorFilter: ColorFilter.mode(
                      isDark ? Colors.white : AppColors.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: isDark ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              actions: [
                // UI-06: removed placeholder "under development" chat
                // and notifications buttons. The notifications screen
                // is accessible from the Drawer instead.
                IconButton(
                  onPressed: () => _openDrawer(context),
                  icon: const Icon(Icons.list),
                  tooltip: 'القائمة',
                ),
                const SizedBox(width: 4),
              ],
            ),
      endDrawer: _buildDrawer(theme, isDark),
      body: LazyIndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: CustomBottomBar(
        selectedIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        onFabTap: _showQuickAddSheet,
        items: _bottomBarItems,
      ),
    );
  }

  void _showQuickAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'إنشاء جديد',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ── Row 1: Original quick-add options ────────────
                  Row(
                    children: [
                      _QuickAddOption(
                        icon: Icons.receipt,
                        label: 'فاتورة بيع',
                        color: AppColors.accentBlue,
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(context, AppConstants.newSaleInvoice);
                        },
                      ),
                      const SizedBox(width: 12),
                      _QuickAddOption(
                        icon: Icons.shopping_cart,
                        label: 'فاتورة شراء',
                        color: AppColors.accentPink,
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(
                              context, AppConstants.newPurchaseInvoice);
                        },
                      ),
                      const SizedBox(width: 12),
                      _QuickAddOption(
                        icon: Icons.person_add,
                        label: 'عميل جديد',
                        color: AppColors.success,
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(context, AppConstants.addCustomer);
                        },
                      ),
                      const SizedBox(width: 12),
                      _QuickAddOption(
                        icon: Icons.inventory_2,
                        label: 'منتج جديد',
                        color: AppColors.secondary,
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(context, AppConstants.addProduct);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Row 2: New dashboard quick actions ───────────
                  Row(
                    children: [
                      _QuickAddOption(
                        icon: Icons.swap_horiz,
                        label: 'مصارفة عملات',
                        color: const Color(0xFF00ACC1),
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(
                              context, AppConstants.currencyExchange);
                        },
                      ),
                      const SizedBox(width: 12),
                      _QuickAddOption(
                        icon: Icons.swap_horiz,
                        label: 'تحويل صناديق',
                        color: const Color(0xFF1E88E5),
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(context, AppConstants.cashTransfers);
                        },
                      ),
                      const SizedBox(width: 12),
                      _QuickAddOption(
                        icon: Icons.savings,
                        label: 'تتبع الديون',
                        color: const Color(0xFFE65100),
                        onTap: () {
                          Navigator.pop(context);
                          AppRouter.push(context, AppConstants.debts);
                        },
                      ),
                      const SizedBox(width: 12),
                      // Empty spacer to balance the row
                      Expanded(child: const SizedBox.shrink()),
                    ],
                  ),
                  SizedBox(height: bottomPadding + 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(ThemeData theme, bool isDark) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ── Drawer Header with gradient ────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryGradientStart,
                    AppColors.primaryGradientEnd
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    width: 48,
                    height: 48,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppConstants.appFullName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.appSlogan,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Drawer items ───────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _drawerItems.length,
                itemBuilder: (context, index) {
                  final item = _drawerItems[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          AppRouter.push(context, item.route);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              // Icon with colored background
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item.icon,
                                  color: item.color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              Icon(
                                Icons.arrow_back_ios,
                                size: 14,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textHint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Version ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الإصدار ${AppConstants.appVersion}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDrawer(BuildContext context) {
    Scaffold.of(context).openEndDrawer();
  }
}

class _DrawerMenuItem {
  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.route,
    this.color = AppColors.primary,
  });
  final IconData icon;
  final String label;
  final String route;
  final Color color;
}

class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزيد'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: kBottomNavigationBarHeight + bottomPadding),
        children: [
          // ── Section: المبيعات والشراء ────────────────────────────
          _buildSectionHeader(context, 'المبيعات والشراء'),
          const SizedBox(height: 8),
          _MoreTile(
            icon: Icons.storefront,
            title: 'نقطة البيع',
            subtitle: 'واجهة بيع سريعة',
            color: AppColors.accentBlue,
            onTap: () => AppRouter.push(context, AppConstants.pos),
          ),
          _MoreTile(
            icon: Icons.description,
            title: 'عروض الأسعار',
            subtitle: 'إدارة عروض الأسعار',
            color: Colors.purple,
            onTap: () => AppRouter.push(context, AppConstants.quotations),
          ),
          _MoreTile(
            icon: Icons.shopping_cart,
            title: 'طلبات الشراء',
            subtitle: 'إدارة طلبات الشراء',
            color: Colors.teal,
            onTap: () => AppRouter.push(context, AppConstants.purchaseOrders),
          ),
          _MoreTile(
            icon: Icons.inventory_2,
            title: 'طلبات البيع',
            subtitle: 'إدارة طلبات البيع',
            color: Colors.indigo,
            onTap: () => AppRouter.push(context, AppConstants.salesOrders),
          ),

          // ── Section: إدارة الأعمال ───────────────────────────────
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'إدارة الأعمال'),
          const SizedBox(height: 8),
          _MoreTile(
            icon: Icons.inventory_2,
            title: 'المنتجات والمخزون',
            subtitle: 'إدارة الأصناف والمخازن',
            color: AppColors.secondary,
            onTap: () => AppRouter.push(context, AppConstants.products),
          ),
          _MoreTile(
            icon: Icons.attach_money,
            title: 'المصروفات',
            subtitle: 'إدارة المصروفات والمصاريف',
            color: AppColors.error,
            onTap: () => AppRouter.push(context, AppConstants.expenses),
          ),
          _MoreTile(
            icon: Icons.person,
            title: 'الموظفين',
            subtitle: 'إدارة الموظفين والأرصدة',
            color: AppColors.accentBlue,
            onTap: () => AppRouter.push(context, AppConstants.employees),
          ),
          _MoreTile(
            icon: Icons.local_shipping,
            title: 'الموردين',
            subtitle: 'إدارة الموردين وأرصدتهم',
            color: AppColors.info,
            onTap: () => AppRouter.push(context, AppConstants.suppliers),
          ),
          _MoreTile(
            icon: Icons.warehouse,
            title: 'المستودعات',
            subtitle: 'إدارة المستودعات والمخازن',
            color: AppColors.secondaryDark,
            onTap: () => AppRouter.push(context, AppConstants.warehouses),
          ),

          // ── Section: المالية والحسابات ──────────────────────────
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'المالية والحسابات'),
          const SizedBox(height: 8),
          _MoreTile(
            icon: Icons.account_balance_wallet,
            title: 'الصناديق والبنوك',
            subtitle: 'إدارة الصناديق والبنوك والأرصدة',
            color: AppColors.success,
            onTap: () => AppRouter.push(context, AppConstants.cashBoxes),
          ),
          // ── New: Currency Exchange ────────────────────────────────
          _MoreTile(
            icon: Icons.swap_horiz,
            title: 'مصارفة عملات',
            subtitle: 'تحويل العملات بأسعار الصرف',
            color: const Color(0xFF00ACC1),
            onTap: () => AppRouter.push(context, AppConstants.currencyExchange),
          ),
          // ── New: Cash Transfers ───────────────────────────────────
          _MoreTile(
            icon: Icons.swap_horiz,
            title: 'تحويل بين الصناديق',
            subtitle: 'تحويل الأموال بين الصناديق والبنوك',
            color: const Color(0xFF1E88E5),
            onTap: () => AppRouter.push(context, AppConstants.cashTransfers),
          ),
          // ── New: Debt Tracking ────────────────────────────────────
          _MoreTile(
            icon: Icons.savings,
            title: 'تتبع الديون',
            subtitle: 'متابعة الديون المستحقة والمطلوبة',
            color: const Color(0xFFE65100),
            onTap: () => AppRouter.push(context, AppConstants.debts),
          ),
          _MoreTile(
            icon: Icons.receipt_long,
            title: 'السندات',
            subtitle: 'سندات القبض والصرف والتسوية',
            color: const Color(0xFF7B1FA2),
            onTap: () => AppRouter.push(context, AppConstants.vouchers),
          ),
          _MoreTile(
            icon: Icons.balance,
            title: 'التسوية البنكية',
            subtitle: 'تسوية كشوفات الحسابات البنكية',
            color: const Color(0xFF00897B),
            onTap: () =>
                AppRouter.push(context, AppConstants.bankReconciliation),
          ),
          _MoreTile(
            icon: Icons.pie_chart,
            title: 'دليل الحسابات',
            subtitle: 'شجرة الحسابات المحاسبية',
            color: AppColors.primary,
            onTap: () => AppRouter.push(context, AppConstants.chartOfAccounts),
          ),
          _MoreTile(
            icon: Icons.attach_money,
            title: 'إدارة العملات',
            subtitle: 'العملات وأسعار الصرف',
            color: AppColors.success,
            onTap: () => AppRouter.push(context, AppConstants.currencies),
          ),
          _MoreTile(
            icon: Icons.bar_chart,
            title: 'التقارير',
            subtitle: 'تقارير المبيعات والمشتريات',
            color: AppColors.primaryLight,
            onTap: () => AppRouter.push(context, AppConstants.reports),
          ),
          _MoreTile(
            icon: Icons.show_chart,
            title: 'الإحصائيات',
            subtitle: 'إحصائيات شاملة',
            color: const Color(0xFF7B1FA2),
            onTap: () => AppRouter.push(context, AppConstants.statistics),
          ),
          _MoreTile(
            icon: Icons.history,
            title: 'الورديات',
            subtitle: 'إدارة ورديات الكاشير',
            color: Colors.brown,
            onTap: () => AppRouter.push(context, AppConstants.shifts),
          ),

          // ── Section: أخرى ────────────────────────────────────────
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'أخرى'),
          const SizedBox(height: 8),
          _MoreTile(
            icon: Icons.settings,
            title: 'الإعدادات',
            subtitle: 'تخصيص التطبيق',
            color: AppColors.textSecondary,
            onTap: () => AppRouter.push(context, AppConstants.settings),
          ),
          _MoreTile(
            icon: Icons.headset,
            title: 'الدعم الفني',
            subtitle: 'الشكاوى والملاحظات',
            color: AppColors.warning,
            onTap: () => AppRouter.push(context, AppConstants.support),
          ),

          const Divider(height: 32),
          Text(
            'حول التطبيق',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text('الإصدار ${AppConstants.appVersion}'),
            subtitle: Text(AppConstants.appFullName),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        shadowColor:
            isDark ? Colors.black26 : AppColors.primary.withValues(alpha: 0.06),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
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
      ),
    );
  }
}

class _QuickAddOption extends StatelessWidget {
  const _QuickAddOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
