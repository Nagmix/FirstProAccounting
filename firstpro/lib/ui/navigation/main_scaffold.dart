import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/design_system.dart';
import 'app_router.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../widgets/custom_bottom_bar.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _drawerAnimController;

  final List<Widget> _pages = const [
    DashboardScreen(),
    CustomersScreen(),
    InvoicesScreen(),
    ReportsScreen(),
    _MoreTab(),
  ];

  static const _bottomBarItems = [
    CustomBottomBarItem(
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
      label: 'الرئيسية',
    ),
    CustomBottomBarItem(
      icon: PhosphorIconsRegular.users,
      activeIcon: PhosphorIconsFill.users,
      label: 'العملاء',
    ),
    CustomBottomBarItem(
      icon: PhosphorIconsRegular.receipt,
      activeIcon: PhosphorIconsFill.receipt,
      label: 'الفواتير',
    ),
    CustomBottomBarItem(
      icon: PhosphorIconsRegular.chartBar,
      activeIcon: PhosphorIconsFill.chartBar,
      label: 'التقارير',
    ),
    CustomBottomBarItem(
      icon: PhosphorIconsRegular.dotsThree,
      activeIcon: PhosphorIconsFill.dotsThree,
      label: 'المزيد',
    ),
  ];

  final _drawerItems = const <_DrawerMenuItem>[
    _DrawerMenuItem(icon: PhosphorIconsRegular.receipt, label: 'فاتورة بيع جديدة', route: AppConstants.newSaleInvoice, color: AppColors.accentBlue),
    _DrawerMenuItem(icon: PhosphorIconsRegular.shoppingCart, label: 'فاتورة شراء جديدة', route: AppConstants.newPurchaseInvoice, color: AppColors.accentPink),
    _DrawerMenuItem(icon: PhosphorIconsRegular.users, label: 'قائمة العملاء', route: AppConstants.customers, color: AppColors.primaryLight),
    _DrawerMenuItem(icon: PhosphorIconsRegular.package, label: 'المنتجات والمخزون', route: AppConstants.products, color: AppColors.accentOrange),
    _DrawerMenuItem(icon: PhosphorIconsRegular.currencyDollar, label: 'المصروفات', route: AppConstants.expenses, color: AppColors.error),
    _DrawerMenuItem(icon: PhosphorIconsRegular.user, label: 'الموظفين', route: AppConstants.employees, color: AppColors.accentBlue),
    _DrawerMenuItem(icon: PhosphorIconsRegular.vault, label: 'الصناديق والبنوك', route: AppConstants.cashBoxes, color: AppColors.accentGreen),
    _DrawerMenuItem(icon: PhosphorIconsRegular.truck, label: 'الموردين', route: AppConstants.suppliers, color: AppColors.info),
    _DrawerMenuItem(icon: PhosphorIconsRegular.warehouse, label: 'المستودعات', route: AppConstants.warehouses, color: AppColors.secondaryDark),
    _DrawerMenuItem(icon: PhosphorIconsRegular.chartPie, label: 'دليل الحسابات', route: AppConstants.chartOfAccounts, color: AppColors.primary),
    _DrawerMenuItem(icon: PhosphorIconsRegular.currencyDollar, label: 'إدارة العملات', route: AppConstants.currencies, color: AppColors.success),
    _DrawerMenuItem(icon: PhosphorIconsRegular.chartLine, label: 'تقرير المبيعات اليومية', route: AppConstants.dailySalesReport, color: AppColors.warning),
    _DrawerMenuItem(icon: PhosphorIconsRegular.gear, label: 'الإعدادات', route: AppConstants.settings, color: AppColors.textSecondary),
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
      extendBody: false,
      extendBodyBehindAppBar: true,
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
                IconButton(
                  onPressed: () {},
                  icon: const Icon(PhosphorIconsRegular.whatsappLogo),
                  tooltip: 'واتساب',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(PhosphorIconsRegular.bell),
                  tooltip: 'الإشعارات',
                ),
                IconButton(
                  onPressed: () => _openDrawer(context),
                  icon: const Icon(PhosphorIconsRegular.list),
                  tooltip: 'القائمة',
                ),
                const SizedBox(width: 4),
              ],
            ),
      endDrawer: _buildDrawer(theme, isDark),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Bottom bar
              CustomBottomBar(
                selectedIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                onFabTap: _showQuickAddSheet,
                items: _bottomBarItems,
              ),

              // Center FAB overlapping the bottom bar
              Positioned(
                top: -28,
                child: CenterFabButton(
                  onTap: _showQuickAddSheet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQuickAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
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
              Row(
                children: [
                  _QuickAddOption(
                    icon: PhosphorIconsFill.receipt,
                    label: 'فاتورة بيع',
                    color: AppColors.accentBlue,
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.push(context, AppConstants.newSaleInvoice);
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickAddOption(
                    icon: PhosphorIconsFill.shoppingCart,
                    label: 'فاتورة شراء',
                    color: AppColors.accentPink,
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.push(context, AppConstants.newPurchaseInvoice);
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickAddOption(
                    icon: PhosphorIconsFill.userPlus,
                    label: 'عميل جديد',
                    color: AppColors.accentGreen,
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.push(context, AppConstants.addCustomer);
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickAddOption(
                    icon: PhosphorIconsFill.package,
                    label: 'منتج جديد',
                    color: AppColors.accentOrange,
                    onTap: () {
                      Navigator.pop(context);
                      AppRouter.push(context, AppConstants.addProduct);
                    },
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
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
                  colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    width: 48,
                    height: 48,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                PhosphorIconsRegular.caretLeft,
                                size: 14,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزيد'),
      ),
      body: ListView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120 + bottomPadding),
        children: [
          Text(
            'المزيد من الخدمات',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _MoreTile(
            icon: PhosphorIconsRegular.storefront,
            title: 'نقطة البيع',
            subtitle: 'واجهة بيع سريعة',
            color: AppColors.accentBlue,
            onTap: () => Navigator.pushNamed(context, AppConstants.pos),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.package,
            title: 'المنتجات والمخزون',
            subtitle: 'إدارة الأصناف والمخازن',
            color: AppColors.accentOrange,
            onTap: () => Navigator.pushNamed(context, AppConstants.products),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.vault,
            title: 'الصناديق والبنوك',
            subtitle: 'إدارة الصناديق والبنوك والأرصدة',
            color: AppColors.accentGreen,
            onTap: () => Navigator.pushNamed(context, AppConstants.cashBoxes),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.currencyDollar,
            title: 'المصروفات',
            subtitle: 'إدارة المصروفات والمصاريف',
            color: AppColors.error,
            onTap: () => Navigator.pushNamed(context, AppConstants.expenses),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.user,
            title: 'الموظفين',
            subtitle: 'إدارة الموظفين والأرصدة',
            color: AppColors.accentBlue,
            onTap: () => Navigator.pushNamed(context, AppConstants.employees),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.truck,
            title: 'الموردين',
            subtitle: 'إدارة الموردين وأرصدتهم',
            color: AppColors.info,
            onTap: () => Navigator.pushNamed(context, AppConstants.suppliers),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.warehouse,
            title: 'المستودعات',
            subtitle: 'إدارة المستودعات والمخازن',
            color: AppColors.secondaryDark,
            onTap: () => Navigator.pushNamed(context, AppConstants.warehouses),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.chartPie,
            title: 'دليل الحسابات',
            subtitle: 'شجرة الحسابات المحاسبية',
            color: AppColors.primary,
            onTap: () => Navigator.pushNamed(context, AppConstants.chartOfAccounts),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.currencyDollar,
            title: 'إدارة العملات',
            subtitle: 'العملات وأسعار الصرف',
            color: AppColors.success,
            onTap: () => Navigator.pushNamed(context, AppConstants.currencies),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.receipt,
            title: 'فاتورة بيع جديدة',
            subtitle: 'إنشاء فاتورة بيع',
            color: AppColors.accentBlue,
            onTap: () => Navigator.pushNamed(context, AppConstants.newSaleInvoice),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.shoppingCart,
            title: 'فاتورة شراء جديدة',
            subtitle: 'إنشاء فاتورة شراء',
            color: AppColors.accentPink,
            onTap: () => Navigator.pushNamed(context, AppConstants.newPurchaseInvoice),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.gear,
            title: 'الإعدادات',
            subtitle: 'تخصيص التطبيق',
            color: AppColors.textSecondary,
            onTap: () => Navigator.pushNamed(context, AppConstants.settings),
          ),
          _MoreTile(
            icon: PhosphorIconsRegular.headset,
            title: 'الدعم الفني',
            subtitle: 'الشكاوى والملاحظات',
            color: AppColors.warning,
            onTap: () => Navigator.pushNamed(context, AppConstants.support),
          ),
          const Divider(height: 32),
          Text(
            'حول التطبيق',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.info),
            title: Text('الإصدار ${AppConstants.appVersion}'),
            subtitle: Text(AppConstants.appFullName),
          ),
        ],
      ),
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
        shadowColor: isDark ? Colors.black26 : AppColors.primary.withValues(alpha: 0.06),
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
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  PhosphorIconsRegular.caretLeft,
                  size: 16,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
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
