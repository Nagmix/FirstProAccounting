import 'dart:convert';
import 'dart:typed_data';

/// ESC/POS command generator for 80mm/58mm thermal printers.
///
/// Generates raw byte commands for thermal receipt printers using
/// the ESC/POS protocol. Supports Arabic text via code page 1256.
class EscPosCommands {
  EscPosCommands._();

  // ── ESC/POS Command Bytes ──────────────────────────────────────
  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _fs = 0x1C;
  static const int _lf = 0x0A;
  static const int _cr = 0x0D;

  /// Initialize printer (reset to defaults).
  static List<int> init() {
    return [_esc, 0x40]; // ESC @
  }

  /// Set text alignment.
  /// [align]: 0=left, 1=center, 2=right
  static List<int> setAlignment(int align) {
    return [_esc, 0x61, align.clamp(0, 2)]; // ESC a n
  }

  /// Turn bold on.
  static List<int> boldOn() {
    return [_esc, 0x45, 0x01]; // ESC E 1
  }

  /// Turn bold off.
  static List<int> boldOff() {
    return [_esc, 0x45, 0x00]; // ESC E 0
  }

  /// Turn underline on.
  static List<int> underlineOn() {
    return [_esc, 0x2D, 0x01]; // ESC - 1
  }

  /// Turn underline off.
  static List<int> underlineOff() {
    return [_esc, 0x2D, 0x00]; // ESC - 0
  }

  /// Set font size.
  /// [doubleHeight]: double the height
  /// [doubleWidth]: double the width
  static List<int> setFontSize(bool doubleHeight, bool doubleWidth) {
    int value = 0;
    if (doubleHeight) value |= 0x01;
    if (doubleWidth) value |= 0x10;
    return [_gs, 0x21, value]; // GS ! n
  }

  /// Set normal font size.
  static List<int> normalFontSize() {
    return [_gs, 0x21, 0x00]; // GS ! 0
  }

  /// Print text with default encoding (UTF-8).
  static List<int> printText(String text) {
    return utf8.encode(text);
  }

  /// Print text and add newline.
  static List<int> println(String text) {
    return [...utf8.encode(text), _lf];
  }

  /// Print Arabic text using code page 1256 (Windows Arabic).
  static List<int> printArabicText(String text) {
    // Set code page to 1256 (Arabic)
    final codePageCmd = [_esc, 0x74, 0x10]; // ESC t 16 (CP1256)

    // Encode using Windows-1256
    final encoded = _encodeCp1256(text);
    return [...codePageCmd, ...encoded];
  }

  /// Print Arabic text line (with newline).
  static List<int> printlnArabic(String text) {
    return [...printArabicText(text), _lf];
  }

  /// Feed [count] lines.
  static List<int> feedLines(int count) {
    return [_esc, 0x64, count.clamp(1, 255)]; // ESC d n
  }

  /// Feed [count] dots (fine feed).
  static List<int> feedDots(int count) {
    return [_esc, 0x4A, count.clamp(0, 255)]; // ESC J n
  }

  /// Print dashed line across the paper.
  /// [charsPerLine] defaults to 48 for 80mm paper, 32 for 58mm.
  static List<int> dashedLine({int charsPerLine = 48}) {
    return [...utf8.encode('-' * charsPerLine), _lf];
  }

  /// Print double dashed line.
  static List<int> doubleLine({int charsPerLine = 48}) {
    return [...utf8.encode('=' * charsPerLine), _lf];
  }

  /// Print a solid line (using ESC/POS graphics).
  static List<int> solidLine({int width = 576}) {
    final w = (width / 8).ceil();
    final data = List<int>.filled(w, 0xFF); // All bits set = solid line
    return [
      _esc, 0x2A, 0x00, // ESC * m=0 (8-dot single density)
      w & 0xFF, (w >> 8) & 0xFF, // nL nH
      ...data,
      _lf,
    ];
  }

  /// Cut paper (full cut).
  static List<int> cutPaper() {
    return [_gs, 0x56, 0x01]; // GS V 1 (full cut with feed)
  }

  /// Cut paper (partial cut).
  static List<int> partialCut() {
    return [_gs, 0x56, 0x00]; // GS V 0 (partial cut with feed)
  }

