import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../di/service_locator.dart';
import '../../data/datasources/repositories/reference_data_repository.dart';
import 'currency_formatter.dart';
import 'money_helper.dart';

/// Generates professional PDF invoices for sales, purchases, and POS transactions.
/// Business header info (name, phone, email, address, logo) is pulled from
/// the settings table; if the user hasn't filled them in, the app's default
/// branding is used instead.
class InvoicePdfGenerator {
  // ── Public API ────────────────────────────────────────────────

  /// Generate and show the system print/share dialog for a single invoice.
  static Future<void> printInvoice(
      Map<String, dynamic> invoice, List<Map<String, dynamic>> items) async {
    final pdfBytes = await generateInvoicePdf(invoice, items);
    await Printing.sharePdf(
        bytes: pdfBytes, filename: 'invoice_${invoice['id']}.pdf');
  }

  /// Generate raw PDF bytes for the given invoice.
  static Future<Uint8List> generateInvoicePdf(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) async {
    // ── Load business settings ──
    final businessName =
        await locator<ReferenceDataRepository>().getSetting('business_name');
    final businessPhone =
        await locator<ReferenceDataRepository>().getSetting('business_phone');
    final businessEmail =
        await locator<ReferenceDataRepository>().getSetting('business_email');
    final businessAddress =
        await locator<ReferenceDataRepository>().getSetting('business_address');
    final logoPath = await locator<ReferenceDataRepository>()
        .getSetting('business_logo_path');

    // Determine if user has configured custom business info
    final hasCustomBusiness =
        businessName != null && businessName.trim().isNotEmpty;

    // Default app branding when user hasn't configured
    final String headerName =
        hasCustomBusiness ? businessName : 'الأول برو المحاسبي';
    final String headerPhone =
        (businessPhone != null && businessPhone.trim().isNotEmpty)
            ? businessPhone
            : '';
    final String headerEmail =
        (businessEmail != null && businessEmail.trim().isNotEmpty)
            ? businessEmail
            : '';
    final String headerAddress =
        (businessAddress != null && businessAddress.trim().isNotEmpty)
            ? businessAddress
            : '';

    // ── Load logo ──
    pw.MemoryImage? logoImage;
    try {
      if (logoPath != null &&
          logoPath.isNotEmpty &&
          File(logoPath).existsSync()) {
        final logoBytes = await File(logoPath).readAsBytes();
        logoImage = pw.MemoryImage(logoBytes);
      } else if (!hasCustomBusiness) {
        // Use default app logo for users who haven't configured their own
        final _ = await rootBundle.load('assets/icons/logo.svg');
        // SVG can't be used directly in pdf; we'll use a text placeholder
        logoImage = null;
      }
    } catch (_) {
      logoImage = null;
    }

    // ── Load Arabic font ──
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      arabicFont = pw.Font.ttf(fontData);
    } catch (_) {
      arabicFont = null;
    }

    final invoiceType = (invoice['type'] as String?) ?? 'sale';
    final isReturn = (invoice['is_return'] as int?) == 1;
    final currency = (invoice['currency'] as String?) ?? 'YER';
    final currencySymbol =
        currency == 'USD' ? r'$' : (currency == 'SAR' ? 'ر.س' : 'ر.ي');

