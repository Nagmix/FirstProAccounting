import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/support/support_screen.dart';

/// Named-route definitions and route-generation helper for FirstPro.
///
/// Using classic [Navigator] with named routes keeps the dependency
/// footprint small while still providing a single source of truth
/// for every screen path in the app.
class AppRouter {
  AppRouter._();

  // ── Route names ────────────────────────────────────────────────
  static const String dashboard = '/dashboard';
  static const String customers = '/customers';
  static const String products = '/products';
  static const String invoices = '/invoices';
  static const String reports = '/reports';
  static const String pos = '/pos';
  static const String settings = '/settings';
  static const String support = '/support';
  static const String newSaleInvoice = '/invoices/new-sale';
  static const String newPurchaseInvoice = '/invoices/new-purchase';
  static const String addCustomer = '/customers/add';
  static const String addProduct = '/products/add';
  static const String inventory = '/products/inventory';
  static const String statistics = '/statistics';
  static const String dailySalesReport = '/reports/daily-sales';
  static const String delegates = '/delegates';
  static const String customerImport = '/customers/import';
  static const String customerLoad = '/customers/load';
  static const String customerPrint = '/customers/print';
  static const String financialOrders = '/financial-orders';

  // ── Route map ──────────────────────────────────────────────────
  static Map<String, WidgetBuilder> get routes => {
        dashboard: (_) => const DashboardScreen(),
        customers: (_) => const _PlaceholderScreen(title: 'قائمة العملاء'),
        products: (_) => const _PlaceholderScreen(title: 'قائمة المنتجات'),
        invoices: (_) => const _PlaceholderScreen(title: 'الفواتير'),
        reports: (_) => const ReportsScreen(),
        pos: (_) => const _PlaceholderScreen(title: 'نقطة البيع'),
        settings: (_) => const SettingsScreen(),
        support: (_) => const SupportScreen(),
        newSaleInvoice: (_) => const _PlaceholderScreen(title: 'فاتورة بيع جديدة'),
        newPurchaseInvoice: (_) =>
            const _PlaceholderScreen(title: 'فاتورة شراء جديدة'),
        addCustomer: (_) => const _PlaceholderScreen(title: 'إضافة عميل'),
        addProduct: (_) => const _PlaceholderScreen(title: 'إضافة منتج'),
        inventory: (_) => const _PlaceholderScreen(title: 'عرض المخزون'),
        statistics: (_) => const _PlaceholderScreen(title: 'الإحصائيات'),
        dailySalesReport: (_) =>
            const _PlaceholderScreen(title: 'تقرير المبيعات اليومية'),
        delegates: (_) => const _PlaceholderScreen(title: 'قائمة المندوبين'),
        customerImport: (_) =>
            const _PlaceholderScreen(title: 'استيراد بيانات العميل'),
        customerLoad: (_) =>
            const _PlaceholderScreen(title: 'تحميل بيانات العميل'),
        customerPrint: (_) =>
            const _PlaceholderScreen(title: 'طباعة قائمة العملاء'),
        financialOrders: (_) =>
            const _PlaceholderScreen(title: 'الطلبات المالية'),
      };

  /// Convenience method – pushes a named route onto the navigator.
  static Future<T?> push<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  /// Convenience method – replaces the current route.
  static Future<T?> replace<T extends Object?, TO extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    TO? result,
  }) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(
      routeName,
      arguments: arguments,
      result: result,
    );
  }
}

/// Temporary placeholder screen used for routes that haven't been
/// fully implemented yet.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction, size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text(
              '$title — قيد التطوير',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
