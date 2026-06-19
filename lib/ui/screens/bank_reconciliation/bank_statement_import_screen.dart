import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/bank_statement_importer.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/bank_reconciliation_service.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/models/bank_reconciliation_model.dart';

/// F-02: Bank statement import screen.
///
/// Allows the user to import a bank statement from a CSV or Excel file
/// into a bank reconciliation session. The flow:
///   1. Select a cash box (bank account).
///   2. Pick a file (.csv or .xlsx).
///   3. Auto-detect column mapping (with manual override).
///   4. Preview the parsed lines.
///   5. Confirm to insert into the reconciliation.
class BankStatementImportScreen extends StatefulWidget {
  final int? reconciliationId;

  const BankStatementImportScreen({super.key, this.reconciliationId});

  @override
  State<BankStatementImportScreen> createState() =>
      _BankStatementImportScreenState();
}

class _BankStatementImportScreenState
    extends State<BankStatementImportScreen> {
  final _bankReconService = locator<BankReconciliationService>();
  final _cashBoxService = locator<CashBoxService>();

  List<Map<String, dynamic>> _cashBoxes = [];
  int? _selectedCashBoxId;
  List<String> _headers = [];
  List<Map<String, String>> _rawRows = [];
  ColumnMapping? _mapping;
  List<BankStatementLine> _previewLines = [];
  bool _isLoading = false;
  bool _isImporting = false;
  String? _fileName;

  @override
  void initState() {
    super.initState();
    _loadCashBoxes();
  }

  Future<void> _loadCashBoxes() async {
    try {
      _cashBoxes = await _bankReconService.getBankCashBoxes();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في تحميل الحسابات البنكية: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    if (_selectedCashBoxId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار الحساب البنكي أولاً'),
            backgroundColor: AppColors.warning),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      _fileName = result.files.first.name;

      setState(() => _isLoading = true);

      final rows = await BankStatementImporter.parseFile(file);
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('الملف فارغ أو لا يحتوي على بيانات'),
                backgroundColor: AppColors.warning),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      _headers = rows.first.keys.toList();
      _rawRows = rows;
      _mapping = BankStatementImporter.autoDetectColumns(_headers);
      _updatePreview();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في قراءة الملف: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _updatePreview() {
    if (_mapping == null || _selectedCashBoxId == null) {
      _previewLines = [];
      return;
    }
    _previewLines = BankStatementImporter.convertToStatementLines(
      rows: _rawRows,
      mapping: _mapping!,
      cashBoxId: _selectedCashBoxId!,
      reconciliationId: widget.reconciliationId,
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmImport() async {
    if (_previewLines.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await _bankReconService.addStatementLines(_previewLines);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم استيراد ${_previewLines.length} بند بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, _previewLines.length);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطأ في الاستيراد: $e'),
            backgroundColor: AppColors.error),
      );
    }
    if (mounted) setState(() => _isImporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استيراد كشف حساب بنكي'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCashBoxSelector(theme),
                    const SizedBox(height: 16),
                    _buildFilePicker(theme),
                    if (_mapping != null) ...[
                      const SizedBox(height: 16),
                      _buildColumnMapping(theme),
                      const SizedBox(height: 16),
                      _buildPreview(theme),
                      const SizedBox(height: 16),
                      _buildImportButton(theme),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCashBoxSelector(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الحساب البنكي',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedCashBoxId,
              decoration: const InputDecoration(
                labelText: 'اختر الحساب البنكي',
                border: OutlineInputBorder(),
              ),
              items: _cashBoxes
                  .map((cb) => DropdownMenuItem(
                        value: cb['id'] as int,
                        child: Text(
                            '${cb['name']} (${cb['currency'] ?? 'YER'})'),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedCashBoxId = v);
                _updatePreview();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePicker(ThemeData theme) {
    return Card(
      child: InkWell(
        onTap: _pickFile,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.upload_file,
                  size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                _fileName ?? 'اختر ملف كشف الحساب',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'الصيغ المدعومة: CSV, Excel (.xlsx)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumnMapping(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تعيين الأعمدة',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'تم التعريف التلقائي — يمكنك التعديل',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 12),
            _mappingDropdown('التاريخ', _mapping!.dateColumn, (v) {
              _mapping = _mapping!.copyWith(dateColumn: v);
              _updatePreview();
            }),
            if (_mapping!.creditColumn != null || _mapping!.debitColumn != null)
              ...[
                _mappingDropdown('الإيداع (Credit)', _mapping!.creditColumn,
                    (v) {
                  _mapping = _mapping!.copyWith(creditColumn: v);
                  _updatePreview();
                }),
                _mappingDropdown('السحب (Debit)', _mapping!.debitColumn, (v) {
                  _mapping = _mapping!.copyWith(debitColumn: v);
                  _updatePreview();
                }),
              ]
            else
              ...[
                _mappingDropdown('المبلغ', _mapping!.amountColumn, (v) {
                  _mapping = _mapping!.copyWith(amountColumn: v);
                  _updatePreview();
                }),
                _mappingDropdown('النوع (اختياري)', _mapping!.typeColumn, (v) {
                  _mapping = _mapping!.copyWith(typeColumn: v);
                  _updatePreview();
                }),
              ],
            _mappingDropdown('المرجع', _mapping!.referenceColumn, (v) {
              _mapping = _mapping!.copyWith(referenceColumn: v);
              _updatePreview();
            }),
            _mappingDropdown('البيان', _mapping!.descriptionColumn, (v) {
              _mapping = _mapping!.copyWith(descriptionColumn: v);
              _updatePreview();
            }),
          ],
        ),
      ),
    );
  }

  Widget _mappingDropdown(
      String label, String? value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('—')),
          ..._headers
              .map((h) => DropdownMenuItem(value: h, child: Text(h))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_previewLines.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'لا توجد بنود صالحة للاستيراد. تحقق من تعيين الأعمدة.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textHint),
            ),
          ),
        ),
      );
    }

    // Show up to 10 preview rows + count of remaining.
    final previewCount = _previewLines.length > 10 ? 10 : _previewLines.length;
    final totalCredit = _previewLines
        .where((l) => l.transactionType == 'credit')
        .fold(0.0, (sum, l) => sum + l.amount);
    final totalDebit = _previewLines
        .where((l) => l.transactionType == 'debit')
        .fold(0.0, (sum, l) => sum + l.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('معاينة (${_previewLines.length} بند)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        'إيداعات: ${CurrencyFormatter.format(totalCredit)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.success)),
                    Text(
                        'سحوبات: ${CurrencyFormatter.format(totalDebit)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.error)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < previewCount; i++)
              _buildPreviewRow(_previewLines[i], theme),
            if (_previewLines.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... و ${_previewLines.length - 10} بند آخر',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textHint),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(BankStatementLine line, ThemeData theme) {
    final isCredit = line.transactionType == 'credit';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            size: 16,
            color: isCredit ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description ?? line.reference ?? '—',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormatter.formatDate(line.transactionDate),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(line.amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isCredit ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed:
            _isImporting || _previewLines.isEmpty ? null : _confirmImport,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.file_download),
        label: Text(_isImporting
            ? 'جاري الاستيراد...'
            : 'استيراد ${_previewLines.length} بند'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
