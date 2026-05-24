import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../../core/utils/esc_pos_commands.dart';
import '../../../data/datasources/database_helper.dart';

/// Bluetooth printer device info.
class BluetoothPrinterDevice {
  final String name;
  final String address;
  final bool connected;

  const BluetoothPrinterDevice({
    required this.name,
    required this.address,
    this.connected = false,
  });

  @override
  String toString() => 'BluetoothPrinterDevice($name, $address)';
}

/// Service for Bluetooth thermal printer communication.
///
/// Uses a MethodChannel-based approach to communicate with native
/// Android Bluetooth APIs via SPP (Serial Port Profile).
/// Provides graceful fallback with informative error messages
/// when Bluetooth is unavailable.
class BluetoothPrinterService {
  BluetoothPrinterService._();
  static final BluetoothPrinterService instance = BluetoothPrinterService._();

  // ── State ──────────────────────────────────────────────────────
  bool _isConnected = false;
  String _connectedAddress = '';
  String _connectedName = '';
  StreamSubscription? _connectionSubscription;

  bool get isConnected => _isConnected;
  String get connectedName => _connectedName;
  String get connectedAddress => _connectedAddress;

  // ── Settings ───────────────────────────────────────────────────
  int _charsPerLine = 48; // 80mm = 48 chars, 58mm = 32 chars
  int _paperWidth = 80; // mm
  bool _autoCut = true;
  int _fontSize = 0; // 0=normal, 1=large

  int get charsPerLine => _charsPerLine;
  int get paperWidth => _paperWidth;
  bool get autoCut => _autoCut;
  int get fontSize => _fontSize;

  /// Set paper width (58 or 80mm).
  void setPaperWidth(int mm) {
    _paperWidth = mm;
    _charsPerLine = mm >= 80 ? 48 : 32;
    _saveSettings();
  }

  /// Set auto-cut option.
  void setAutoCut(bool value) {
    _autoCut = value;
    _saveSettings();
  }

  /// Set font size (0=normal, 1=large).
  void setFontSize(int size) {
    _fontSize = size;
    _saveSettings();
  }

  // ── Bluetooth Serial (conditionally loaded) ────────────────────

