import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import 'app_router.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/reports/reports_screen.dart';

/// The main scaffold that wraps every "tab" screen.
///
/// Provides:
/// - A custom [AppBar] with logo + action icons
/// - An [EndDrawer] (right side in RTL) with the full navigation menu
/// - A [BottomNavigationBar] with 5 tabs using [IndexedStack]
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  // ── Tab pages (IndexedStack keeps state alive) ────────────────
  final List<Widget> _pages = const [
    DashboardScreen(),
    CustomersScreen(),
    InvoicesScreen(),
    ReportsScreen(),
    _MoreTab(),
  ];

  // ── Bottom nav items ──────────────────────────────────────────
  static const _navItems = [
    BottomNavigationBarItem(
      icon: Icon(PhosphorIconsRegular.house),
      activeIcon: Icon(PhosphorIconsFill.house),
      label: 'الرئيسية',
    ),
    BottomNavigationBarItem(
      icon: Icon(PhosphorIconsRegular.users),
      activeIcon: Icon(PhosphorIconsFill.users),
      label: 'العملاء',
    ),
    BottomNavigationBarItem(
      icon: Icon(PhosphorIconsRegular.receipt),
      activeIcon: Icon(PhosphorIconsFill.receipt),
      label: 'الفواتير',
    ),
    BottomNavigationBarItem(
      icon: Icon(PhosphorIconsRegular.chartBar),
      activeIcon: Icon(PhosphorIconsFill.chartBar),
      label: 'التقارير',
    ),
    BottomNavigationBarItem(
      icon: Icon(PhosphorIconsRegular.dotsThree),
      activeIcon: Icon(PhosphorIconsFill.dotsThree),
      label: 'المزيد',
    ),
  ];

  // ── Drawer menu items ─────────────────────────────────────────
  final _drawerItems = const <_DrawerMenuItem>[
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.arrowDown,
      label: 'تحميل بيانات العميل',
      route: AppRouter.customerLoad,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.uploadSimple,
      label: 'استيراد بيانات العميل',
      route: AppRouter.customerImport,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.users,
      label: 'قائمة العملاء',
      route: AppRouter.customers,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.identificationCard,
      label: 'قائمة المندوبين',
      route: AppRouter.delegates,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.printer,
      label: 'طباعة قائمة العملاء',
      route: AppRouter.customerPrint,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.receipt,
      label: 'فاتورة بيع جديدة',
      route: AppRouter.newSaleInvoice,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.chartLine,
      label: 'تقرير المبيعات اليومية',
      route: AppRouter.dailySalesReport,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.package,
      label: 'قائمة المنتجات',
      route: AppRouter.products,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.money,
      label: 'الطلبات المالية',
      route: AppRouter.financialOrders,
    ),
    _DrawerMenuItem(
      icon: PhosphorIconsRegular.gear,
      label: 'الإعدادات',
      route: AppRouter.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // ── AppBar ────────────────────────────────────────────────
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App logo (SVG)
            SvgPicture.asset(
              'assets/icons/logo.svg',
              width: 32,
              height: 32,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppConstants.appName,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          // WhatsApp icon
          IconButton(
            onPressed: () {
              // TODO: Open WhatsApp support
            },
            icon: const Icon(PhosphorIconsRegular.whatsappLogo),
            tooltip: 'واتساب',
          ),
          // Notifications with badge
          IconButton(
            onPressed: () {
              // TODO: Open notifications
            },
            icon: Badge(
              label: const Text('3'),
              child: const Icon(PhosphorIconsRegular.bell),
            ),
            tooltip: 'الإشعارات',
          ),
          // More / drawer toggle
          IconButton(
            onPressed: () => _openDrawer(context),
            icon: const Icon(PhosphorIconsRegular.list),
            tooltip: 'القائمة',
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ── EndDrawer (appears on right in RTL) ───────────────────
      endDrawer: _buildDrawer(theme, isDark),

      // ── Body (IndexedStack) ───────────────────────────────────
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // ── Bottom navigation bar ─────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: _navItems,
      ),
    );
  }

  // ── Drawer builder ────────────────────────────────────────────
  Widget _buildDrawer(ThemeData theme, bool isDark) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ── Drawer header ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    width: 48,
                    height: 48,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.appFullName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.appSlogan,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Menu items ─────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _drawerItems.length,
                itemBuilder: (context, index) {
                  final item = _drawerItems[index];
                  return ListTile(
                    leading: Icon(
                      item.icon,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                      size: 22,
                    ),
                    title: Text(item.label),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(); // close drawer
                      AppRouter.push(context, item.route);
                    },
                  );
                },
              ),
            ),

            // ── Footer version ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الإصدار ${AppConstants.appVersion}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textHint,
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

// ── Data class for drawer items ──────────────────────────────────
class _DrawerMenuItem {
  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

// ── More tab with quick links to all features ──────────────────
class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('المزيد من الخدمات', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        _MoreTile(icon: PhosphorIconsRegular.storefront, title: 'نقطة البيع', subtitle: 'واجهة بيع سريعة', onTap: () => Navigator.pushNamed(context, AppRouter.pos)),
        _MoreTile(icon: PhosphorIconsRegular.package, title: 'المنتجات والمخزون', subtitle: 'إدارة الأصناف والمخازن', onTap: () => Navigator.pushNamed(context, AppRouter.products)),
        _MoreTile(icon: PhosphorIconsRegular.currencyDollar, title: 'إدارة العملات', subtitle: 'العملات وأسعار الصرف', onTap: () => Navigator.pushNamed(context, AppRouter.currencies)),
        _MoreTile(icon: PhosphorIconsRegular.gear, title: 'الإعدادات', subtitle: 'تخصيص التطبيق', onTap: () => Navigator.pushNamed(context, AppRouter.settings)),
        _MoreTile(icon: PhosphorIconsRegular.headset, title: 'الدعم الفني', subtitle: 'الشكاوى والملاحظات', onTap: () => Navigator.pushNamed(context, AppRouter.support)),
        _MoreTile(icon: PhosphorIconsRegular.receipt, title: 'فاتورة بيع جديدة', subtitle: 'إنشاء فاتورة بيع', onTap: () => Navigator.pushNamed(context, AppRouter.newSaleInvoice)),
        _MoreTile(icon: PhosphorIconsRegular.chartLine, title: 'تقرير المبيعات اليومية', subtitle: 'ملخص اليوم', onTap: () => Navigator.pushNamed(context, AppRouter.dailySalesReport)),
        const Divider(height: 32),
        Text('حول التطبيق', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(PhosphorIconsRegular.info),
          title: Text('الإصدار ${AppConstants.appVersion}'),
          subtitle: Text(AppConstants.appFullName),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(PhosphorIconsRegular.caretLeft, size: 16),
        onTap: onTap,
      ),
    );
  }
}
