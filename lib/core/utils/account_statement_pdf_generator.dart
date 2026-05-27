import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/datasources/database_helper.dart';
import 'currency_formatter.dart';

/// Generates PDF account statements for customers and suppliers.
class AccountStatementPdfGenerator {
  /// Generate and share PDF account statement for a customer or supplier.
  static Future<void> printAccountStatement({
    required String entityName,
    required String entityType, // 'customer' or 'supplier'
    required List<Map<String, dynamic>> movements,
    required double totalDebit,
    required double totalCredit,
    required double netBalance,
    required String balanceLabel, // 'له', 'عليه', 'متساوي'
    String? phone,
    String currency = 'YER',
  }) async {
    final pdfBytes = await generateStatementPdf(
      entityName: entityName,
      entityType: entityType,
      movements: movements,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      netBalance: netBalance,
      balanceLabel: balanceLabel,
      phone: phone,
      currency: currency,
    );
    final filename = '${entityType}_statement_${entityName.replaceAll(' ', '_')}.pdf';
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }

  /// Generate raw PDF bytes for the account statement.
  static Future<Uint8List> generateStatementPdf({
    required String entityName,
    required String entityType,
    required List<Map<String, dynamic>> movements,
    required double totalDebit,
    required double totalCredit,
    required double netBalance,
    required String balanceLabel,
    String? phone,
    String currency = 'YER',
  }) async {
    final db = DatabaseHelper();

    // Load business settings
    final businessName = await db.getSetting('business_name');
    final businessPhone = await db.getSetting('business_phone');
    final businessAddress = await db.getSetting('business_address');
    final logoPath = await db.getSetting('business_logo_path');

    final hasCustomBusiness = businessName != null && businessName.trim().isNotEmpty;
    final String headerName = hasCustomBusiness ? businessName! : 'الأول برو المحاسبي';
    final String headerPhone = (businessPhone != null && businessPhone.trim().isNotEmpty) ? businessPhone : '';
    final String headerAddress = (businessAddress != null && businessAddress.trim().isNotEmpty) ? businessAddress : '';

    // Load logo
    pw.MemoryImage? logoImage;
    try {
      if (logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync()) {
        final logoBytes = await File(logoPath).readAsBytes();
        logoImage = pw.MemoryImage(logoBytes);
      }
    } catch (_) {
      logoImage = null;
    }

    // Load Arabic font
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      arabicFont = pw.Font.ttf(fontData);
    } catch (_) {
      arabicFont = null;
    }