    String typeLabel;
    if (invoiceType == 'pos') {
      typeLabel = isReturn
          ? 'فاتورة مبيعات نقاط البيع - مرتجع'
          : 'فاتورة مبيعات نقاط البيع';
    } else if (invoiceType == 'sale' || invoiceType == 'sale_return') {
      typeLabel = isReturn ? 'فاتورة مبيعات - مرتجع' : 'فاتورة مبيعات';
    } else {
      typeLabel = isReturn ? 'فاتورة مشتريات - مرتجع' : 'فاتورة مشتريات';
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: arabicFont ?? pw.Font.helvetica(),
        bold: arabicFont ?? pw.Font.helveticaBold(),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          // ── Header ──
          _buildHeader(headerName, headerPhone, headerEmail, headerAddress,
              logoImage, arabicFont),
          pw.SizedBox(height: 16),
          pw.Divider(
              thickness: 2,
              color: const PdfColor(0.12, 0.42, 0.14)), // AppColors.primary
          pw.SizedBox(height: 12),

          // ── Invoice title & info ──
          _buildInvoiceInfo(invoice, typeLabel, currencySymbol, arabicFont),
          pw.SizedBox(height: 16),

          // ── Items table ──
          _buildItemsTable(items, currencySymbol, arabicFont),
          pw.SizedBox(height: 16),

          // ── Totals ──
          _buildTotals(invoice, currencySymbol, arabicFont),
          pw.SizedBox(height: 24),

          // ── Notes ──
          if ((invoice['notes'] as String?)?.isNotEmpty == true) ...[
            pw.Divider(),
            pw.SizedBox(height: 8),
            _buildSectionTitle('ملاحظات', arabicFont),
            pw.Text(invoice['notes'] as String,
                style: pw.TextStyle(font: arabicFont, fontSize: 10)),
          ],

          // ── Footer ──
          pw.SizedBox(height: 40),
          pw.Divider(color: const PdfColor(0.7, 0.7, 0.7)),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'تم إنشاء هذه الفاتورة بواسطة تطبيق الأول برو المحاسبي',
              style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 8,
                  color: const PdfColor(0.5, 0.5, 0.5)),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ── Private helpers ────────────────────────────────────────────

