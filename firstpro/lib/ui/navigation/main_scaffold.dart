import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import 'app_router.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/products/products_screen.dart';
import '../screens/pos/pos_screen.dart';
import '../screens/support/support_screen.dart';

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
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'الرئيسية',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.people_outline),
      activeIcon: Icon(Icons.people),
      label: 'العملاء',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.receipt_long_outlined),
      activeIcon: Icon(Icons.receipt_long),
      label: 'الفواتير',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.bar_chart_outlined),
      activeIcon: Icon(Icons.bar_chart),
      label: 'التقارير',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.more_horiz_outlined),
      activeIcon: Icon(Icons.more_horiz),
      label: 'المزيد',
    ),
  ];

  // ── Drawer menu items ─────────────────────────────────────────
  final _drawerItems = const <_DrawerMenuItem>[
    _DrawerMenuItem(
      icon: Icons.cloud_download_outlined,
      label: 'تحميل بيانات العميل',
      route: AppRouter.customerLoad,
    ),
    _DrawerMenuItem(
      icon: Icons.upload_file_outlined,
      label: 'استيراد بيانات العميل',
      route: AppRouter.customerImport,
    ),
    _DrawerMenuItem(
      icon: Icons.people_outline,
      label: 'قائمة العملاء',
      route: AppRouter.customers,
    ),
    _DrawerMenuItem(
      icon: Icons.badge_outlined,
      label: 'قائمة المندوبين',
      route: AppRouter.delegates,
    ),
    _DrawerMenuItem(
      icon: Icons.print_outlined,
      label: 'طباعة قائمة العملاء',
      route: AppRouter.customerPrint,
    ),
    _DrawerMenuItem(
      icon: Icons.add_business_outlined,
      label: 'فاتورة بيع جديدة',
      route: AppRouter.newSaleInvoice,
    ),
    _DrawerMenuItem(
      icon: Icons.summarize_outlined,
      label: 'تقرير المبيعات اليومية',
      route: AppRouter.dailySalesReport,
    ),
    _DrawerMenuItem(
      icon: Icons.inventory_2_outlined,
      label: 'قائمة المنتجات',
      route: AppRouter.products,
    ),
    _DrawerMenuItem(
      icon: Icons.request_quote_outlined,
      label: 'الطلبات المالية',
      route: AppRouter.financialOrders,
    ),
    _DrawerMenuItem(
      icon: Icons.settings_outlined,
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
            icon: const Icon(Icons.chat_outlined),
            tooltip: 'واتساب',
          ),
          // Notifications with badge
          IconButton(
            onPressed: () {
              // TODO: Open notifications
            },
            icon: Badge(
              label: const Text('3'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'الإشعارات',
          ),
          // More / drawer toggle
          IconButton(
            onPressed: () => _openDrawer(context),
            icon: const Icon(Icons.menu),
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
        _MoreTile(icon: Icons.point_of_sale, title: 'نقطة البيع', subtitle: 'واجهة بيع سريعة', onTap: () => Navigator.pushNamed(context, AppRouter.pos)),
        _MoreTile(icon: Icons.inventory_2_outlined, title: 'المنتجات والمخزون', subtitle: 'إدارة الأصناف والمخازن', onTap: () => Navigator.pushNamed(context, AppRouter.products)),
        _MoreTile(icon: Icons.settings_outlined, title: 'الإعدادات', subtitle: 'تخصيص التطبيق', onTap: () => Navigator.pushNamed(context, AppRouter.settings)),
        _MoreTile(icon: Icons.support_agent_outlined, title: 'الدعم الفني', subtitle: 'الشكاوى والملاحظات', onTap: () => Navigator.pushNamed(context, AppRouter.support)),
        _MoreTile(icon: Icons.add_business_outlined, title: 'فاتورة بيع جديدة', subtitle: 'إنشاء فاتورة بيع', onTap: () => Navigator.pushNamed(context, AppRouter.newSaleInvoice)),
        _MoreTile(icon: Icons.summarize_outlined, title: 'تقرير المبيعات اليومية', subtitle: 'ملخص اليوم', onTap: () => Navigator.pushNamed(context, AppRouter.dailySalesReport)),
        const Divider(height: 32),
        Text('حول التطبيق', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.info_outline),
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
        trailing: const Icon(Icons.arrow_back_ios_new, size: 16),
        onTap: onTap,
      ),
    );
  }
}
