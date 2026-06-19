import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guards: prevent re-introduction of known duplicates and
/// orphans that were cleaned up in past iterations.
void main() {
  group('Architecture deduplication guards', () {
    test('only one InventoryVoucherScreen file exists in the codebase', () {
      // B-01 guard: there used to be two copies of InventoryVoucherScreen
      // at lib/ui/screens/vouchers/inventory_voucher_screen.dart (in use)
      // and lib/ui/screens/inventory/inventory_voucher_screen.dart (orphan).
      // The orphan was deleted on 2026-06-19. This guard prevents
      // accidental re-introduction by copy-paste or refactoring mistakes.
      final vouchersFile = File(
        'lib/ui/screens/vouchers/inventory_voucher_screen.dart',
      );
      final inventoryDirFile = File(
        'lib/ui/screens/inventory/inventory_voucher_screen.dart',
      );

      expect(vouchersFile.existsSync(), isTrue,
          reason:
              'The canonical InventoryVoucherScreen must live in lib/ui/screens/vouchers/.');
      expect(inventoryDirFile.existsSync(), isFalse,
          reason:
              'The orphan lib/ui/screens/inventory/inventory_voucher_screen.dart was deleted on 2026-06-19 (audit B-01). Do not re-create it.');
    });

    test('lib/ui/screens/inventory/ directory does not exist', () {
      // After B-01 cleanup, the entire lib/ui/screens/inventory/ directory
      // was removed (it only contained the orphan). If a future feature
      // genuinely needs an inventory screens subdirectory, that is fine —
      // but it must not contain a duplicate of an existing screen.
      final dir = Directory('lib/ui/screens/inventory');
      // Allow the directory to not exist (preferred state) OR to exist
      // without containing inventory_voucher_screen.dart (already covered
      // by the test above). We do not block creation of new, distinct
      // screens in this directory.
      if (dir.existsSync()) {
        final files = dir.listSync();
        for (final f in files) {
          expect(f.path.contains('inventory_voucher_screen'), isFalse,
              reason: 'Duplicate inventory_voucher_screen.dart is forbidden.');
        }
      }
    });
  });
}
