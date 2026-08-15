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
      expect(source, contains('allowNegative'),
          reason: 'The sale guard must respect the explicit negative-stock policy.');
      expect(source, contains('quantity > currentStock'),
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

    test('FIFO/LIFO return and fallback paths preserve auditable allocations', () {
      final source = readLib(
        'lib/data/datasources/services/costing_engine_service.dart',
      );

      expect(source, contains('reverseCOGSAllocationsInTransaction'),
          reason: 'Returns must reverse the original cost allocations.');
      expect(source, contains('quantityToReverse'),
          reason: 'Partial returns must cap the quantity reversed per allocation.');
      expect(source, contains('fallback'),
          reason:
              'Negative or missing-layer inventory must still have a reversible cost record.');
    });
  });
}