    final currencySymbol = currency == 'USD' ? r'$' : (currency == 'SAR' ? 'ر.س' : 'ر.ي');
    final titleAr = entityType == 'customer' ? 'كشف حساب عميل' : 'كشف حساب مورد';

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
          _buildHeader(headerName, headerPhone, headerAddress, logoImage, arabicFont),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 2, color: const PdfColor(0.12, 0.42, 0.14)),
          pw.SizedBox(height: 12),

          // ── Statement title ──
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: pw.BoxDecoration(
              color: const PdfColor(0.12, 0.42, 0.14),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              titleAr,
              style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: const PdfColor(1, 1, 1)),
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Entity info ──
          _infoRow('الاسم', entityName, arabicFont),
          if (phone != null && phone.isNotEmpty)
            _infoRow('الهاتف', phone, arabicFont),
          _infoRow('تاريخ الطباعة', _formatDate(DateTime.now().toIso8601String()), arabicFont),
          pw.SizedBox(height: 16),

          // ── Movements table ──
          _buildMovementsTable(movements, currencySymbol, arabicFont),
          pw.SizedBox(height: 16),

          // ── Summary ──
          _buildSummary(totalDebit, totalCredit, netBalance, balanceLabel, currencySymbol, arabicFont),

          // ── Footer ──
          pw.SizedBox(height: 40),
          pw.Divider(color: const PdfColor(0.7, 0.7, 0.7)),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'تم إنشاء هذا الكشف بواسطة تطبيق الأول برو المحاسبي',
              style: pw.TextStyle(font: arabicFont, fontSize: 8, color: const PdfColor(0.5, 0.5, 0.5)),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader(
    String name, String phone, String address,
    pw.MemoryImage? logo, pw.Font? font,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.12, 0.42, 0.14))),
              if (phone.isNotEmpty)
                pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('هاتف: $phone', style: pw.TextStyle(font: font, fontSize: 10))),
              if (address.isNotEmpty)
                pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text('العنوان: $address', style: pw.TextStyle(font: font, fontSize: 10))),
            ],
          ),
        ),
        if (logo != null)
          pw.Container(width: 72, height: 72, decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(12)), child: pw.Image(logo, fit: pw.BoxFit.contain))
        else
          pw.Container(
            width: 72, height: 72,
            decoration: pw.BoxDecoration(color: const PdfColor(0.12, 0.42, 0.14), borderRadius: pw.BorderRadius.circular(12)),
            alignment: pw.Alignment.center,
            child: pw.Text('FP', style: pw.TextStyle(font: font, fontSize: 24, fontWeight: pw.FontWeight.bold, color: const PdfColor(1, 1, 1))),
          ),
      ],
    );
  }

  static pw.Widget _buildMovementsTable(
    List<Map<String, dynamic>> movements,
    String currencySymbol,
    pw.Font? font,
  ) {
    final headerStyle = pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor(1, 1, 1));
    final cellStyle = pw.TextStyle(font: font, fontSize: 8);

    double runningBalance = 0;

    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor(0.8, 0.8, 0.8), width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5), // التاريخ
        1: const pw.FlexColumnWidth(2),   // البيان
        2: const pw.FlexColumnWidth(1.5), // عليه
        3: const pw.FlexColumnWidth(1.5), // له
        4: const pw.FlexColumnWidth(1.5), // الرصيد
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor(0.12, 0.42, 0.14)),
          children: [
            _tableCell('التاريخ', headerStyle),
            _tableCell('البيان', headerStyle),
            _tableCell('عليه', headerStyle),
            _tableCell('له', headerStyle),
            _tableCell('الرصيد', headerStyle),
          ],
        ),
        // Data rows
        ...movements.map((m) {
          final dateStr = m['date'] as String? ?? '';
          final description = m['description'] as String? ?? (m['type_ar'] as String? ?? '');
          final debit = (m['debit'] as num?)?.toDouble() ?? 0.0;
          final credit = (m['credit'] as num?)?.toDouble() ?? 0.0;
          runningBalance += credit - debit;

          return pw.TableRow(
            children: [
              _tableCell(_formatDate(dateStr), cellStyle),
              _tableCell(description, cellStyle, maxLines: 2),
              _tableCell(debit > 0 ? '$currencySymbol ${CurrencyFormatter.format(debit)}' : '', cellStyle),
              _tableCell(credit > 0 ? '$currencySymbol ${CurrencyFormatter.format(credit)}' : '', cellStyle),
              _tableCell('$currencySymbol ${CurrencyFormatter.format(runningBalance.abs())}', cellStyle),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildSummary(
    double totalDebit, double totalCredit, double netBalance,
    String balanceLabel, String currencySymbol, pw.Font? font,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          _totalRow('إجمالي عليه', '$currencySymbol ${CurrencyFormatter.format(totalDebit)}', font),
          pw.SizedBox(height: 4),
          _totalRow('إجمالي له', '$currencySymbol ${CurrencyFormatter.format(totalCredit)}', font),
          pw.Divider(color: const PdfColor(0.7, 0.7, 0.7)),
          _totalRow(
            'الرصيد ($balanceLabel)',
            '$currencySymbol ${CurrencyFormatter.format(netBalance.abs())}',
            font,
            isBold: true,
            fontSize: 14,
            color: netBalance >= 0 ? const PdfColor(0.12, 0.42, 0.14) : const PdfColor(0.8, 0, 0),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value, pw.Font? font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 10, color: const PdfColor(0.4, 0.4, 0.4))),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value, pw.Font? font, {bool isBold = false, double fontSize = 10, PdfColor? color}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      ],
    );
  }

  static pw.Widget _tableCell(String text, pw.TextStyle style, {int maxLines = 1}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: style, maxLines: maxLines),
    );
  }

  static String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}