  /// Open cash drawer (pulse on pin 2).
  static List<int> openCashDrawer() {
    return [_esc, 0x70, 0x00, 0x19, 0xFA]; // ESC p 0 t1 t2
  }

  /// Print barcode (CODE128).
  /// [data]: the barcode content
  /// [width]: module width (2-6)
  /// [height]: barcode height in dots
  static List<int> printBarcode(String data, {int width = 2, int height = 100}) {
    final dataBytes = utf8.encode(data);
    return [
      _gs, 0x77, width.clamp(2, 6), // GS w (module width)
      _gs, 0x68, height.clamp(1, 255), // GS h (height)
      _gs, 0x6B, 0x49, // GS k 73 (CODE128)
      dataBytes.length, // n (data length)
      ...dataBytes,
    ];
  }

  /// Set character spacing.
  static List<int> setCharSpacing(int spacing) {
    return [_esc, 0x20, spacing.clamp(0, 255)]; // ESC SP n
  }

  /// Set line spacing to n/180 inch.
  static List<int> setLineSpacing(int n) {
    return [_esc, 0x33, n.clamp(0, 255)]; // ESC 3 n
  }

  /// Reset line spacing to default.
  static List<int> resetLineSpacing() {
    return [_esc, 0x32]; // ESC 2
  }

  /// Select character code table.
  /// [codeTable]: code table number (e.g., 16 = CP1256 Arabic)
  static List<int> selectCodeTable(int codeTable) {
    return [_esc, 0x74, codeTable]; // ESC t n
  }

  /// Enable/disable reverse color (white on black).
  static List<int> setReverseColor(bool enable) {
    return [_gs, 0x42, enable ? 0x01 : 0x00]; // GS B n
  }

  /// Set left margin.
  /// [marginLeft]: margin in dots
  static List<int> setLeftMargin(int marginLeft) {
    return [_gs, 0x4C, marginLeft & 0xFF, (marginLeft >> 8) & 0xFF]; // GS L nL nH
  }

  /// Print QR code (if printer supports it).
  /// Note: Not all thermal printers support QR. This uses the standard
  /// GS ( k QR code command structure.
  static List<int> printQRCode(String data, {int moduleSize = 4, int errorCorrection = 1}) {
    final dataBytes = utf8.encode(data);
    return [
      // QR model selection
      _gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      // Module size
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize.clamp(1, 16),
      // Error correction level
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, errorCorrection.clamp(0, 3),
      // Store data
      _gs, 0x28, 0x6B, (dataBytes.length + 3) & 0xFF, ((dataBytes.length + 3) >> 8) & 0xFF,
      0x31, 0x50, 0x30, ...dataBytes,
      // Print
      _gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x44, 0x30,
    ];
  }

