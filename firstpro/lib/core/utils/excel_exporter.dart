import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// أداة تصدير البيانات إلى ملفات Excel
class ExcelExporter {
  ExcelExporter._();

  /// تصدير شجرة الحسابات
  static Future<String> exportAccountsToExcel(List<Map<String, dynamic>> accounts) async {
    final excel = Excel.createExcel();
    final sheet = excel['الحسابات'];

    // حذف الشيت الافتراضي
    excel.delete('Sheet1');

    // ترويسات الأعمدة
    final headers = ['رمز الحساب', 'اسم الحساب', 'نوع الحساب', 'العملة', 'الرصيد', 'الحالة'];
    _addHeaders(sheet, headers);

    // البيانات
    for (var i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      final row = i + 2; // بعد صف الترويسة
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(account['account_code'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(account['name_ar'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(_accountTypeAr(account['account_type'] as String? ?? ''));
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(account['currency'] as String? ?? 'YER');
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue((account['balance'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('F$row')).value = TextCellValue((account['is_active'] as int?) == 1 ? 'نشط' : 'غير نشط');
    }

    return await _saveAndShare(excel, 'الحسابات');
  }

  /// تصدير الفواتير
  static Future<String> exportInvoicesToExcel(List<Map<String, dynamic>> invoices) async {
    final excel = Excel.createExcel();
    final sheet = excel['الفواتير'];

    excel.delete('Sheet1');

    final headers = ['رقم الفاتورة', 'النوع', 'التاريخ', 'الإجمالي الفرعي', 'الخصم', 'الضريبة', 'الإجمالي', 'المدفوع', 'المتبقي', 'الحالة', 'العملة'];
    _addHeaders(sheet, headers);

    for (var i = 0; i < invoices.length; i++) {
      final inv = invoices[i];
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(inv['id'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(_invoiceTypeAr(inv['type'] as String? ?? ''));
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(_formatDate(inv['created_at'] as String?));
      sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue((inv['subtotal'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue((inv['discount_amount'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue((inv['tax_amount'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('G$row')).value = DoubleCellValue((inv['total'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('H$row')).value = DoubleCellValue((inv['paid_amount'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('I$row')).value = DoubleCellValue((inv['remaining'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('J$row')).value = TextCellValue(inv['status'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('K$row')).value = TextCellValue(inv['currency'] as String? ?? 'YER');
    }

    return await _saveAndShare(excel, 'الفواتير');
  }

  /// تصدير المخزون
  static Future<String> exportInventoryToExcel(List<Map<String, dynamic>> products) async {
    final excel = Excel.createExcel();
    final sheet = excel['المخزون'];

    excel.delete('Sheet1');

    final headers = ['رمز الصنف', 'اسم المنتج', 'الباركود', 'سعر التكلفة', 'سعر البيع', 'الكمية الحالية', 'الحد الأدنى', 'المخزن', 'الحالة'];
    _addHeaders(sheet, headers);

    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(p['item_code'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(p['name_ar'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(p['barcode'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue((p['cost_price'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue((p['sell_price'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue((p['current_stock'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('G$row')).value = DoubleCellValue((p['min_stock'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('H$row')).value = TextCellValue(p['warehouse_name'] as String? ?? '');
      sheet.cell(CellIndex.indexByString('I$row')).value = TextCellValue((p['is_active'] as int?) == 1 ? 'نشط' : 'غير نشط');
    }

    return await _saveAndShare(excel, 'المخزون');
  }

  /// تصدير الحركات (القيود المحاسبية)
  static Future<String> exportTransactionsToExcel(List<Map<String, dynamic>> transactions) async {
    final excel = Excel.createExcel();
    final sheet = excel['الحركات'];

    excel.delete('Sheet1');

    final headers = ['التاريخ', 'الحساب', 'مدين', 'دائن', 'البيان'];
    _addHeaders(sheet, headers);

    for (var i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(_formatDate(t['date'] as String?));
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(t['account_name'] as String? ?? t['account_id']?.toString() ?? '');
      sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue((t['debit'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue((t['credit'] as num?)?.toDouble() ?? 0.0);
      sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue(t['description'] as String? ?? '');
    }

    return await _saveAndShare(excel, 'الحركات');
  }

  // ══════════════════════════════════════════════════════════════
  //  مساعدات خاصة
  // ══════════════════════════════════════════════════════════════

  /// إضافة صف الترويسة مع تنسيق
  static void _addHeaders(Sheet sheet, List<String> headers) {
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('2633C5'),
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
      );
    }
  }

  /// حفظ الملف ومشاركته
  static Future<String> _saveAndShare(Excel excel, String name) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/firstpro_${name}_$timestamp.xlsx';

    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'تقرير $name - الأول برو المحاسبي',
      );

      return filePath;
    }

    throw Exception('فشل في إنشاء ملف Excel');
  }

  /// ترجمة نوع الحساب
  static String _accountTypeAr(String type) {
    switch (type) {
      case 'ASSET':
        return 'أصول';
      case 'LIABILITY':
        return 'خصوم';
      case 'COST':
        return 'تكاليف';
      case 'REVENUE':
        return 'إيرادات';
      case 'EXPENSE':
        return 'مصاريف';
      default:
        return type;
    }
  }

  /// ترجمة نوع الفاتورة
  static String _invoiceTypeAr(String type) {
    switch (type) {
      case 'sale':
        return 'مبيعات';
      case 'purchase':
        return 'مشتريات';
      case 'sale_return':
        return 'مرتجع مبيعات';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'return':
        return 'مرتجع';
      default:
        return type;
    }
  }

  /// تنسيق التاريخ
  static String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
