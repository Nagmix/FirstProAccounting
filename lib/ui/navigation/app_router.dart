import 'package:flutter/material.dart';

import 'package:firstpro/ui/screens/dashboard/dashboard_screen.dart';
import 'package:firstpro/ui/screens/customers/customers_screen.dart';
import 'package:firstpro/ui/screens/customers/add_customer_sheet.dart';
import 'package:firstpro/ui/screens/products/products_screen.dart';
import 'package:firstpro/ui/screens/products/add_product_sheet.dart';
import 'package:firstpro/ui/screens/products/units_screen.dart';
import 'package:firstpro/ui/screens/invoices/invoices_screen.dart';
import 'package:firstpro/ui/screens/invoices/sales_invoices_screen.dart';
import 'package:firstpro/ui/screens/invoices/purchase_invoices_screen.dart';
import 'package:firstpro/ui/screens/invoices/invoice_detail_screen.dart';
import 'package:firstpro/ui/screens/pos/pos_screen.dart';
import 'package:firstpro/ui/screens/reports/reports_screen.dart';
import 'package:firstpro/ui/screens/settings/settings_screen.dart';
import 'package:firstpro/ui/screens/currencies/currencies_screen.dart';
import 'package:firstpro/ui/screens/support/support_screen.dart';
import 'package:firstpro/ui/screens/cash_boxes/cash_boxes_screen.dart';
import 'package:firstpro/ui/screens/accounts/chart_of_accounts_screen.dart';
import 'package:firstpro/ui/screens/accounts/account_ledger_screen.dart';
import 'package:firstpro/ui/screens/suppliers/suppliers_screen.dart';
import 'package:firstpro/ui/screens/warehouses/warehouses_screen.dart';
import 'package:firstpro/ui/screens/warehouses/stock_transfer_screen.dart';
import 'package:firstpro/ui/screens/warehouses/stocktaking_screen.dart';
import 'package:firstpro/ui/screens/expenses/expenses_screen.dart';
import 'package:firstpro/ui/screens/expenses/expense_account_detail_screen.dart';
import 'package:firstpro/ui/screens/employees/employees_screen.dart';
import 'package:firstpro/ui/screens/statistics/statistics_screen.dart';
import 'package:firstpro/ui/screens/audit/accounting_audit_screen.dart';
import 'package:firstpro/ui/screens/quotations/quotations_screen.dart';
import 'package:firstpro/ui/screens/purchase_orders/purchase_orders_screen.dart';
import 'package:firstpro/ui/screens/sales_orders/sales_orders_screen.dart';
import 'package:firstpro/ui/screens/shifts/shifts_screen.dart';
import 'package:firstpro/ui/screens/currency_exchange/currency_exchange_screen.dart';
import 'package:firstpro/ui/screens/cash_transfers/cash_transfer_screen.dart';
import 'package:firstpro/ui/screens/debts/debts_screen.dart';
import 'package:firstpro/ui/screens/app_lock/app_lock_screen.dart';
import 'package:firstpro/ui/screens/notifications/notifications_screen.dart';
import 'package:firstpro/ui/screens/vouchers/vouchers_screen.dart';
import 'package:firstpro/ui/screens/vouchers/create_receipt_payment_voucher_screen.dart';
import 'package:firstpro/ui/screens/daily_ops/daily_operations_screen.dart';
import 'package:firstpro/ui/screens/vouchers/inventory_voucher_screen.dart';
import 'package:firstpro/ui/screens/recurring_invoices/recurring_invoices_screen.dart';
import 'package:firstpro/ui/screens/reports/annual_posting_screen.dart';
import 'package:firstpro/ui/screens/reports/trial_balance_screen.dart';
import 'package:firstpro/ui/screens/reports/financial_statements_screen.dart';
import 'package:firstpro/ui/screens/bank_reconciliation/bank_reconciliation_screen.dart';
import 'package:firstpro/ui/screens/bank_reconciliation/bank_reconciliation_detail_screen.dart';