  /// Check if Bluetooth is available on this device.
  Future<bool> isBluetoothAvailable() async {
    try {
      final isAvailable = await _invokeBluetoothMethod('isAvailable');
      return isAvailable == true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get list of paired (bonded) Bluetooth devices.
  Future<List<BluetoothPrinterDevice>> getPairedDevices() async {
    try {
      final devices = await _invokeBluetoothMethod('getBondedDevices');
      if (devices is List) {
        return devices.map((d) {
          if (d is Map) {
            return BluetoothPrinterDevice(
              name: d['name']?.toString() ?? 'جهاز غير معروف',
              address: d['address']?.toString() ?? '',
            );
          }
          return null;
        }).whereType<BluetoothPrinterDevice>().toList();
      }
      return [];
    } on PlatformException catch (_) {
      return [];
    } on MissingPluginException catch (_) {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Connect to a Bluetooth device by address.
  Future<bool> connect(String address) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      final result = await _invokeBluetoothMethod('connect', {'address': address});
      if (result == true) {
        _isConnected = true;
        _connectedAddress = address;

        // Get device name
        final devices = await getPairedDevices();
        final device = devices.where((d) => d.address == address).firstOrNull;
        _connectedName = device?.name ?? 'طابعة';

        // Save as default printer
        final db = DatabaseHelper();
        await db.setSetting('default_printer_address', address);
        await db.setSetting('default_printer_name', _connectedName);

        return true;
      }
      return false;
    } on PlatformException catch (e) {
      _isConnected = false;
      throw PrinterException('فشل الاتصال بالطابعة: ${e.message ?? e.toString()}');
    } on MissingPluginException catch (_) {
      throw PrinterException('خدمة البلوتوث غير متاحة على هذا الجهاز');
    } catch (e) {
      _isConnected = false;
      throw PrinterException('خطأ في الاتصال: $e');
    }
  }

  /// Disconnect from the current Bluetooth device.
  Future<void> disconnect() async {
    if (!_isConnected) return;

    try {
      await _invokeBluetoothMethod('disconnect');
    } catch (_) {
      // Ignore disconnect errors
    } finally {
      _isConnected = false;
      _connectedAddress = '';
      _connectedName = '';
      _connectionSubscription?.cancel();
      _connectionSubscription = null;
    }
  }

  /// Send raw bytes to the connected printer.
  Future<void> _sendData(List<int> data) async {
    if (!_isConnected) {
      throw PrinterException('الطابعة غير متصلة');
    }

    try {
      await _invokeBluetoothMethod('write', {
        'data': data,
      });
    } on PlatformException catch (e) {
      throw PrinterException('فشل إرسال البيانات: ${e.message ?? e.toString()}');
    } on MissingPluginException catch (_) {
      throw PrinterException('حزمة البلوتوث غير متاحة');
    } catch (e) {
      throw PrinterException('خطأ في الإرسال: $e');
    }
  }

  /// Print a receipt from structured data.
  Future<void> printReceipt(Map<String, dynamic> receiptData) async {
    final db = DatabaseHelper();
    final businessName = await db.getSetting('business_name') ?? 'الأول برو';
    final businessPhone = await db.getSetting('business_phone') ?? '';
    final businessAddress = await db.getSetting('business_address') ?? '';

    final cmds = EscPosCommands.buildReceipt(
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
      invoiceNumber: receiptData['invoice_number']?.toString() ?? '',
      invoiceType: receiptData['invoice_type']?.toString() ?? 'فاتورة',
      date: receiptData['date'] as DateTime? ?? DateTime.now(),
      customerName: receiptData['customer_name']?.toString() ?? 'بدون عميل',
      items: (receiptData['items'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      subtotal: (receiptData['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (receiptData['discount'] as num?)?.toDouble() ?? 0,
      tax: (receiptData['tax'] as num?)?.toDouble() ?? 0,
      total: (receiptData['total'] as num?)?.toDouble() ?? 0,
      paid: (receiptData['paid'] as num?)?.toDouble() ?? 0,
      remaining: (receiptData['remaining'] as num?)?.toDouble() ?? 0,
      currency: receiptData['currency']?.toString() ?? 'ر.ي',
      notes: receiptData['notes']?.toString(),
      charsPerLine: _charsPerLine,
      autoCut: _autoCut,
    );

    await _sendData(cmds);
  }

  /// Print an invoice using data from the database.
  Future<void> printInvoice(String invoiceId) async {
    final db = DatabaseHelper();
    final invoiceItems = await db.getInvoiceItems(invoiceId);
    final invoices = await db.getAllInvoices();
    final invoice = invoices.where((i) => i['id'] == invoiceId).firstOrNull;

    if (invoice == null) {
      throw PrinterException('الفاتورة غير موجودة');
    }

    final businessName = await db.getSetting('business_name') ?? 'الأول برو';
    final businessPhone = await db.getSetting('business_phone') ?? '';
    final businessAddress = await db.getSetting('business_address') ?? '';

    final type = invoice['type'] as String? ?? 'sale';
    final isReturn = (invoice['is_return'] as int? ?? 0) == 1;
    final typeAr = isReturn
        ? 'فاتورة مرتجع'
        : type == 'sale'
            ? 'فاتورة مبيعات'
            : 'فاتورة مشتريات';

    final createdAt = DateTime.tryParse(invoice['created_at'] as String? ?? '') ?? DateTime.now();

    await printReceipt({
      'business_name': businessName,
      'business_phone': businessPhone,
      'business_address': businessAddress,
      'invoice_number': invoiceId,
      'invoice_type': typeAr,
      'date': createdAt,
      'customer_name': invoice['entity_name'] ?? 'بدون عميل',
      'items': invoiceItems,
      'subtotal': (invoice['subtotal'] as num?)?.toDouble() ?? 0,
      'discount': (invoice['discount_amount'] as num?)?.toDouble() ?? 0,
      'tax': (invoice['tax_amount'] as num?)?.toDouble() ?? 0,
      'total': (invoice['total'] as num?)?.toDouble() ?? 0,
      'paid': (invoice['paid_amount'] as num?)?.toDouble() ?? 0,
      'remaining': (invoice['remaining'] as num?)?.toDouble() ?? 0,
      'currency': invoice['currency'] ?? 'YER',
      'notes': invoice['notes'],
    });
  }

  /// Print a test receipt.
  Future<void> testPrint() async {
    final cmds = EscPosCommands.buildTestPrint(charsPerLine: _charsPerLine);
    await _sendData(cmds);
  }

  /// Print a customer statement.
  Future<void> printCustomerStatement(Map<String, dynamic> customerData) async {
    final db = DatabaseHelper();
    final businessName = await db.getSetting('business_name') ?? 'الأول برو';

    final cmds = <int>[];
    cmds.addAll(EscPosCommands.init());
    cmds.addAll(EscPosCommands.selectCodeTable(16));
    cmds.addAll(EscPosCommands.setAlignment(1));
    cmds.addAll(EscPosCommands.boldOn());
    cmds.addAll(EscPosCommands.setFontSize(true, true));
    cmds.addAll(EscPosCommands.printlnArabic(businessName));
    cmds.addAll(EscPosCommands.normalFontSize());
    cmds.addAll(EscPosCommands.boldOff());
    cmds.addAll(EscPosCommands.feedLines(1));

    cmds.addAll(EscPosCommands.boldOn());
    cmds.addAll(EscPosCommands.printlnArabic('كشف حساب عميل'));
    cmds.addAll(EscPosCommands.boldOff());

    cmds.addAll(EscPosCommands.dashedLine(charsPerLine: _charsPerLine));
    cmds.addAll(EscPosCommands.setAlignment(0));

    final name = customerData['name']?.toString() ?? '';
    final balance = (customerData['balance'] as num?)?.toDouble() ?? 0;
    final bt = customerData['balance_type'] as String? ?? 'credit';
    final currency = customerData['currency'] as String? ?? 'YER';

    cmds.addAll(EscPosCommands.printlnArabic('العميل: $name'));
    cmds.addAll(EscPosCommands.printlnArabic('الرصيد: ${balance.toStringAsFixed(2)} $currency'));
    cmds.addAll(EscPosCommands.printlnArabic('الحالة: ${bt == 'credit' ? 'له' : 'عليه'}'));

    cmds.addAll(EscPosCommands.feedLines(3));
    cmds.addAll(EscPosCommands.cutPaper());

    await _sendData(cmds);
  }

  // ── Settings persistence ───────────────────────────────────────

  /// Load printer settings from database.
  Future<void> loadSettings() async {
    try {
      final db = DatabaseHelper();
      final paperWidthStr = await db.getSetting('printer_paper_width');
      final autoCutStr = await db.getSetting('printer_auto_cut');
      final fontSizeStr = await db.getSetting('printer_font_size');

      if (paperWidthStr != null) {
        final pw = int.tryParse(paperWidthStr) ?? 80;
        _paperWidth = pw;
        _charsPerLine = pw >= 80 ? 48 : 32;
      }
      if (autoCutStr != null) {
        _autoCut = autoCutStr == '1';
      }
      if (fontSizeStr != null) {
        _fontSize = int.tryParse(fontSizeStr) ?? 0;
      }
    } catch (_) {
      // Use defaults
    }
  }

  Future<void> _saveSettings() async {
    try {
      final db = DatabaseHelper();
      await db.setSetting('printer_paper_width', _paperWidth.toString());
      await db.setSetting('printer_auto_cut', _autoCut ? '1' : '0');
      await db.setSetting('printer_font_size', _fontSize.toString());
    } catch (_) {
      // Ignore save errors
    }
  }

  /// Try to auto-connect to the default printer.
  Future<bool> autoConnect() async {
    try {
      final db = DatabaseHelper();
      final address = await db.getSetting('default_printer_address');
      if (address != null && address.isNotEmpty) {
        return await connect(address);
      }
    } catch (_) {
      // Ignore
    }
    return false;
  }

  // ── Platform channel bridge ────────────────────────────────────
  /// This method invokes Bluetooth methods via a platform MethodChannel.
  /// The native Android side must register a MethodCallHandler for the
  /// 'bluetooth_printer' channel. Throws MissingPluginException if the
  /// native handler is not registered.
  static Future<dynamic> _invokeBluetoothMethod(String method, [dynamic arguments]) async {
    // Use a custom MethodChannel for Bluetooth SPP communication
    const channel = MethodChannel('bluetooth_printer');

    // Check if we're on Android (only platform supporting BT serial)
    if (!Platform.isAndroid) {
      throw PrinterException('البلوتوث مدعوم فقط على أندرويد');
    }

    return await channel.invokeMethod(method, arguments);
  }
}

/// Custom exception for printer errors.
class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
