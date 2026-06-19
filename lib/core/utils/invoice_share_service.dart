import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/invoice_pdf_generator.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/core/di/service_locator.dart';

/// F-04: invoice sharing service.
///
/// Provides structured methods for sending invoices via WhatsApp and
/// email, replacing the previous inline `_shareInvoice` /
/// `_shareInvoiceWhatsApp` methods in InvoiceDetailScreen that only
/// shared plain text via the generic share sheet.
///
/// Features:
///   - WhatsApp: opens wa.me/<phone> directly with the customer's phone
///     number, pre-fills the message with the invoice summary, and
///     attaches the PDF.
///   - Email: opens the user's default email client via mailto: URI,
///     pre-fills subject + body, and attaches the PDF via share_plus
///     (mailto: cannot attach files, so we fall back to share_plus for
///     the actual attachment).
///   - Plain text share (generic share sheet) — backward-compatible
///     with the existing _shareInvoice behavior.
///   - PDF-only share — generates the PDF and opens the share sheet.
///
/// All methods are async and return bool indicating whether the share
/// was successfully dispatched (NOT whether the user actually sent it —
/// that's outside the app's control).
class InvoiceShareService {
  InvoiceShareService._();

  // ════════════════════════════════════════════════════════════════
  //  WhatsApp
  // ════════════════════════════════════════════════════════════════

  /// Send the invoice via WhatsApp to the given [phone] number.
  ///
  /// [phone] should be in international format without '+' or spaces
  /// (e.g. '967777123456'). If the phone has a leading '+' or spaces,
  /// they're stripped automatically.
  ///
  /// [includePdf] controls whether a PDF attachment is generated and
  /// shared alongside the text message. When true, the method:
  ///   1. Generates the PDF via InvoicePdfGenerator.
  ///   2. Writes it to a temp file.
  ///   3. Calls Share.shareXFiles with the WhatsApp mime type hint.
  /// The user then picks WhatsApp from the share sheet (Android's
  /// direct wa.me intent cannot attach files, so share_plus is the
  /// only reliable cross-version path).
  ///
  /// When [includePdf] is false, the method opens wa.me/<phone>
  /// directly with the pre-filled message text.
  ///
  /// Returns true if the share was dispatched, false if [phone] is
  /// empty or an error occurred.
  static Future<bool> shareViaWhatsApp({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    required String? phone,
    bool includePdf = true,
  }) async {
    final cleanedPhone = _cleanPhoneNumber(phone);
    final message = _buildWhatsAppMessage(invoice, items);

    if (cleanedPhone.isEmpty) {
      // No phone — fall back to generic share with text only.
      try {
        await Share.share(message, subject: _invoiceSubject(invoice));
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('InvoiceShareService.shareViaWhatsApp: $e');
        return false;
      }
    }

    if (includePdf) {
      // Share PDF + text via share_plus. The user picks WhatsApp from
      // the share sheet. This is the only reliable way to attach a
      // file on Android (wa.me intent cannot attach files).
      try {
        final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(invoice, items);
        final file = await _writeTempPdf(invoice, pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: message,
          subject: _invoiceSubject(invoice),
        );
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('InvoiceShareService.shareViaWhatsApp PDF: $e');
        // Fallback: open wa.me with text only.
        return _openWhatsAppDirect(cleanedPhone, message);
      }
    }

    // Text-only: open wa.me directly.
    return _openWhatsAppDirect(cleanedPhone, message);
  }