  static pw.Widget _buildHeader(
    String name,
    String phone,
    String email,
    String address,
    pw.MemoryImage? logo,
    pw.Font? font,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Business info (right side for RTL)
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                name,
                style: pw.TextStyle(
                    font: font,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor(0.12, 0.42, 0.14)),
              ),
              if (phone.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text('هاتف: $phone',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                ),
              if (email.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text('بريد إلكتروني: $email',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                ),
              if (address.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text('العنوان: $address',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                ),
            ],
          ),
        ),
        // Logo (left side)
        if (logo != null)
          pw.Container(
            width: 72,
            height: 72,
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          )
        else
          pw.Container(
            width: 72,
            height: 72,
            decoration: pw.BoxDecoration(
              color: const PdfColor(0.12, 0.42, 0.14),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              'FP',
              style: pw.TextStyle(
                  font: font,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor(1, 1, 1)),
            ),
          ),
      ],
    );
  }

  static pw.Widget _buildInvoiceInfo(
    Map<String, dynamic> invoice,
    String typeLabel,
    String currencySymbol,
    pw.Font? font,
  ) {
    final invoiceDate = invoice['created_at'] as String? ?? '';
    final paymentMethod = (invoice['payment_method'] as String?) ?? 'cash';
    final paymentLabel = paymentMethod == 'credit' ? 'آجل' : 'نقدي';
    final status = (invoice['status'] as String?) ?? 'paid';
    final statusLabel = status == 'paid'
        ? 'مدفوعة'
        : (status == 'partial' ? 'مدفوعة جزئياً' : 'غير مدفوعة');
    final entityName = invoice['entity_name'] as String? ?? '—';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Invoice type title
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: pw.BoxDecoration(
            color: const PdfColor(0.12, 0.42, 0.14),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            typeLabel,
            style: pw.TextStyle(
                font: font,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(1, 1, 1)),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow(
                    'رقم الفاتورة', invoice['id']?.toString() ?? '—', font),
                pw.SizedBox(height: 4),
                _infoRow('التاريخ', _formatDate(invoiceDate), font),
                pw.SizedBox(height: 4),
                _infoRow('طريقة الدفع', paymentLabel, font),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow('العميل', entityName, font),
                pw.SizedBox(height: 4),
                _infoRow('الحالة', statusLabel, font),
                pw.SizedBox(height: 4),
                _infoRow('العملة', currencySymbol, font),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    String currencySymbol,
    pw.Font? font,
  ) {
    final headerStyle = pw.TextStyle(
        font: font,
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: const PdfColor(1, 1, 1));
    final cellStyle = pw.TextStyle(font: font, fontSize: 9);

    return pw.Table(
      border:
          pw.TableBorder.all(color: const PdfColor(0.8, 0.8, 0.8), width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // Product name
        1: const pw.FlexColumnWidth(1), // Quantity
        2: const pw.FlexColumnWidth(1.5), // Unit price
        3: const pw.FlexColumnWidth(1.5), // Total
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor(0.12, 0.42, 0.14)),
          children: [
            _tableCell('الصنف', headerStyle,
                alignment: pw.Alignment.centerRight),
            _tableCell('الكمية', headerStyle, alignment: pw.Alignment.center),
            _tableCell('سعر الوحدة', headerStyle,
                alignment: pw.Alignment.center),
            _tableCell('الإجمالي', headerStyle, alignment: pw.Alignment.center),
          ],
        ),
        // Data rows
        ...items.map((item) {
          final productName = (item['product_name'] as String?) ?? '—';
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
          final unitPrice = MoneyHelper.readMoney(item['unit_price']);
          final totalPrice = MoneyHelper.readMoney(item['total_price']);

          return pw.TableRow(
            children: [
              _tableCell(productName, cellStyle,
                  alignment: pw.Alignment.centerRight),
              _tableCell(
                  quantity.toStringAsFixed(
                      quantity == quantity.truncateToDouble() ? 0 : 2),
                  cellStyle,
                  alignment: pw.Alignment.center),
              _tableCell(
                  '$currencySymbol ${CurrencyFormatter.format(unitPrice)}',
                  cellStyle,
                  alignment: pw.Alignment.center),
              _tableCell(
                  '$currencySymbol ${CurrencyFormatter.format(totalPrice)}',
                  cellStyle,
                  alignment: pw.Alignment.center),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTotals(
    Map<String, dynamic> invoice,
    String currencySymbol,
    pw.Font? font,
  ) {
    final subtotal = MoneyHelper.readMoney(invoice['subtotal']);
    final discountAmount = MoneyHelper.readMoney(invoice['discount_amount']);
    final taxAmount = MoneyHelper.readMoney(invoice['tax_amount']);
    final transportCharges =
        MoneyHelper.readMoney(invoice['transport_charges']);
    final total = MoneyHelper.readMoney(invoice['total']);
    final paidAmount = MoneyHelper.readMoney(invoice['paid_amount']);
    final remaining = MoneyHelper.readMoney(invoice['remaining']);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          _totalRow('المجموع الفرعي',
              '$currencySymbol ${CurrencyFormatter.format(subtotal)}', font),
          if (discountAmount > 0) ...[
            pw.SizedBox(height: 4),
            _totalRow(
                'الخصم',
                '$currencySymbol ${CurrencyFormatter.format(discountAmount)}',
                font,
                isNegative: true),
          ],
          if (taxAmount > 0) ...[
            pw.SizedBox(height: 4),
            _totalRow('الضريبة',
                '$currencySymbol ${CurrencyFormatter.format(taxAmount)}', font),
          ],
          if (transportCharges > 0) ...[
            pw.SizedBox(height: 4),
            _totalRow(
                'أجور النقل',
                '$currencySymbol ${CurrencyFormatter.format(transportCharges)}',
                font),
          ],
          pw.Divider(color: const PdfColor(0.7, 0.7, 0.7)),
          _totalRow(
            'الإجمالي',
            '$currencySymbol ${CurrencyFormatter.format(total)}',
            font,
            isBold: true,
            fontSize: 14,
          ),
          pw.SizedBox(height: 6),
          _totalRow('المدفوع',
              '$currencySymbol ${CurrencyFormatter.format(paidAmount)}', font),
          pw.SizedBox(height: 4),
          _totalRow(
            'المتبقي',
            '$currencySymbol ${CurrencyFormatter.format(remaining)}',
            font,
            color: remaining > 0
                ? const PdfColor(0.8, 0, 0)
                : const PdfColor(0.12, 0.42, 0.14),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionTitle(String title, pw.Font? font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(
            font: font,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor(0.12, 0.42, 0.14)),
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value, pw.Font? font) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('$label: ',
            style: pw.TextStyle(
                font: font,
                fontSize: 10,
                color: const PdfColor(0.4, 0.4, 0.4))),
        pw.Text(value,
            style: pw.TextStyle(
                font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value,
    pw.Font? font, {
    bool isBold = false,
    bool isNegative = false,
    double fontSize = 10,
    PdfColor? color,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: font,
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          isNegative ? '- $value' : value,
          style: pw.TextStyle(
            font: font,
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? (isNegative ? const PdfColor(0.8, 0, 0) : null),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableCell(String text, pw.TextStyle style,
      {pw.Alignment alignment = pw.Alignment.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Align(
        alignment: alignment,
        child: pw.Text(text, style: style),
      ),
    );
  }

  static String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}
