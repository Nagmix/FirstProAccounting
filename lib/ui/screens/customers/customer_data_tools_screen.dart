import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/utils/bank_statement_importer.dart';
import 'package:firstpro/data/datasources/repositories/customer_repository.dart';

/// The operation exposed by the customer data routes.
enum CustomerDataAction { importData, loadData, printData }

class CustomerDataToolsScreen extends StatefulWidget {
  final CustomerDataAction action;

  const CustomerDataToolsScreen({
    super.key,
    required this.action,
  });

  @override
  State<CustomerDataToolsScreen> createState() =>
      _CustomerDataToolsScreenState();
}

class _CustomerImportRow {
  final String name;
  final String phone;
  final String address;
  final String email;
  final String currency;
  final String? error;

  const _CustomerImportRow({
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    required this.currency,
    this.error,
  });

  bool get isValid => error == null;
}

class _CustomerDataToolsScreenState extends State<CustomerDataToolsScreen> {
  final _repository = locator<CustomerRepository>();
  List<_CustomerImportRow> _rows = [];
  List<Map<String, dynamic>> _printRows = [];
  bool _isBusy = false;
  String? _fileName;
  String? _message;

  bool get _isPrint => widget.action == CustomerDataAction.printData;

  String get _title {
    switch (widget.action) {
      case CustomerDataAction.importData:
        return 'استيراد العملاء';
      case CustomerDataAction.loadData:
        return 'تحميل قائمة العملاء';
      case CustomerDataAction.printData:
        return 'طباعة قائمة العملاء';
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isPrint) _loadPrintRows();
  }

