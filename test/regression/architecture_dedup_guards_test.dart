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

    test('ThermalPrinterService orphan is not re-introduced (B-02)', () {
      // B-02 guard: ThermalPrinterService (BLE-based, flutter_blue_plus)
      // was an orphan service that was never called from any screen. The
      // active printer service is BluetoothPrinterService (SPP-based,
      // MethodChannel, uses EscPosCommands). The orphan was deleted on
      // 2026-06-19 to remove dead code and the only consumer of the
      // flutter_blue_plus dependency.
      //
      // If a future feature genuinely needs BLE thermal printer support,
      // it should be implemented as a new IPrinterService implementation
      // alongside BluetoothPrinterService, NOT as a second standalone
      // singleton service. This guard catches accidental re-creation.
      final orphanFile = File(
        'lib/core/services/thermal_printer_service.dart',
      );
      expect(orphanFile.existsSync(), isFalse,
          reason: 'ThermalPrinterService was deleted on 2026-06-19 '
              '(audit B-02) as an orphan service with no callers. Do not '
              're-create it. If BLE printer support is needed, implement '
              'it as an IPrinterService subclass alongside '
              'BluetoothPrinterService.');
    });

    test('BluetoothPrinterService is the only printer service in lib/', () {
      // After B-02 cleanup, only BluetoothPrinterService should exist.
      // This guard catches accidental introduction of parallel printer
      // services (which would re-introduce the B-02 duplication).
      final libServicesDir = Directory('lib/core/services');
      expect(libServicesDir.existsSync(), isTrue,
          reason: 'lib/core/services/ must exist (it contains '
              'BluetoothPrinterService, InvoicePdfService, etc.).');

      final printerFiles = libServicesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().contains('printer'))
          .where((f) => !f.path.endsWith('bluetooth_printer_service.dart'))
          .where((f) => !f.path.endsWith('bluetooth_printer_settings_screen.dart'))
          .toList();

      // Allow invoice_pdf_service.dart (PDF generation, not a printer
      // service in the Bluetooth sense) and thermal_printer_service.dart
      // (already guarded above). The only allowed *printer_service.dart
      // is bluetooth_printer_service.dart.
      final unexpected = printerFiles.where((f) {
        final name = f.path.split('/').last;
        return name != 'invoice_pdf_service.dart';
      }).toList();

      expect(unexpected, isEmpty,
          reason: 'B-02: only bluetooth_printer_service.dart should '
              'exist as a printer service. Found unexpected: '
              '${unexpected.map((f) => f.path).join(', ')}.');
    });
  });
}
