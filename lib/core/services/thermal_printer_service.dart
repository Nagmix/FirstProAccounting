import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../di/service_locator.dart';
import '../../data/datasources/repositories/reference_data_repository.dart';
import '../utils/money_helper.dart';

/// Service for Bluetooth thermal printer (80mm) integration.
/// Uses flutter_blue_plus for Bluetooth connectivity and manual ESC/POS
/// commands for receipt printing. This approach is compatible with Dart 3.x.
class ThermalPrinterService {
  ThermalPrinterService._();
  static final ThermalPrinterService _instance = ThermalPrinterService._();
  factory ThermalPrinterService() => _instance;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  String? get connectedDevice => _connectedDevice?.platformName;

  /// Get available Bluetooth devices that support thermal printing.
  /// Scans for BLE devices and collects discovered results.
  Future<List<Map<String, String>>> getAvailableDevices() async {
    try {
      // Start scan
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      // Collect scan results
      final devices = <Map<String, String>>[];
      final results = FlutterBluePlus.scanResults;
      // scanResults is a Stream<List<ScanResult>>, get the latest value
      await for (final list in results) {
        for (final result in list) {
          devices.add({
            'name': result.device.platformName.isNotEmpty
                ? result.device.platformName
                : 'Unknown',
            'mac': result.device.remoteId.str,
          });
        }
        break; // Just get the first emission
      }
      await FlutterBluePlus.stopScan();
      return devices;
    } catch (e) {
      debugPrint('Error getting Bluetooth devices: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth thermal printer by MAC address.
  Future<bool> connect(String macAddress) async {
    try {
      final device = BluetoothDevice.fromId(macAddress);
      await device.connect(timeout: const Duration(seconds: 10));

      // Discover services and find a write characteristic
      final services = await device.discoverServices();
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            _writeCharacteristic = characteristic;
            _connectedDevice = device;
            _isConnected = true;

            // Save the connected device
            await locator<ReferenceDataRepository>().setSetting('thermal_printer_mac', macAddress);

            return true;
          }
        }
      }

      // No write characteristic found
      await device.disconnect();
      _isConnected = false;
      return false;
    } catch (e) {
      debugPrint('Error connecting to printer: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from the printer.
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      _isConnected = false;
      _connectedDevice = null;
      _writeCharacteristic = null;
    } catch (e) {
      debugPrint('Error disconnecting from printer: $e');
    }
  }

  /// Auto-connect to the last used printer.
  Future<bool> autoConnect() async {
    try {
      final mac = await locator<ReferenceDataRepository>().getSetting('thermal_printer_mac');
      if (mac != null && mac.isNotEmpty) {
        return await connect(mac);
      }
      return false;
    } catch (e) {
      debugPrint('Error auto-connecting: $e');
      return false;
    }
  }

  /// Write raw bytes to the printer characteristic.
  Future<bool> _writeBytes(List<int> bytes) async {
    if (_writeCharacteristic == null) return false;
    try {
      await _writeCharacteristic!.write(bytes, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint('Error writing to printer: $e');
      return false;
    }
  }

  /// Print a POS receipt (80mm thermal paper).
  Future<bool> printPosReceipt({
    required String invoiceId,
    required String invoiceType,
    required String customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    required double taxAmount,
    required double total,
    required double paidAmount,
    required double remaining,
    required String paymentMethod,
    required String currency,
    required String date,
  }) async {
    if (!_isConnected) {
      final autoConnected = await autoConnect();
      if (!autoConnected) return false;
    }

    try {
      List<int> bytes = [];

      // Get business info from settings
      final businessName =
          await locator<ReferenceDataRepository>().getSetting('business_name') ?? 'الأول برو المحاسبي';
      final businessPhone = await locator<ReferenceDataRepository>().getSetting('business_phone') ?? '';
      final businessAddress = await locator<ReferenceDataRepository>().getSetting('business_address') ?? '';

      final currencySymbol =
          currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

      // ESC/POS Commands
      bytes += cInit();
      bytes += cTextAlignCenter();
      bytes += cTextSize(2);
      bytes += cText('${_normalizeArabic(businessName)}\n');
      bytes += cTextSize(1);
      if (businessPhone.isNotEmpty) {
        bytes += cText('${_normalizeArabic('هاتف: $businessPhone')}\n');
      }
      if (businessAddress.isNotEmpty) {
        bytes += cText('${_normalizeArabic(businessAddress)}\n');
      }
      bytes += cLine();

      // Invoice type
      final typeLabel = invoiceType == 'sale'
          ? 'فاتورة بيع'
          : (invoiceType == 'purchase' ? 'فاتورة شراء' : 'فاتورة');
      final paymentLabel =
          paymentMethod == 'cash' ? 'نقدي' : (paymentMethod == 'credit' ? 'آجل' : 'بطاقة');
      bytes += cTextSize(1);
      bytes += cBoldOn();
      bytes += cText('${_normalizeArabic('$typeLabel $paymentLabel')}\n');
      bytes += cBoldOff();
      bytes += cText('${_normalizeArabic('رقم: $invoiceId')}\n');
      bytes += cText('${_normalizeArabic('التاريخ: $date')}\n');
      bytes += cText('${_normalizeArabic('العميل: $customerName')}\n');
      bytes += cLine();

      // Items header
      bytes += cTextAlignRight();
      bytes +=
          cText('${_normalizeArabic('الصنف                الكمية    السعر    المبلغ')}\n');
      bytes += cLine();

      // Items
      for (final item in items) {
        final name = _normalizeArabic((item['product_name'] as String?) ?? '');
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = MoneyHelper.readMoney(item['unit_price']);
        final itemTotal = MoneyHelper.readMoney(item['total_price']);
        bytes += cText('$name\n');
        bytes += cText('     $qty    $price    $itemTotal\n');
      }

      bytes += cLine();

      // Totals
      bytes += cTextAlignRight();
      bytes += cText(
          '${_normalizeArabic('المجموع:              $subtotal $currencySymbol')}\n');
      if (discountAmount > 0) {
        bytes += cText(
            '${_normalizeArabic('الخصم:               -$discountAmount $currencySymbol')}\n');
      }
      if (taxAmount > 0) {
        bytes += cText(
            '${_normalizeArabic('الضريبة:              $taxAmount $currencySymbol')}\n');
      }
      bytes += cBoldOn();
      bytes += cTextSize(2);
      bytes += cText(
          '${_normalizeArabic('الإجمالي: $total $currencySymbol')}\n');
      bytes += cTextSize(1);
      bytes += cBoldOff();

      if (paidAmount > 0 && remaining > 0) {
        bytes += cText(
            '${_normalizeArabic('المدفوع: $paidAmount $currencySymbol')}\n');
        bytes += cText(
            '${_normalizeArabic('المتبقي: $remaining $currencySymbol')}\n');
      }

      bytes += cLine();
      bytes += cTextAlignCenter();
      bytes += cText('${_normalizeArabic('شكراً لزيارتكم')}\n');
      bytes += cFeed(3);

      return await _writeBytes(bytes);
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      return false;
    }
  }

  /// Print inventory voucher receipt.
  Future<bool> printInventoryVoucher({
    required String voucherNumber,
    required String warehouseName,
    required String date,
    required List<Map<String, dynamic>> items,
    required double totalDiffValue,
    required String currency,
  }) async {
    if (!_isConnected) {
      final autoConnected = await autoConnect();
      if (!autoConnected) return false;
    }

    try {
      List<int> bytes = [];
      final businessName =
          await locator<ReferenceDataRepository>().getSetting('business_name') ?? 'الأول برو المحاسبي';
      final currencySymbol =
          currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

      bytes += cInit();
      bytes += cTextAlignCenter();
      bytes += cTextSize(2);
      bytes += cText('${_normalizeArabic(businessName)}\n');
      bytes += cTextSize(1);
      bytes += cBoldOn();
      bytes += cText('${_normalizeArabic('سند جرد مخزون')}\n');
      bytes += cBoldOff();
      bytes += cText('${_normalizeArabic('رقم: $voucherNumber')}\n');
      bytes += cText('${_normalizeArabic('المستودع: $warehouseName')}\n');
      bytes += cText('${_normalizeArabic('التاريخ: $date')}\n');
      bytes += cLine();

      bytes += cTextAlignRight();
      bytes += cText(
          '${_normalizeArabic('الصنف           الكمية النظامية  الكمية الفعلية  الفرق')}\n');
      bytes += cLine();

      for (final item in items) {
        final name = _normalizeArabic((item['product_name'] as String?) ?? '');
        final systemQty = (item['system_quantity'] as num?)?.toDouble() ?? 0;
        final countedQty = (item['counted_quantity'] as num?)?.toDouble() ?? 0;
        final diff = (item['difference'] as num?)?.toDouble() ?? 0;
        bytes += cText('$name\n');
        bytes += cText('     $systemQty    $countedQty    $diff\n');
      }

      bytes += cLine();
      bytes += cBoldOn();
      bytes += cText(
          '${_normalizeArabic('إجمالي الفرق: $totalDiffValue $currencySymbol')}\n');
      bytes += cBoldOff();
      bytes += cFeed(3);

      return await _writeBytes(bytes);
    } catch (e) {
      debugPrint('Error printing inventory voucher: $e');
      return false;
    }
  }

  // ESC/POS Command helpers
  List<int> cInit() => [0x1B, 0x40]; // Initialize printer
  List<int> cFeed(int lines) =>
      List.generate(lines, (_) => 0x0A); // Feed lines
  List<int> cLine() =>
      [0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x0A]; // Dashed line
  List<int> cTextAlignCenter() => [0x1B, 0x61, 0x01]; // Center alignment
  List<int> cTextAlignRight() => [0x1B, 0x61, 0x02]; // Right alignment
  List<int> cTextAlignLeft() => [0x1B, 0x61, 0x00]; // Left alignment
  List<int> cBoldOn() => [0x1B, 0x45, 0x01]; // Bold on
  List<int> cBoldOff() => [0x1B, 0x45, 0x00]; // Bold off
  List<int> cTextSize(int size) =>
      [0x1D, 0x21, size == 2 ? 0x11 : 0x00]; // Text size (1=normal, 2=double)
  List<int> cText(String text) => utf8.encode(text); // Encode text
  String _normalizeArabic(String text) => text;
}