  Future<void> _loadPrintRows() async {
    try {
      final rows = await _repository.getAllCustomers(orderBy: 'name');
      if (mounted) setState(() => _printRows = rows);
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر تحميل العملاء: $error');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isBusy = true;
        _message = null;
        _fileName = result.files.single.name;
      });
      final rawRows = await BankStatementImporter.parseFile(
        File(result.files.single.path!),
      );
      final existing = await _repository.getAllCustomers();
      final existingKeys = existing
          .map((row) => _identityKey(
                (row['name'] as String?) ?? '',
                (row['phone'] as String?) ?? '',
              ))
          .toSet();
      final seenKeys = <String>{};
      final parsed = rawRows.map((row) {
        final name = _read(row, const ['name', 'customer', 'الاسم', 'العميل']);
        final phone = _read(row, const ['phone', 'mobile', 'هاتف', 'الجوال']);
        final address = _read(row, const ['address', 'العنوان']);
        final email = _read(row, const ['email', 'البريد']);
        final rawCurrency =
            _read(row, const ['currency', 'العملة']).toUpperCase().trim();
        final currency = rawCurrency.isEmpty ? 'YER' : rawCurrency;
        final balanceText = _read(row, const ['balance', 'الرصيد']);
        final balance = _parseMoney(balanceText);
        final key = _identityKey(name, phone);
        String? error;
        if (name.trim().isEmpty) {
          error = 'اسم العميل مطلوب';
        } else if (!const {'YER', 'SAR', 'USD'}.contains(currency)) {
          error = 'عملة العميل غير مدعومة: $currency';
        } else if (balance.abs() > 0.005) {
          error = 'الرصيد الافتتاحي لا يُستورد آلياً؛ أدخله من شاشة العميل بعد مراجعة الحساب';
        } else if (existingKeys.contains(key) || !seenKeys.add(key)) {
          error = 'عميل مكرر بالاسم والهاتف';
        }
        return _CustomerImportRow(
          name: name,
          phone: phone,
          address: address,
          email: email,
          currency: currency,
          error: error,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _rows = parsed;
          _isBusy = false;
          _message = parsed.isEmpty ? 'الملف فارغ أو لا يحتوي صفوفاً' : null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _message = 'تعذر قراءة الملف: $error';
        });
      }
    }
  }

  Future<void> _importRows() async {
    final validRows = _rows.where((row) => row.isValid).toList();
    if (validRows.isEmpty) {
      setState(() => _message = 'لا توجد صفوف صالحة للاستيراد');
      return;
    }
    setState(() {
      _isBusy = true;
      _message = null;
    });
    var imported = 0;
    var failed = 0;
    for (final row in validRows) {
      try {
        await _repository.insertCustomer({
          'name': row.name.trim(),
          'phone': row.phone.trim().isEmpty ? null : row.phone.trim(),
          'address': row.address.trim().isEmpty ? null : row.address.trim(),
          'email': row.email.trim().isEmpty ? null : row.email.trim(),
          'currency': row.currency,
          'balance': 0.0,
          'balance_type': 'credit',
        });
        imported++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _message = 'تم تحميل $imported عميل${failed > 0 ? '، وتعذر تحميل $failed' : ''}';
    });
  }

  Future<void> _printCustomers() async {
    if (_printRows.isEmpty) {
      setState(() => _message = 'لا توجد عملاء للطباعة');
      return;
    }
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      pw.Font? arabicFont;
      try {
        final data = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
        arabicFont = pw.Font.ttf(data);
      } catch (_) {}
      final printedDate = DateTime.now().toIso8601String().split('T').first;
      final cellStyle = pw.TextStyle(font: arabicFont, fontSize: 9);
      final headerStyle = pw.TextStyle(
        font: arabicFont,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      );
      final document = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont ?? pw.Font.helvetica(),
          bold: arabicFont ?? pw.Font.helveticaBold(),
        ),
      );
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => [
            pw.Text('قائمة العملاء',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                )),
            pw.SizedBox(height: 8),
            pw.Text('تاريخ الطباعة: $printedDate', style: cellStyle),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(2.4),
                3: pw.FlexColumnWidth(0.8),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.green700),
                  children: [
                    _pdfCell('الاسم', headerStyle),
                    _pdfCell('الهاتف', headerStyle),
                    _pdfCell('العنوان', headerStyle),
                    _pdfCell('العملة', headerStyle),
                  ],
                ),
                ..._printRows.map((row) => pw.TableRow(children: [
                      _pdfCell((row['name'] as String?) ?? '', cellStyle),
                      _pdfCell((row['phone'] as String?) ?? '', cellStyle),
                      _pdfCell((row['address'] as String?) ?? '', cellStyle),
                      _pdfCell((row['currency'] as String?) ?? 'YER', cellStyle),
                    ])),
              ],
            ),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => document.save());
      if (mounted) setState(() => _message = 'تم إرسال قائمة العملاء إلى الطباعة');
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذرت الطباعة: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  static pw.Widget _pdfCell(String value, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(value, style: style, textAlign: pw.TextAlign.right),
      );

  static String _read(Map<String, String> row, List<String> keywords) {
    for (final entry in row.entries) {
      final key = entry.key.toLowerCase().trim();
      if (keywords.any((keyword) => key.contains(keyword.toLowerCase()))) {
        return entry.value.trim();
      }
    }
    return '';
  }

  static double _parseMoney(String value) {
    final normalized = value.replaceAll(',', '').replaceAll(' ', '').trim();
    return double.tryParse(normalized) ?? 0.0;
  }

  static String _identityKey(String name, String phone) =>
      '${name.trim().toLowerCase()}|${phone.trim()}';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: _isPrint ? _buildPrintBody() : _buildImportBody(),
      ),
    );
  }

  Widget _buildPrintBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('عدد العملاء: ${_printRows.length}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Expanded(
            child: _printRows.isEmpty
                ? const Center(child: Text('لا توجد بيانات عملاء'))
                : ListView.builder(
                    itemCount: _printRows.length,
                    itemBuilder: (_, index) {
                      final row = _printRows[index];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text((row['name'] as String?) ?? ''),
                        subtitle: Text((row['phone'] as String?) ?? ''),
                      );
                    },
                  ),
          ),
          FilledButton.icon(
            onPressed: _isBusy ? null : _printCustomers,
            icon: const Icon(Icons.print),
            label: Text(_isBusy ? 'جارٍ التجهيز...' : 'طباعة القائمة'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildImportBody() {
    final validCount = _rows.where((row) => row.isValid).length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اختر ملف CSV أو Excel. الأعمدة المدعومة: الاسم، الهاتف، العنوان، البريد، العملة. لا تُستورد الأرصدة الافتتاحية آلياً حفاظاً على دفتر الأستاذ؛ أدخلها بعد المراجعة من شاشة العميل.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _pickFile,
            icon: const Icon(Icons.file_open),
            label: Text(_fileName ?? 'اختيار ملف العملاء'),
          ),
          const SizedBox(height: 12),
          if (_isBusy) const LinearProgressIndicator(),
          if (_rows.isNotEmpty)
            Text('الصفوف الصالحة: $validCount من ${_rows.length}'),
          const SizedBox(height: 8),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('لم يتم تحميل ملف بعد'))
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (_, index) {
                      final row = _rows[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            row.isValid ? Icons.check_circle : Icons.error,
                            color: row.isValid ? Colors.green : Colors.orange,
                          ),
                          title: Text(row.name.isEmpty ? 'بدون اسم' : row.name),
                          subtitle: Text(row.error ??
                              '${row.phone} — ${row.currency}'),
                        ),
                      );
                    },
                  ),
          ),
          FilledButton.icon(
            onPressed: _isBusy || validCount == 0 ? null : _importRows,
            icon: const Icon(Icons.download_done),
            label: Text(widget.action == CustomerDataAction.importData
                ? 'استيراد العملاء الصالحين'
                : 'تحميل العملاء الصالحين'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
