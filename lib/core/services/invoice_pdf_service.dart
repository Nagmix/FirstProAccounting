import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../../data/datasources/database_helper.dart';
import '../utils/money_helper.dart';

/// Professional sales invoice PDF generator for the FirstPro accounting app.
///
/// Produces A4 RTL Arabic-layout invoices following the Yemeni accounting
/// standard template with: header, invoice type badge, metadata, items table,
/// totals, amount-in-words, and signature fields.
class InvoicePdfService {
  final DatabaseHelper _db = DatabaseHelper();

  // ─── Color constants ────────────────────────────────────────────────
  static const PdfColor _blueHeader = PdfColor.fromInt(0xFF174AFF);
  static const PdfColor _yellowHighlight = PdfColor.fromInt(0xFFFFFFC8);
  static const PdfColor _white = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _black = PdfColor.fromInt(0xFF000000);
  static const PdfColor _darkGray = PdfColor.fromInt(0xFF333333);
  static const PdfColor _lightGray = PdfColor.fromInt(0xFFF5F5F5);
  static const PdfColor _mediumGray = PdfColor.fromInt(0xFFCCCCCC);
  static const PdfColor _badgeBlue = PdfColor.fromInt(0xFF174AFF);

  // ─── Font cache ─────────────────────────────────────────────────────
  pw.Font? _arabicFont;
  pw.Font? _arabicFontBold;

  /// Load the Cairo font from assets. Call once before generating PDFs.
  Future<void> _loadFonts() async {
    if (_arabicFont != null) return;
    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final ttf = pw.Font.ttf(fontData);
    _arabicFont = ttf;
    _arabicFontBold = ttf; // Variable font; same ref for both weights
  }