import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/data/models/account_model.dart';
import 'package:firstpro/ui/screens/license/license_activation_screen.dart';
import 'package:firstpro/ui/screens/license/license_status_screen.dart';

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
        AppConstants.stockTransfer: (_) => const StockTransferScreen(),
        AppConstants.stocktaking: (_) => const StocktakingScreen(),
        AppConstants.expenses: (_) => const ExpensesScreen(),
        AppConstants.employees: (_) => const EmployeesScreen(),
        AppConstants.newSaleInvoice: (_) => const SalesInvoicesScreen(),
        AppConstants.newPurchaseInvoice: (_) => const PurchaseInvoicesScreen(),
        AppConstants.salesInvoices: (_) => const SalesInvoicesScreen(),
        AppConstants.purchaseInvoices: (_) => const PurchaseInvoicesScreen(),
        AppConstants.addCustomer: (_) => const AddCustomerSheet(),
        AppConstants.addProduct: (_) => const AddProductSheet(),
        AppConstants.inventory: (_) => const ProductsScreen(),
        AppConstants.statistics: (_) => const StatisticsScreen(),
        AppConstants.dailySalesReport: (_) => const ReportsScreen(),
        AppConstants.delegates: (_) => const EmployeesScreen(),
        AppConstants.customerImport: (_) => const CustomersScreen(),
        AppConstants.customerLoad: (_) => const CustomersScreen(),
        AppConstants.customerPrint: (_) => const CustomersScreen(),
        AppConstants.financialOrders: (_) => const InvoicesScreen(),
        AppConstants.accountingAudit: (_) => const AccountingAuditScreen(),
        AppConstants.quotations: (_) => const QuotationsScreen(),
        AppConstants.purchaseOrders: (_) => const PurchaseOrdersScreen(),
        AppConstants.salesOrders: (_) => const SalesOrdersScreen(),
        AppConstants.shifts: (_) => const ShiftsScreen(),
        AppConstants.currencyExchange: (_) => const CurrencyExchangeScreen(),
        AppConstants.cashTransfers: (_) => const CashTransferScreen(),
        AppConstants.debts: (_) => const DebtsScreen(),
        AppConstants.appLock: (_) => const AppLockScreen(),
        AppConstants.notifications: (_) => const NotificationsScreen(),
        AppConstants.vouchers: (_) => const VouchersScreen(),
        AppConstants.recurringInvoices: (_) => const RecurringInvoicesScreen(),
        AppConstants.newVoucher: (_) =>
            const CreateReceiptPaymentVoucherScreen(),
        AppConstants.dailyOperations: (_) => const DailyOperationsScreen(),
        AppConstants.inventoryVoucher: (_) => const InventoryVoucherScreen(),
        '/units': (_) => const UnitsScreen(),
        AppConstants.annualPosting: (_) => const AnnualPostingScreen(),
        AppConstants.trialBalance: (_) => const TrialBalanceScreen(),
        AppConstants.financialStatements: (_) =>
            const FinancialStatementsScreen(),
        AppConstants.bankReconciliation: (_) =>
            const BankReconciliationScreen(),
        AppConstants.licenseActivation: (_) => const LicenseActivationScreen(),
        AppConstants.licenseStatus: (_) => const LicenseStatusScreen(),
      };

  static Future<T?> push<T extends Object?>(
      BuildContext context, String routeName,
      {Object? arguments}) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  static Future<T?> replace<T extends Object?, TO extends Object?>(
      BuildContext context, String routeName,
      {Object? arguments, TO? result}) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(routeName,
        arguments: arguments, result: result);
  }

  /// Push the AccountLedgerScreen directly (requires an [Account] object).
  static Future<void> pushAccountLedger(BuildContext context, Account account) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountLedgerScreen(account: account)),
    );
  }

  /// Push the InvoiceDetailScreen directly (requires an invoiceId string).
  static Future<void> pushInvoiceDetail(
      BuildContext context, String invoiceId) {
    return Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId)),
    );
  }

  /// Push the ExpenseAccountDetailScreen directly (requires a sub-account map).
  static Future<void> pushExpenseAccountDetail(
      BuildContext context, Map<String, dynamic> subAccount) {
    return Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ExpenseAccountDetailScreen(subAccount: subAccount)),
    );
  }

  /// Push the BankReconciliationDetailScreen directly.
  static Future<void> pushBankReconciliationDetail(
      BuildContext context, int reconciliationId) {
    return Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => BankReconciliationDetailScreen(
              reconciliationId: reconciliationId)),
    );
  }
}
