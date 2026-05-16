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
import '../screens/cash_boxes/cash_boxes_screen.dart';
import '../screens/accounts/chart_of_accounts_screen.dart';
import '../screens/accounts/account_ledger_screen.dart';
import '../screens/suppliers/suppliers_screen.dart';
import '../screens/warehouses/warehouses_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/employees/employees_screen.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/account_model.dart';

class AppRouter {
  AppRouter._();

  static Map<String, WidgetBuilder> get routes => {
        AppConstants.dashboard: (_) => const DashboardScreen(),
        AppConstants.customers: (_) => const CustomersScreen(),
        AppConstants.products: (_) => const ProductsScreen(),
        AppConstants.invoices: (_) => const InvoicesScreen(),
        AppConstants.reports: (_) => const ReportsScreen(),
        AppConstants.pos: (_) => const PosScreen(),
        AppConstants.settings: (_) => const SettingsScreen(),
        AppConstants.support: (_) => const SupportScreen(),
        AppConstants.currencies: (_) => const CurrenciesScreen(),
        AppConstants.cashBoxes: (_) => const CashBoxesScreen(),
        AppConstants.chartOfAccounts: (_) => const ChartOfAccountsScreen(),
        AppConstants.suppliers: (_) => const SuppliersScreen(),
        AppConstants.warehouses: (_) => const WarehousesScreen(),
        AppConstants.expenses: (_) => const ExpensesScreen(),
        AppConstants.employees: (_) => const EmployeesScreen(),
        AppConstants.newSaleInvoice: (_) => const CreateInvoiceScreen(invoiceType: 'sale'),
        AppConstants.newPurchaseInvoice: (_) => const CreateInvoiceScreen(invoiceType: 'purchase'),
        AppConstants.addCustomer: (_) => const AddCustomerSheet(),
        AppConstants.addProduct: (_) => const AddProductSheet(),
        AppConstants.inventory: (_) => const ProductsScreen(),
        AppConstants.statistics: (_) => const DashboardScreen(),
        AppConstants.dailySalesReport: (_) => const ReportsScreen(),
        AppConstants.delegates: (_) => const SettingsScreen(),
        AppConstants.customerImport: (_) => const CustomersScreen(),
        AppConstants.customerLoad: (_) => const CustomersScreen(),
        AppConstants.customerPrint: (_) => const CustomersScreen(),
        AppConstants.financialOrders: (_) => const SettingsScreen(),
      };

  static Future<T?> push<T extends Object?>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  static Future<T?> replace<T extends Object?, TO extends Object?>(BuildContext context, String routeName, {Object? arguments, TO? result}) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(routeName, arguments: arguments, result: result);
  }

  /// Push the AccountLedgerScreen directly (requires an [Account] object).
  static Future<void> pushAccountLedger(BuildContext context, Account account) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountLedgerScreen(account: account)),
    );
  }
}