  /// Generate a sales invoice PDF and return the bytes.
  Future<Uint8List> generateSalesInvoicePdf(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) async {
    await _loadFonts();

    // ─── Load business settings ─────────────────────────────────────
    final businessName =
        await _db.getSetting('business_name') ?? 'الأول برو المحاسبي';
    final businessPhone = await _db.getSetting('business_phone') ?? '';
    final businessEmail = await _db.getSetting('business_email') ?? '';
    final businessAddress = await _db.getSetting('business_address') ??
        'الجمهورية اليمنية - صنعاء';
    final logoPath = await _db.getSetting('business_logo_path') ?? '';
    final taxNumber = await _db.getSetting('business_tax_number') ?? '';
    final commercialReg =
        await _db.getSetting('business_commercial_reg') ?? '';

    final currency = invoice['currency'] as String? ?? 'YER';
    final currencySymbol =
        currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

    // ─── Invoice type title ─────────────────────────────────────────
    final invoiceType = invoice['type'] as String? ?? 'sale';
    final paymentMechanism =
        invoice['payment_mechanism'] as String? ?? 'cash';
    String invoiceTitle;
    if (invoiceType == 'sale') {
      invoiceTitle =
          paymentMechanism == 'credit' ? 'فاتورة بيع آجل' : 'فاتورة بيع نقدي';
    } else if (invoiceType == 'purchase') {
      invoiceTitle = paymentMechanism == 'credit'
          ? 'فاتورة شراء آجل'
          : 'فاتورة شراء نقدي';
    } else {
      invoiceTitle = 'فاتورة بيع نقدي';
    }

    // ─── Load logo ──────────────────────────────────────────────────
    pw.MemoryImage? logoImage;
    if (logoPath.isNotEmpty && File(logoPath).existsSync()) {
      final logoBytes = await File(logoPath).readAsBytes();
      logoImage = pw.MemoryImage(logoBytes);
    }

    // ─── Resolve customer name ──────────────────────────────────────
    String customerName = invoice['customer_name'] as String? ?? '';
    if (customerName.isEmpty && invoice['customer_id'] != null) {
      final custId = invoice['customer_id'];
      if (custId is int) {
        final customer = await _db.getCustomerById(custId);
        if (customer != null) {
          customerName = customer['name'] as String? ?? '';
        }
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header: Logo + Company Info
                _buildHeader(
                  logoImage,
                  businessName,
                  businessPhone,
                  businessEmail,
                  businessAddress,
                  taxNumber,
                  commercialReg,
                ),
                pw.SizedBox(height: 8),
                // Invoice Type Badge
                _buildInvoiceTypeBadge(invoiceTitle),
                pw.Divider(thickness: 1, color: _mediumGray),
                pw.SizedBox(height: 6),
                // Invoice Metadata
                _buildInvoiceMetadata(invoice, currencySymbol, customerName),
                pw.SizedBox(height: 10),
                // Items Table
                _buildItemsTable(items, currencySymbol),
                pw.SizedBox(height: 6),
                // Totals
                _buildTotals(invoice, currencySymbol),
                pw.SizedBox(height: 8),
                // Amount in Words
                _buildAmountInWords(invoice, currency, currencySymbol),
                pw.SizedBox(height: 20),
                // Signature Fields
                _buildSignatureFields(),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ════════════════════════════════════════════════════════════════════
  //  HEADER
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildHeader(
    pw.MemoryImage? logoImage,
    String businessName,
    String businessPhone,
    String businessEmail,
    String businessAddress,
    String taxNumber,
    String commercialReg,
  ) {
    // Company info column (right side in RTL = visual right)
    final infoChildren = <pw.Widget>[
      pw.Text(
        businessName,
        style: pw.TextStyle(
          font: _arabicFontBold!,
          fontSize: 16,
          color: _blueHeader,
          fontWeight: pw.FontWeight.bold,
        ),
        textDirection: pw.TextDirection.rtl,
      ),
    ];

    if (businessAddress.isNotEmpty) {
      infoChildren.add(
        pw.Text(
          businessAddress,
          style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: _darkGray),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }
    if (businessPhone.isNotEmpty) {
      infoChildren.add(
        pw.Text(
          'هاتف: $businessPhone',
          style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: _darkGray),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }
    if (businessEmail.isNotEmpty) {
      infoChildren.add(
        pw.Text(
          'بريد إلكتروني: $businessEmail',
          style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: _darkGray),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }
    if (taxNumber.isNotEmpty) {
      infoChildren.add(
        pw.Text(
          'الرقم الضريبي: $taxNumber',
          style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: _darkGray),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }
    if (commercialReg.isNotEmpty) {
      infoChildren.add(
        pw.Text(
          'السجل التجاري: $commercialReg',
          style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: _darkGray),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Logo (left side in RTL = visual left)
        pw.Container(
          width: 70,
          height: 70,
          child: logoImage != null
              ? pw.Image(logoImage, fit: pw.BoxFit.contain)
              : _buildDefaultLogo(),
        ),
        pw.SizedBox(width: 12),
        // Company info
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: infoChildren,
          ),
        ),
      ],
    );
  }

  /// Build a default app icon placeholder when no logo is set.
  pw.Widget _buildDefaultLogo() {
    return pw.Container(
      width: 70,
      height: 70,
      decoration: pw.BoxDecoration(
        color: _blueHeader,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'FP',
        style: pw.TextStyle(
          font: _arabicFontBold!,
          fontSize: 24,
          color: _white,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  INVOICE TYPE BADGE
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildInvoiceTypeBadge(String invoiceTitle) {
    return pw.Center(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _badgeBlue,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          invoiceTitle,
          style: pw.TextStyle(
            font: _arabicFontBold!,
            fontSize: 14,
            color: _white,
            fontWeight: pw.FontWeight.bold,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  INVOICE METADATA
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildInvoiceMetadata(
    Map<String, dynamic> invoice,
    String currencySymbol,
    String customerName,
  ) {
    // Parse date
    final createdAtRaw = invoice['created_at'] as String?;
    String formattedDate = '';
    if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAtRaw);
        formattedDate = DateFormat('yyyy/MM/dd - hh:mm a').format(dt);
      } catch (_) {
        formattedDate = createdAtRaw;
      }
    }

    final invoiceNumber = invoice['id'] as String? ?? '—';
    final notes = invoice['notes'] as String? ?? '';

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _mediumGray, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          _metadataRow('رقم الفاتورة', invoiceNumber),
          pw.SizedBox(height: 4),
          _metadataRow('التاريخ', formattedDate),
          if (customerName.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            _metadataRow('العميل', customerName),
          ],
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            _metadataRow('ملاحظات', notes),
          ],
        ],
      ),
    );
  }

  pw.Widget _metadataRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            font: _arabicFontBold!,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(font: _arabicFont!, fontSize: 10, color: _black),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  ITEMS TABLE
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    String currencySymbol,
  ) {
    // Column widths: #, Product Name, Expiry Date, Unit, Quantity, Unit Price, Total
    // In RTL the visual order is reversed, but we define logical order
    final columnWidths = [
      25.0, // # (م)
      120.0, // Product Name (اسم المنتج)
      70.0, // Expiry Date (تاريخ الانتهاء)
      40.0, // Unit (الوحدة)
      50.0, // Quantity (الكمية)
      70.0, // Unit Price (سعر الوحدة)
      75.0, // Total (الإجمالي)
    ];

    final headerTexts = [
      '#',
      'اسم المنتج',
      'تاريخ الانتهاء',
      'الوحدة',
      'الكمية',
      'سعر الوحدة',
      'الإجمالي',
    ];

    // Header row
    final headerRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: _blueHeader),
      children: List.generate(headerTexts.length, (i) {
        return pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: pw.Text(
            headerTexts[i],
            style: pw.TextStyle(
              font: _arabicFontBold!,
              fontSize: 9,
              color: _white,
              fontWeight: pw.FontWeight.bold,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        );
      }),
    );

    // Data rows
    final dataRows = <pw.TableRow>[];
    double grandTotal = 0;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final productName = item['product_name'] as String? ?? '';
      final expiryDate = item['expiry_date'] as String? ?? '—';
      final unit = item['unit'] as String? ?? item['unit_name'] as String? ?? '—';
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = MoneyHelper.readMoney(item['unit_price']);
      final totalPrice = MoneyHelper.readMoney(item['total_price'], fallback: quantity * unitPrice);

      grandTotal += totalPrice;

      final isEvenRow = i % 2 == 0;
      final rowBg = isEvenRow ? _lightGray : _white;

      dataRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: rowBg),
          children: [
            _tableCell('${i + 1}'),
            _tableCell(productName, align: pw.Alignment.centerRight),
            _tableCell(expiryDate),
            _tableCell(unit),
            _tableCell(_formatNumber(quantity)),
            _tableCell('${_formatNumber(unitPrice)} $currencySymbol'),
            _tableCell('${_formatNumber(totalPrice)} $currencySymbol'),
          ],
        ),
      );
    }