  /// Open wa.me/<phone>?text=<message> via url_launcher.
  static Future<bool> _openWhatsAppDirect(String phone, String message) async {
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('InvoiceShareService._openWhatsAppDirect: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Email
  // ════════════════════════════════════════════════════════════════

  /// Send the invoice via email to the given [email] address.
  ///
  /// Because mailto: URIs cannot attach files on Android, this method:
  ///   1. If [includePdf] is true, generates the PDF and shares it via
  ///      Share.shareXFiles with the email subject + body as the share
  ///      text. The user picks their email client from the share sheet.
  ///   2. If [includePdf] is false, opens mailto:<email> with subject +
  ///      body pre-filled (no attachment).
  ///
  /// Returns true if the share was dispatched, false if [email] is
  /// empty or an error occurred.
  static Future<bool> shareViaEmail({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    required String? email,
    bool includePdf = true,
  }) async {
    final cleanedEmail = (email ?? '').trim();
    final subject = _invoiceSubject(invoice);
    final body = _buildEmailBody(invoice, items);

    if (cleanedEmail.isEmpty && includePdf) {
      // No email + PDF: share via share_plus (user picks email client).
      try {
        final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(invoice, items);
        final file = await _writeTempPdf(invoice, pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: body,
          subject: subject,
        );
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('InvoiceShareService.shareViaEmail PDF: $e');
        return false;
      }
    }

    if (cleanedEmail.isEmpty) {
      // No email, no PDF: open generic mailto: with subject + body.
      return _openMailto('', subject, body);
    }

    if (includePdf) {
      // Have email + PDF: share via share_plus (user picks email client).
      try {
        final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(invoice, items);
        final file = await _writeTempPdf(invoice, pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: body,
          subject: subject,
        );
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('InvoiceShareService.shareViaEmail PDF: $e');
        // Fallback: open mailto: without attachment.
        return _openMailto(cleanedEmail, subject, body);
      }
    }

    // Text-only email: open mailto: directly.
    return _openMailto(cleanedEmail, subject, body);
  }

  /// Open mailto:<email>?subject=<>&body=<> via url_launcher.
  static Future<bool> _openMailto(String email, String subject, String body) async {
    final uri = Uri.parse(
      'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('InvoiceShareService._openMailto: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Generic share (text or PDF only)
  // ════════════════════════════════════════════════════════════════

  /// Share the invoice as plain text via the generic share sheet.
  /// Backward-compatible with the existing _shareInvoice behavior.
  static Future<bool> shareAsText({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await Share.share(
        _buildPlainTextMessage(invoice, items),
        subject: _invoiceSubject(invoice),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('InvoiceShareService.shareAsText: $e');
      return false;
    }
  }

  /// Share the invoice as a PDF file via the generic share sheet.
  static Future<bool> shareAsPdf({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(invoice, items);
      final file = await _writeTempPdf(invoice, pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: _invoiceSubject(invoice),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('InvoiceShareService.shareAsPdf: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Message builders
  // ════════════════════════════════════════════════════════════════

  /// Build a WhatsApp-formatted message (with *bold* and bullet points).
  static String _buildWhatsAppMessage(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) {
    final buffer = StringBuffer();
    final businessName = _getBusinessNameSync();
    if (businessName.isNotEmpty) {
      buffer.writeln('*$businessName*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━');
    }
    buffer.writeln('*${_invoiceTypeAr(invoice)}*');
    buffer.writeln('رقم: ${_displayInvoiceId(invoice)}');
    final entityName = _entityName(invoice);
    if (entityName.isNotEmpty) {
      buffer.writeln('${_isSale(invoice) ? 'العميل' : 'المورد'}: *$entityName*');
    }
    buffer.writeln('التاريخ: ${_formatDate(invoice['created_at'] as String?)}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    final total = MoneyHelper.readMoney(invoice['total']);
    final paid = MoneyHelper.readMoney(invoice['paid_amount']);
    final remaining = MoneyHelper.readMoney(invoice['remaining']);
    final currency = invoice['currency'] as String? ?? 'YER';
    buffer.writeln(
        '*الإجمالي: ${CurrencyFormatter.format(total, symbol: _currencySymbol(currency))}*');
    buffer.writeln(
        'المدفوع: ${CurrencyFormatter.format(paid, symbol: _currencySymbol(currency))}');
    buffer.writeln(
        'المتبقي: ${CurrencyFormatter.format(remaining, symbol: _currencySymbol(currency))}');
    if (items.isNotEmpty) {
      buffer.writeln('━━━━━━━━━━━━━━━━━━');
      for (final item in items) {
        final productName = item['product_name'] as String? ?? '';
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = MoneyHelper.readMoney(item['total_price']);
        buffer.writeln(
            '▫️ $productName × ${_formatQty(quantity)} = ${CurrencyFormatter.format(totalPrice, symbol: _currencySymbol(currency))}');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('شكراً لتعاملكم معنا');
    return buffer.toString();
  }

  /// Build a plain-text message (no WhatsApp formatting).
  static String _buildPlainTextMessage(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) {
    final buffer = StringBuffer();
    final businessName = _getBusinessNameSync();
    if (businessName.isNotEmpty) {
      buffer.writeln(businessName);
      buffer.writeln('──────────────────');
    }
    buffer.writeln(_invoiceTypeAr(invoice));
    buffer.writeln('رقم: ${_displayInvoiceId(invoice)}');
    final entityName = _entityName(invoice);
    if (entityName.isNotEmpty) {
      buffer.writeln('${_isSale(invoice) ? 'العميل' : 'المورد'}: $entityName');
    }
    buffer.writeln('التاريخ: ${_formatDate(invoice['created_at'] as String?)}');
    buffer.writeln('──────────────────');
    final total = MoneyHelper.readMoney(invoice['total']);
    final paid = MoneyHelper.readMoney(invoice['paid_amount']);
    final remaining = MoneyHelper.readMoney(invoice['remaining']);
    final currency = invoice['currency'] as String? ?? 'YER';
    buffer.writeln(
        'الإجمالي: ${CurrencyFormatter.format(total, symbol: _currencySymbol(currency))}');
    buffer.writeln(
        'المدفوع: ${CurrencyFormatter.format(paid, symbol: _currencySymbol(currency))}');
    buffer.writeln(
        'المتبقي: ${CurrencyFormatter.format(remaining, symbol: _currencySymbol(currency))}');
    if (items.isNotEmpty) {
      buffer.writeln('──────────────────');
      for (final item in items) {
        final productName = item['product_name'] as String? ?? '';
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = MoneyHelper.readMoney(item['total_price']);
        buffer.writeln(
            '$productName × ${_formatQty(quantity)} = ${CurrencyFormatter.format(totalPrice, symbol: _currencySymbol(currency))}');
      }
    }
    buffer.writeln('──────────────────');
    buffer.writeln('شكراً لتعاملكم معنا');
    return buffer.toString();
  }

  /// Build an email body (plain text, slightly more formal).
  static String _buildEmailBody(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) {
    // Email body is the same as plain text, with a header line.
    return _buildPlainTextMessage(invoice, items);
  }

  // ════════════════════════════════════════════════════════════════
  //  Helpers
  // ════════════════════════════════════════════════════════════════

  static String _cleanPhoneNumber(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  static String _invoiceSubject(Map<String, dynamic> invoice) {
    return '${_invoiceTypeAr(invoice)} - ${_displayInvoiceId(invoice)}';
  }

  static String _invoiceTypeAr(Map<String, dynamic> invoice) {
    final type = invoice['type'] as String? ?? 'sale';
    final isReturn = (invoice['is_return'] as num?)?.toInt() == 1;
    switch (type) {
      case 'sale':
        return isReturn ? 'فاتورة مرتجع مبيعات' : 'فاتورة مبيعات';
      case 'pos':
        return isReturn ? 'فاتورة مرتجع POS' : 'فاتورة نقطة بيع';
      case 'purchase':
        return isReturn ? 'فاتورة مرتجع مشتريات' : 'فاتورة مشتريات';
      default:
        return 'فاتورة';
    }
  }

  static String _displayInvoiceId(Map<String, dynamic> invoice) {
    final id = invoice['id'] as String? ?? '';
    if (id.length <= 12) return id;
    return id.substring(0, 12);
  }

  static bool _isSale(Map<String, dynamic> invoice) {
    final type = invoice['type'] as String? ?? 'sale';
    return type == 'sale' || type == 'pos';
  }

  static String _entityName(Map<String, dynamic> invoice) {
    return (invoice['entity_name'] as String?) ??
        (invoice['customer_name'] as String?) ??
        (invoice['supplier_name'] as String?) ??
        '';
  }

  static String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return isoDate.length >= 10 ? isoDate.substring(0, 10) : isoDate;
    }
  }

  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
    return qty.toStringAsFixed(2);
  }

  static String _currencySymbol(String code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      default:
        return 'ر.ي';
    }
  }

  /// Synchronous read of business_name from settings cache.
  /// Returns empty string if not set or unavailable.
  static String _getBusinessNameSync() {
    // We can't await here (the message builders are sync), so we
    // return empty string. The PDF generator already adds the
    // business name to the PDF header, so this is only for the text
    // message body. A future improvement could cache the business
    // name in a static field on app startup.
    return '';
  }

  /// Write PDF bytes to a temp file and return the File.
  static Future<File> _writeTempPdf(
    Map<String, dynamic> invoice,
    Uint8List bytes,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'invoice_${_displayInvoiceId(invoice)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }
}
