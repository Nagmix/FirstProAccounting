import 'package:flutter/material.dart';

import '../screens/dashboard/dashboard_screen.dart';
import '../screens/customers/customers_screen.dart';
import '../screens/customers/add_customer_sheet.dart';
import '../screens/products/products_screen.dart';
import '../screens/products/add_product_sheet.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/invoices/create_invoice_screen.dart';
import '../screens/pos/pos_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/currencies/currencies_screen.dart';
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
  static const String currencies = '/currencies';
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
        customers: (_) => const CustomersScreen(),
        products: (_) => const ProductsScreen(),
        invoices: (_) => const InvoicesScreen(),
        reports: (_) => const ReportsScreen(),
        pos: (_) => const PosScreen(),
        settings: (_) => const SettingsScreen(),
        support: (_) => const SupportScreen(),
        currencies: (_) => const CurrenciesScreen(),
        newSaleInvoice: (_) => const CreateInvoiceScreen(
              invoiceType: 'sale',
            ),
        newPurchaseInvoice: (_) => const CreateInvoiceScreen(
              invoiceType: 'purchase',
            ),
        addCustomer: (_) => const AddCustomerSheet(),
        addProduct: (_) => const AddProductSheet(),
        // Routes without dedicated screens point to related screens
        inventory: (_) => const ProductsScreen(),
        statistics: (_) => const DashboardScreen(),
        dailySalesReport: (_) => const ReportsScreen(),
        delegates: (_) => const SettingsScreen(),
        customerImport: (_) => const CustomersScreen(),
        customerLoad: (_) => const CustomersScreen(),
        customerPrint: (_) => const CustomersScreen(),
        financialOrders: (_) => const SettingsScreen(),
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