    // Total row (yellow highlight)
    final totalRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: _yellowHighlight),
      children: [
        _tableCell('', bold: true), // #
        _tableCell('', bold: true), // Product Name
        _tableCell('', bold: true), // Expiry Date
        _tableCell('', bold: true), // Unit
        _tableCell('', bold: true), // Quantity
        _tableCell(
          'المجموع',
          bold: true,
          align: pw.Alignment.centerRight,
        ),
        _tableCell(
          '${_formatNumber(grandTotal)} $currencySymbol',
          bold: true,
        ),
      ],
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _mediumGray, width: 0.5),
      columnWidths: { for (var i = 0; i < columnWidths.length; i++) i: pw.FixedColumnWidth(columnWidths[i]) },
      children: [headerRow, ...dataRows, totalRow],
    );
  }

  pw.Widget _tableCell(
    String text, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: bold ? _arabicFontBold! : _arabicFont!,
          fontSize: 9,
          color: _black,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  TOTALS SECTION
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildTotals(
    Map<String, dynamic> invoice,
    String currencySymbol,
  ) {
    final subtotal =
        MoneyHelper.readMoney(invoice['subtotal']);
    final discountAmount =
        MoneyHelper.readMoney(invoice['discount_amount']);
    final taxAmount =
        MoneyHelper.readMoney(invoice['tax_amount']);
    final transportCharges =
        MoneyHelper.readMoney(invoice['transport_charges']);
    final total =
        MoneyHelper.readMoney(invoice['total']);

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _mediumGray, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          // Subtotal
          _totalsRow('المجموع الفرعي', '${_formatNumber(subtotal)} $currencySymbol'),
          // Discount (if any)
          if (discountAmount > 0)
            _totalsRow(
              'الخصم',
              '- ${_formatNumber(discountAmount)} $currencySymbol',
              valueColor: PdfColor.fromInt(0xFFD32F2F),
            ),
          // Tax (if any)
          if (taxAmount > 0)
            _totalsRow('الضريبة', '${_formatNumber(taxAmount)} $currencySymbol'),
          // Transport charges (if any)
          if (transportCharges > 0)
            _totalsRow(
              'أجور النقل',
              '${_formatNumber(transportCharges)} $currencySymbol',
            ),
          pw.Divider(color: _mediumGray, thickness: 0.5),
          // Net total (yellow highlight)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: pw.BoxDecoration(
              color: _yellowHighlight,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: _totalsRow(
              'الإجمالي الصافي',
              '${_formatNumber(total)} $currencySymbol',
              bold: true,
              showBox: false,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _totalsRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor? valueColor,
    bool showBox = true,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: bold ? _arabicFontBold! : _arabicFont!,
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _darkGray,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: bold ? _arabicFontBold! : _arabicFont!,
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor ?? _black,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  AMOUNT IN WORDS
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildAmountInWords(
    Map<String, dynamic> invoice,
    String currency,
    String currencySymbol,
  ) {
    final total = MoneyHelper.readMoney(invoice['total']);

    final currencyNameAr = currency == 'SAR'
        ? 'ريال سعودي'
        : (currency == 'USD' ? 'دولار أمريكي' : 'ريال يمني');
    final subCurrencyNameAr = currency == 'SAR'
        ? 'هللة'
        : (currency == 'USD' ? 'سنت' : 'فلس');

    final words = _numberToArabicWords(total, currencyNameAr, subCurrencyNameAr);

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'المبلغ بالحروف: ',
            style: pw.TextStyle(
              font: _arabicFontBold!,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _darkGray,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Expanded(
            child: pw.Text(
              words,
              style: pw.TextStyle(
                font: _arabicFont!,
                fontSize: 10,
                color: _black,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  SIGNATURE FIELDS
  // ════════════════════════════════════════════════════════════════════

  pw.Widget _buildSignatureFields() {
    final labels = ['البائع', 'المخازن', 'المصادق', 'المستلم'];

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
      children: labels.map((label) {
        return pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Column(
              children: [
                // Space for the actual signature
                pw.Container(
                  height: 45,
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _darkGray, width: 0.5),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    font: _arabicFontBold!,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _darkGray,
                  ),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  NUMBER FORMATTING
  // ════════════════════════════════════════════════════════════════════

  /// Format a number with commas for Arabic locale.
  /// Example: 1000000 → "1,000,000" or 1234.56 → "1,234.56"
  static String _formatNumber(num value) {
    if (value == value.truncateToDouble()) {
      // Integer-like value (no meaningful decimals)
      return _addCommas(value.toInt().toString());
    }
    final fixed = value.toStringAsFixed(2);
    // Remove trailing zeros after decimal point, but keep at least .00 if
    // there are meaningful decimals
    final parts = fixed.split('.');
    final integerPart = parts[0];
    var decimalPart = parts[1];

    // Trim trailing zeros
    decimalPart = decimalPart.replaceAll(RegExp(r'0+$'), '');
    if (decimalPart.isEmpty) {
      return _addCommas(integerPart);
    }
    return '${_addCommas(integerPart)}.$decimalPart';
  }

  static String _addCommas(String integerPart) {
    final isNegative = integerPart.startsWith('-');
    var digits = isNegative ? integerPart.substring(1) : integerPart;
    final buffer = StringBuffer();
    final length = digits.length;
    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return isNegative ? '-$buffer' : buffer.toString();
  }

  // ════════════════════════════════════════════════════════════════════
  //  NUMBER TO ARABIC WORDS
  // ════════════════════════════════════════════════════════════════════

  /// Converts a number to its Arabic word representation with currency.
  ///
  /// Supports values up to billions. Handles decimal parts as sub-currency.
  ///
  /// Example: 1234.56 → "ألف ومائتان وأربعة وثلاثون ريال يمني وستة
  /// وخمسون فلس فقط لا غير"
  static String _numberToArabicWords(
    double amount,
    String currencyName,
    String subCurrencyName,
  ) {
    if (amount == 0) {
      return 'صفر $currencyName فقط لا غير';
    }

    final integerPart = amount.truncate();
    final decimalPart = ((amount - integerPart) * 100).round();

    final buffer = StringBuffer();

    if (integerPart > 0) {
      buffer.write(_convertIntegerToArabic(integerPart));
      buffer.write(' $currencyName');
    }

    if (decimalPart > 0) {
      if (integerPart > 0) {
        buffer.write(' و');
      }
      buffer.write(_convertIntegerToArabic(decimalPart));
      buffer.write(' $subCurrencyName');
    }

    buffer.write(' فقط لا غير');
    return buffer.toString();
  }

  /// Convert an integer (0 ≤ n ≤ 999,999,999,999) to Arabic words.
  static String _convertIntegerToArabic(int n) {
    if (n == 0) return 'صفر';
    if (n < 0) return 'سالب ${_convertIntegerToArabic(-n)}';

    final parts = <String>[];

    // Billions (مليار)
    if (n >= 1000000000) {
      final billions = n ~/ 1000000000;
      // For 1 and 2 the magnitude word already encodes the count
      if (billions > 2) {
        parts.add(_convertHundreds(billions, isFeminine: true, asMagnitudePrefix: true));
      }
      parts.add(billions == 1
          ? 'مليار'
          : billions == 2
              ? 'ملياران'
              : billions <= 10
                  ? 'مليارات'
                  : 'ملياراً');
      n %= 1000000000;
    }

    // Millions (مليون)
    if (n >= 1000000) {
      final millions = n ~/ 1000000;
      if (millions > 2) {
        parts.add(_convertHundreds(millions, isFeminine: true, asMagnitudePrefix: true));
      }
      parts.add(millions == 1
          ? 'مليون'
          : millions == 2
              ? 'مليونان'
              : millions <= 10
                  ? 'ملايين'
                  : 'مليوناً');
      n %= 1000000;
    }

    // Thousands (ألف)
    if (n >= 1000) {
      final thousands = n ~/ 1000;
      if (thousands > 2) {
        parts.add(_convertHundreds(thousands, isFeminine: false, asMagnitudePrefix: true));
      }
      parts.add(thousands == 1
          ? 'ألف'
          : thousands == 2
              ? 'ألفان'
              : thousands <= 10
                  ? 'آلاف'
                  : 'ألفاً');
      n %= 1000;
    }

    // Hundreds + tens + ones
    if (n > 0) {
      parts.add(_convertHundreds(n, isFeminine: false));
    }

    return parts.join(' و');
  }

  /// Convert a number 1–999 to Arabic words.
  ///
  /// [isFeminine] affects the form of numbers 1 and 2 when they appear
  /// as standalone tens/ones (e.g., "واحدة" vs "واحد").
  ///
  /// [asMagnitudePrefix] when true, uses the counting forms with ة (ta
  /// marbuta) for 3-10 which is correct before magnitude words like
  /// آلاف, ملايين, مليارات (e.g., "ثلاثة آلاف" not "ثلاث آلاف").
  static String _convertHundreds(int n, {bool isFeminine = false, bool asMagnitudePrefix = false}) {
    assert(n >= 1 && n <= 999);

    // Ones forms used in the final position (3-10 without ة)
    final onesBase = [
      '', // 0
      isFeminine ? 'واحدة' : 'واحد',
      isFeminine ? 'اثنتان' : 'اثنان',
      'ثلاث',
      'أربع',
      'خمس',
      'ست',
      'سبع',
      'ثمان',
      'تسع',
    ];

    // Counting forms used before magnitude words (3-10 with ة)
    final onesCounting = [
      '', // 0
      isFeminine ? 'واحدة' : 'واحد',
      isFeminine ? 'اثنتان' : 'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
    ];

    // Forms used in the teens (13-19)
    final onesTeens = [
      '', // 0
      '', // 11 and 12 are handled separately
      '',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
    ];

    final tens = [
      '', // 0
      'عشر',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون',
    ];

    final hundreds = [
      '', // 0
      'مائة',
      'مائتان',
      'ثلاثمائة',
      'أربعمائة',
      'خمسمائة',
      'ستمائة',
      'سبعمائة',
      'ثمانمائة',
      'تسعمائة',
    ];

    // Choose the right ones array based on context
    final ones = asMagnitudePrefix ? onesCounting : onesBase;

    final result = <String>[];

    final h = n ~/ 100;
    final remainder = n % 100;
    final t = remainder ~/ 10;
    final o = remainder % 10;

    if (h > 0) {
      result.add(hundreds[h]);
    }

    if (remainder == 0) {
      // Nothing more to add
    } else if (remainder == 1) {
      result.add(isFeminine ? 'واحدة' : 'واحد');
    } else if (remainder == 2) {
      result.add(isFeminine ? 'اثنتان' : 'اثنان');
    } else if (remainder <= 10) {
      // 3-10
      result.add(ones[remainder]);
    } else if (remainder == 11) {
      result.add('إحدى عشرة');
    } else if (remainder == 12) {
      result.add('اثنتا عشرة');
    } else if (remainder < 20) {
      // 13-19: use teens form + عشر
      result.add('${onesTeens[o]} عشر');
    } else {
      // 20-99
      if (o > 0) {
        result.add('${ones[o]} و${tens[t]}');
      } else {
        result.add(tens[t]);
      }
    }

    return result.join(' و');
  }
}