  /// Build a complete receipt from structured data.
  static List<int> buildReceipt({
    required String businessName,
    String? businessPhone,
    String? businessAddress,
    required String invoiceNumber,
    required String invoiceType,
    required DateTime date,
    required String customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required double remaining,
    String currency = 'ر.ي',
    String? notes,
    int charsPerLine = 48,
    bool autoCut = true,
  }) {
    final cmds = <int>[];

    // Initialize
    cmds.addAll(init());

    // Select Arabic code page
    cmds.addAll(selectCodeTable(16)); // CP1256

    // Business name (centered, bold, large)
    cmds.addAll(setAlignment(1)); // center
    cmds.addAll(boldOn());
    cmds.addAll(setFontSize(true, true));
    cmds.addAll(printlnArabic(businessName));
    cmds.addAll(normalFontSize());
    cmds.addAll(boldOff());

    // Business details
    if (businessPhone != null && businessPhone.isNotEmpty) {
      cmds.addAll(printlnArabic('هاتف: $businessPhone'));
    }
    if (businessAddress != null && businessAddress.isNotEmpty) {
      cmds.addAll(printlnArabic('عنوان: $businessAddress'));
    }

    cmds.addAll(feedLines(1));
    cmds.addAll(dashedLine(charsPerLine: charsPerLine));

    // Invoice header
    cmds.addAll(boldOn());
    cmds.addAll(setAlignment(1));
    cmds.addAll(printlnArabic(invoiceType));
    cmds.addAll(boldOff());
    cmds.addAll(setAlignment(0)); // right

    // Invoice info
    cmds.addAll(printlnArabic('رقم الفاتورة: $invoiceNumber'));
    cmds.addAll(printlnArabic('التاريخ: ${date.day}/${date.month}/${date.year}'));
    cmds.addAll(printlnArabic('الوقت: ${date.hour}:${date.minute.toString().padLeft(2, '0')}'));
    cmds.addAll(printlnArabic('العميل: $customerName'));

    cmds.addAll(dashedLine(charsPerLine: charsPerLine));

    // Items header
    cmds.addAll(boldOn());
    cmds.addAll(printlnArabic(_padColumns(
      ['الصنف', 'الكمية', 'السعر', 'الإجمالي'],
      [20, 8, 10, 10],
      charsPerLine: charsPerLine,
    )));
    cmds.addAll(boldOff());
    cmds.addAll(dashedLine(charsPerLine: charsPerLine));

    // Items
    for (final item in items) {
      final name = (item['product_name'] ?? item['name'] ?? '').toString();
      final qty = (item['quantity'] ?? 1).toString();
      final price = _formatAmount((item['unit_price'] ?? item['price'] ?? 0).toDouble());
      final itemTotal = _formatAmount((item['total_price'] ?? item['total'] ?? 0).toDouble());

      cmds.addAll(printlnArabic(_padColumns(
        [name, qty, price, itemTotal],
        [20, 8, 10, 10],
        charsPerLine: charsPerLine,
      )));
    }

    cmds.addAll(dashedLine(charsPerLine: charsPerLine));

    // Totals
    cmds.addAll(setAlignment(2)); // left (in RTL context)
    cmds.addAll(printlnArabic('المجموع الفرعي: ${_formatAmount(subtotal)} $currency'));

    if (discount > 0) {
      cmds.addAll(printlnArabic('الخصم: ${_formatAmount(discount)} $currency'));
    }
    if (tax > 0) {
      cmds.addAll(printlnArabic('الضريبة: ${_formatAmount(tax)} $currency'));
    }

    cmds.addAll(boldOn());
    cmds.addAll(setFontSize(true, false));
    cmds.addAll(printlnArabic('الإجمالي: ${_formatAmount(total)} $currency'));
    cmds.addAll(normalFontSize());
    cmds.addAll(boldOff());

    if (paid > 0) {
      cmds.addAll(printlnArabic('المدفوع: ${_formatAmount(paid)} $currency'));
      cmds.addAll(printlnArabic('المتبقي: ${_formatAmount(remaining)} $currency'));
    }

    if (notes != null && notes.isNotEmpty) {
      cmds.addAll(feedLines(1));
      cmds.addAll(printlnArabic('ملاحظات: $notes'));
    }

    cmds.addAll(dashedLine(charsPerLine: charsPerLine));
    cmds.addAll(setAlignment(1));
    cmds.addAll(printlnArabic('شكراً لتعاملكم معنا'));

    // Feed and cut
    cmds.addAll(feedLines(3));
    if (autoCut) {
      cmds.addAll(cutPaper());
    }

    return cmds;
  }

