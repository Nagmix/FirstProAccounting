import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deep accounting audit regressions', () {
    String readLib(String relativePath) {
      final file = File(relativePath);
      expect(file.existsSync(), isTrue,
          reason: 'Expected source file is missing: $relativePath');
      return file.readAsStringSync();
    }

    test('sale path rejects missing products and stock overdraw', () {
      final source = readLib(
        'lib/data/datasources/repositories/invoice_repository.dart',
      );

      expect(source, contains("productRow.isEmpty"),
          reason:
              'A sale line must fail atomically when its product no longer exists.');
      expect(source, contains('allowNeg'),
          reason: 'The sale guard must respect the explicit negative-stock policy.');
      expect(source, contains('baseQuantity > currentStock'),
          reason:
              'Tracked products must not be sold above available stock unless explicitly allowed.');
      expect(source, contains("track_stock"),
          reason: 'Non-stock items must bypass stock mutation and COGS allocation.');
      expect(source, contains('warehouse_id = ? OR warehouse_id IS NULL'),
          reason: 'Invoice products must be scoped to the selected warehouse.');
    });

    test('invoice total is recomputed and checked at the repository boundary', () {
      final source = readLib(
        'lib/data/datasources/repositories/invoice_repository.dart',
      );

      expect(source, contains('calculatedSubtotal'),
          reason: 'The repository must derive subtotal from invoice lines.');
      expect(source, contains('expectedTotal'),
          reason:
              'The repository must validate total against subtotal, discount, tax and transport.');
      expect(
        source,
        contains('declaredSubtotal - discountAmount + taxAmount + transportCharges'),
      );
    });

    test('P&L excludes cancelled invoices and reads COGS allocations', () {
      final source = readLib(
        'lib/data/datasources/services/report_service.dart',
      );

      expect(source, contains("status != 'cancelled'"),
          reason: 'Cancelled invoices must not contribute to P&L.');
      expect(source, contains('movement_cost_allocations'),
          reason:
              'Reported COGS must be based on the same FIFO/LIFO allocations used by posting.');
      expect(source, contains('tax_amount'),
          reason: 'Sales revenue in P&L must be separated from VAT.');
    });

    test('cost-layer initialization is isolated by warehouse', () {
      final source = readLib(
        'lib/data/datasources/services/costing_engine_service.dart',
      );

      expect(source, contains('product_id = ? AND warehouse_id = ?'),
          reason:
              'Existing cost-layer initialization must distinguish the same product across warehouses.');
      expect(source, contains('warehouse_id IS NULL'),
          reason: 'Legacy products without a warehouse must still be scoped safely.');
    });

    test('customer and supplier balances derive amounts from the posted ledger', () {
      final customerSource = readLib(
        'lib/data/datasources/repositories/customer_repository.dart',
      );
      final supplierSource = readLib(
        'lib/data/datasources/repositories/supplier_repository.dart',
      );

      expect(customerSource, contains('SUM(t.credit)'));
      expect(customerSource, contains("FROM transactions t"));
      expect(customerSource, contains("i.status != 'cancelled'"));
      expect(customerSource, contains("t.reference_id = 'voucher_'"));
      expect(supplierSource, contains('SUM(t.credit)'));
      expect(supplierSource, contains("FROM transactions t"));
      expect(supplierSource, contains("i.status != 'cancelled'"));
      expect(supplierSource, contains("t.reference_id = 'voucher_'"));
    });

    test('aggregated debt reports use ledger transactions for both entities', () {
      final source = readLib(
        'lib/data/datasources/services/report_service.dart',
      );
      expect(source, contains('Customer receivables derived from posted ledger transactions'));
      expect(source, contains('Supplier payables derived from posted ledger transactions'));
      expect(source, contains('FROM customers c'));
      expect(source, contains('FROM suppliers s'));
      expect(source, contains('INNER JOIN transactions t'));
      expect(source, contains("i.status != 'cancelled'"));
      expect(source, contains("v.is_posted = 1"));
      expect(source, contains('getCustomerStatementReport'));
      expect(source, contains('Shared receivable accounts are safe here'));
      expect(source, contains('t.currency_code = ?'));
    });

    test('customer list chart ranks computed ledger balances, not stored balance columns', () {
      final source = readLib(
        'lib/data/datasources/repositories/customer_repository.dart',
      );
      expect(source, contains('getCustomerBalanceForCurrency(id, currency)'));
      expect(source, contains('ranked.sort'));
      expect(source, contains('MoneyHelper.toCents(signedBalance.abs())'));
    });

    test('posted invoice editing remains blocked safely', () {
      final source = readLib(
        'lib/ui/screens/invoices/create_invoice_screen.dart',
      );
      expect(source, contains('widget.existingInvoice != null'));
      expect(source, contains('تعديل الفاتورة غير متاح بعد الترحيل'));
      expect(source, contains('الإلغاء ثم أنشئ فاتورة تصحيحية'));
    });

    test('customer and supplier lists expose local export actions', () {
      final sharedSource = readLib(
        'lib/ui/screens/shared/entities_screen.dart',
      );
      final customerSource = readLib(
        'lib/ui/screens/customers/customers_screen.dart',
      );
      final supplierSource = readLib(
        'lib/ui/screens/suppliers/suppliers_screen.dart',
      );
      expect(sharedSource, contains('exportEntities'));
      expect(sharedSource, contains('file_download_outlined'));
      expect(customerSource, contains('ExcelExporter.exportGenericReport'));
      expect(supplierSource, contains('ExcelExporter.exportGenericReport'));
    });

    test('FIFO/LIFO return and fallback paths preserve auditable allocations', () {
      final source = readLib(
        'lib/data/datasources/services/costing_engine_service.dart',
      );

      expect(source, contains('reverseCOGSAllocationsInTransaction'),
          reason: 'Returns must reverse the original cost allocations.');
      expect(source, contains('qtyToRestore'),
          reason: 'Partial returns must cap the quantity reversed per allocation.');
      expect(source, contains('fallback'),
          reason:
              'Negative or missing-layer inventory must still have a reversible cost record.');
    });

    test('voucher persistence rejects empty or zero journals and mismatched totals', () {
      final source = readLib(
        'lib/data/datasources/services/cash_box_service.dart',
      );
      expect(source, contains('items.isEmpty'),
          reason: 'A voucher must contain real journal lines.');
      expect(source, contains('totalDebit <= 0.0'),
          reason: 'A zero-value voucher must be rejected.');
      expect(source, contains('voucherTotalAmount'),
          reason: 'The voucher header total must be checked against its lines.');
    });

    test('cash transfers reject invalid source, destination, and currency combinations', () {
      final source = readLib(
        'lib/data/datasources/services/cash_box_service.dart',
      );
      expect(source, contains('amount <= 0'),
          reason: 'Cash transfers must reject zero and negative amounts.');
      expect(source, contains('fromCashBoxId == toCashBoxId'),
          reason: 'A cash transfer must use two distinct cash boxes.');
      expect(source, contains('cashBoxCurrency != transferCurrency'),
          reason: 'Both cash boxes must match the transfer currency.');
    });

    test('expenses reject zero values and cash boxes in another currency', () {
      final source = readLib(
        'lib/data/datasources/repositories/expense_repository.dart',
      );
      expect(source, contains('amount <= 0'),
          reason: 'An expense without a positive amount must not be persisted.');
      expect(source, contains('cashBoxCurrency != expenseCurrency'),
          reason: 'An explicitly selected cash box must match the expense currency.');
      expect(source, contains('amountBaseDifference'),
          reason: 'The base amount must be validated against amount and exchange rate.');
    });

    test('stock transfer materializes a fallback layer when no source layers exist', () {
      final source = readLib(
        'lib/data/datasources/services/stock_service.dart',
      );
      expect(source, contains('remainingToTransfer = quantity'),
          reason: 'The transfer quantity must be handled even when sourceLayers is empty.');
      expect(source, contains("reference_type': 'stock_transfer_fallback'"),
          reason: 'Missing FIFO/LIFO layers must remain auditable and reversible.');
    });

    test('customer data routes expose real import, load, and print screens', () {
      final router = readLib('lib/ui/navigation/app_router.dart');
      final screen = File(
        'lib/ui/screens/customers/customer_data_tools_screen.dart',
      );
      expect(screen.existsSync(), isTrue,
          reason: 'Customer data actions need a real local workflow screen.');
      expect(router, contains('CustomerDataToolsScreen'));
      expect(router, contains('CustomerDataAction.importData'));
      expect(router, contains('CustomerDataAction.loadData'));
      expect(router, contains('CustomerDataAction.printData'));
      expect(router, isNot(contains('AppConstants.customerImport: (_) => const CustomersScreen()')));
    });

    test('entity voucher dialog filters cash boxes by selected currency', () {
      final source = readLib(
        'lib/ui/widgets/entity_detail/entity_detail_state.dart',
      );
      expect(source, contains('cashBoxesForCurrency'),
          reason: 'The voucher dialog must not offer a cash box in another currency.');
      expect(source, contains('selectedCurrency'),
          reason: 'Filtering must use the currency currently selected in the dialog.');
    });
  });
}