  /// Build a test print receipt.
  static List<int> buildTestPrint({int charsPerLine = 48}) {
    final cmds = <int>[];

    cmds.addAll(init());
    cmds.addAll(selectCodeTable(16));
    cmds.addAll(setAlignment(1));
    cmds.addAll(boldOn());
    cmds.addAll(setFontSize(true, true));
    cmds.addAll(printlnArabic('اختبار الطابعة'));
    cmds.addAll(normalFontSize());
    cmds.addAll(boldOff());
    cmds.addAll(feedLines(1));
    cmds.addAll(dashedLine(charsPerLine: charsPerLine));
    cmds.addAll(setAlignment(0));
    cmds.addAll(printlnArabic('تم الاتصال بنجاح'));
    cmds.addAll(printlnArabic('الأول برو المحاسبي'));
    cmds.addAll(printlnArabic('التاريخ: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'));
    cmds.addAll(printlnArabic('الوقت: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}'));
    cmds.addAll(feedLines(1));
    cmds.addAll(boldOn());
    cmds.addAll(printlnArabic('الطباعة بلوتوث حرارية'));
    cmds.addAll(boldOff());
    cmds.addAll(dashedLine(charsPerLine: charsPerLine));

    // Test Arabic
    cmds.addAll(setAlignment(1));
    cmds.addAll(printlnArabic('مرحباً بالعربية'));
    cmds.addAll(printlnArabic('1234567890'));

    // Test barcode
    cmds.addAll(feedLines(1));
    cmds.addAll(printBarcode('1234567890'));

    cmds.addAll(feedLines(1));
    cmds.addAll(setAlignment(1));
    cmds.addAll(printlnArabic('نهاية اختبار الطابعة'));
    cmds.addAll(feedLines(3));
    cmds.addAll(cutPaper());

    return cmds;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Encode string using Windows-1256 (Arabic) code page.
  static List<int> _encodeCp1256(String text) {
    final result = <int>[];
    for (int i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      // Windows-1256 mapping for Arabic characters
      if (codeUnit < 128) {
        result.add(codeUnit);
      } else {
        // Map common Arabic Unicode code points to CP1256
        final cp1256 = _arabicUnicodeToCp1256(codeUnit);
        if (cp1256 != null) {
          result.add(cp1256);
        } else {
          // Fallback: use UTF-8 encoding for unmapped characters
          result.addAll(utf8.encode(String.fromCharCode(codeUnit)));
        }
      }
    }
    return result;
  }

  /// Map Unicode Arabic characters to CP1256 equivalents.
  static int? _arabicUnicodeToCp1256(int codeUnit) {
    // Common Arabic character mapping (Unicode → CP1256)
    const mapping = <int, int>{
      0x060C: 0xA1, // Arabic comma
      0x061B: 0xBA, // Arabic semicolon
      0x061F: 0xBF, // Arabic question mark
      0x0621: 0xC0, // Hamza
      0x0622: 0xC1, // Alef with madda
      0x0623: 0xC2, // Alef with hamza above
      0x0624: 0xC3, // Waw with hamza
      0x0625: 0xC4, // Alef with hamza below
      0x0626: 0xC5, // Yeh with hamza
      0x0627: 0xC6, // Alef
      0x0628: 0xC7, // Beh
      0x0629: 0xC8, // Teh marbuta
      0x062A: 0xC9, // Teh
      0x062B: 0xCA, // Theh
      0x062C: 0xCB, // Jeem
      0x062D: 0xCC, // Hah
      0x062E: 0xCD, // Khah
      0x062F: 0xCE, // Dal
      0x0630: 0xCF, // Thal
      0x0631: 0xD0, // Reh
      0x0632: 0xD1, // Zain
      0x0633: 0xD2, // Seen
      0x0634: 0xD3, // Sheen
      0x0635: 0xD4, // Sad
      0x0636: 0xD5, // Dad
      0x0637: 0xD6, // Tah
      0x0638: 0xD7, // Zah
      0x0639: 0xD8, // Ain
      0x063A: 0xD9, // Ghain
      0x0640: 0xE0, // Tatweel
      0x0641: 0xE1, // Feh
      0x0642: 0xE2, // Qaf
      0x0643: 0xE3, // Kaf
      0x0644: 0xE4, // Lam
      0x0645: 0xE5, // Meem
      0x0646: 0xE6, // Noon
      0x0647: 0xE7, // Heh
      0x0648: 0xE8, // Waw
      0x0649: 0xE9, // Alef maksura
      0x064A: 0xEA, // Yeh
      0x064B: 0xEB, // Fathatan
      0x064C: 0xEC, // Dammatan
      0x064D: 0xED, // Kasratan
      0x064E: 0xEE, // Fatha
      0x064F: 0xEF, // Damma
      0x0650: 0xF0, // Kasra
      0x0651: 0xF1, // Shadda
      0x0652: 0xF2, // Sukun
    };
    return mapping[codeUnit];
  }

  /// Format amount for receipt display.
  static String _formatAmount(double amount) {
    return amount.toStringAsFixed(2);
  }

  /// Pad columns for receipt table alignment.
  static String _padColumns(List<String> columns, List<int> widths, {int charsPerLine = 48}) {
    final buffer = StringBuffer();
    for (int i = 0; i < columns.length; i++) {
      final text = columns[i];
      final width = i < widths.length ? widths[i] : 10;
      if (text.length > width) {
        buffer.write(text.substring(0, width));
      } else {
        buffer.write(text.padLeft(width));
      }
    }
    return buffer.toString();
  }
}
