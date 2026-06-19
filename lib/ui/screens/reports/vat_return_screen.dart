import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/utils/excel_exporter.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/report_service.dart';

// ═══════════════════════════════════════════════════════════════════
//  VAT Return Screen (شاشة إقرار ضريبة القيمة المضافة) — A-04
//
//  Shows Output VAT (from sale/POS invoices) and Input VAT (from
//  purchase invoices) for a given period and currency, with the
//  net VAT payable or refundable.
//
//  Data source: ReportService.getVatReturnSummary / getVatReturnDetails
//  which read invoices.tax_amount (captured at posting time, matches
//  the journal entries to accounts 2300+offset / 1400+offset).
//
//  Returns are signed (negative) so net VAT reflects the true payable
//  or refundable amount after returns.
// ═══════════════════════════════════════════════════════════════════

class VatReturnScreen extends StatefulWidget {
  const VatReturnScreen({super.key});

  @override
  State<VatReturnScreen> createState() => _VatReturnScreenState();
}

class _VatReturnScreenState extends State<VatReturnScreen> {
  bool _isLoading = false;
  String _selectedCurrency = 'SAR'; // default SAR (15% VAT)
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Summary state (per-currency when _selectedCurrency = 'الكل')
  List<Map<String, dynamic>> _summaryRows = [];

  // Details state (per-invoice rows for the selected direction)
  List<Map<String, dynamic>> _detailRows = [];

  // Net payable for the currently selected currency
  Map<String, dynamic>? _netPayable;

  // Detail view filter: 'output' / 'input' / null (both)
  String? _detailDirection;

  List<String> get _currencyOptions =>
      CurrencyConstants.currencyOptionsWithAll;

  bool get _isAllCurrencies => _selectedCurrency == 'الكل';

  String _currentSymbol() =>
      _isAllCurrencies ? '' : CurrencyConstants.currencySymbol(_selectedCurrency);

  @override
  void initState() {
    super.initState();
    // Default to current month
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final reportService = locator<ReportService>();
      final currencyArg = _isAllCurrencies ? null : _selectedCurrency;

      // Load summary (one row per currency, or single row for the
      // selected currency).
      _summaryRows = await reportService.getVatReturnSummary(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        currency: currencyArg,
      );

      // Load detail rows for the currently selected direction.
      _detailRows = await reportService.getVatReturnDetails(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        currency: currencyArg,
        vatDirection: _detailDirection,
      );

      // Load net payable for single-currency view.
      if (!_isAllCurrencies) {
        _netPayable = await reportService.getVatNetPayable(
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          currency: _selectedCurrency,
        );
      } else {
        _netPayable = null;
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إقرار ضريبة القيمة المضافة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadData,
              tooltip: 'تحديث',
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _isLoading || _detailRows.isEmpty
                  ? null
                  : _exportToExcel,
              tooltip: 'تصدير Excel',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFiltersCard(theme, isDark),
                    const SizedBox(height: 16),
                    _buildSummaryCard(theme, isDark),
                    const SizedBox(height: 16),
                    if (_netPayable != null)
                      _buildNetPayableCard(theme, isDark),
                    if (_netPayable != null) const SizedBox(height: 16),
                    _buildDetailsSection(theme, isDark),
                  ],
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Filters card (date range + currency)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFiltersCard(ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الفترة والعملة',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    label: 'من تاريخ',
                    date: _dateFrom,
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDateField(
                    label: 'إلى تاريخ',
                    date: _dateTo,
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: 'العملة',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _currencyOptions
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c == 'الكل'
                            ? 'كل العملات'
                            : '${CurrencyConstants.currencyLabel(c)} ($c)'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCurrency = v);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(date == null
            ? '—'
            : DateFormatter.formatDate(date)),
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    _loadData();
  }

  // ═══════════════════════════════════════════════════════════════
  //  Summary card (per-currency totals)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryCard(ThemeData theme, bool isDark) {
    if (_summaryRows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.receipt_long,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 8),
              const Text('لا توجد فواتير خاضعة للضريبة في هذه الفترة'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ملخص الإقرار',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            // Header row
            _buildSummaryHeader(theme),
            const Divider(height: 24),
            // Body rows (one per currency)
            for (final row in _summaryRows) _buildSummaryRow(row, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('العملة', style: theme.textTheme.labelMedium)),
          Expanded(flex: 3, child: Text('ض. المخرجات', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
          Expanded(flex: 3, child: Text('ض. المدخلات', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
          Expanded(flex: 3, child: Text('الصافي', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(Map<String, dynamic> row, ThemeData theme) {
    final currency = row['currency'] as String? ?? '?';
    final symbol = CurrencyConstants.currencySymbol(currency);

    final outputVat = MoneyHelper.readCalculatedMoney(row['output_vat']);
    final outputVatReturns =
        MoneyHelper.readCalculatedMoney(row['output_vat_returns']);
    final inputVat = MoneyHelper.readCalculatedMoney(row['input_vat']);
    final inputVatReturns =
        MoneyHelper.readCalculatedMoney(row['input_vat_returns']);
    final netOutput = outputVat - outputVatReturns;
    final netInput = inputVat - inputVatReturns;
    final net = netOutput - netInput;

    final isPayable = net > 0;
    final isRefundable = net < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(currency, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.format(netOutput, symbol: symbol),
                    style: theme.textTheme.bodyMedium),
                if (outputVatReturns > 0)
                  Text('(-${CurrencyFormatter.format(outputVatReturns, symbol: symbol)} مرتجع)',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.format(netInput, symbol: symbol),
                    style: theme.textTheme.bodyMedium),
                if (inputVatReturns > 0)
                  Text('(-${CurrencyFormatter.format(inputVatReturns, symbol: symbol)} مرتجع)',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              CurrencyFormatter.formatSigned(net, symbol: symbol),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isPayable
                    ? AppColors.error
                    : (isRefundable ? AppColors.success : null),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Net payable card (single-currency view)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNetPayableCard(ThemeData theme, bool isDark) {
    final np = _netPayable!;
    final currency = np['currency'] as String? ?? _selectedCurrency;
    final symbol = CurrencyConstants.currencySymbol(currency);
    final outputVat = MoneyHelper.readMoney(np['output_vat']);
    final inputVat = MoneyHelper.readMoney(np['input_vat']);
    final netVat = MoneyHelper.readMoney(np['net_vat']);
    final payable = np['payable'] as bool? ?? false;
    final refundable = np['refundable'] as bool? ?? false;

    return Card(
      color: payable
          ? AppColors.error.withValues(alpha: 0.08)
          : (refundable ? AppColors.success.withValues(alpha: 0.08) : null),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  payable
                      ? Icons.arrow_upward
                      : (refundable ? Icons.arrow_downward : Icons.check_circle),
                  color: payable
                      ? AppColors.error
                      : (refundable ? AppColors.success : AppColors.textHint),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    payable
                        ? 'صافي الضريبة المستحقة للدفع ($currency)'
                        : (refundable
                            ? 'صافي الضريبة المستحقة للاسترداد ($currency)'
                            : 'صافي الضريبة صفر ($currency)'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildNetRow('ضريبة المخرجات (Output VAT)',
                CurrencyFormatter.format(outputVat, symbol: symbol), theme),
            _buildNetRow('ضريبة المدخلات (Input VAT)',
                CurrencyFormatter.format(inputVat, symbol: symbol), theme),
            const Divider(height: 24),
            _buildNetRow(
              'الصافي',
              CurrencyFormatter.formatSigned(netVat, symbol: symbol),
              theme,
              isBold: true,
              color: payable
                  ? AppColors.error
                  : (refundable ? AppColors.success : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetRow(String label, String value, ThemeData theme,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: isBold ? FontWeight.bold : null)),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.bold : null,
                color: color,
              )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Details section (per-invoice table)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDetailsSection(ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('تفاصيل الفواتير الخاضعة للضريبة',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                // Direction filter chips
                _buildDirectionChips(theme),
              ],
            ),
            const SizedBox(height: 12),
            if (_detailRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('لا توجد فواتير مطابقة')),
              )
            else
              // Detail rows
              Column(
                children: [
                  _buildDetailHeader(theme),
                  const Divider(height: 16),
                  for (final row in _detailRows) _buildDetailRow(row, theme),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionChips(ThemeData theme) {
    return Wrap(
      spacing: 6,
      children: [
        _chip('الكل', null, theme),
        _chip('المخرجات', 'output', theme),
        _chip('المدخلات', 'input', theme),
      ],
    );
  }

  Widget _chip(String label, String? value, ThemeData theme) {
    final isSelected = _detailDirection == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _detailDirection = value);
        _loadData();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDetailHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('الفاتورة', style: theme.textTheme.labelMedium)),
          Expanded(flex: 3, child: Text('الكيان', style: theme.textTheme.labelMedium)),
          Expanded(flex: 2, child: Text('التاريخ', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
          Expanded(flex: 3, child: Text('أساس الضريبة', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
          Expanded(flex: 3, child: Text('الضريبة', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(Map<String, dynamic> row, ThemeData theme) {
    final id = row['id'] as String? ?? '—';
    final type = row['type'] as String? ?? '';
    final isReturn = (row['is_return'] as num?)?.toInt() == 1;
    final entityName = row['entity_name'] as String? ?? '—';
    final createdAt = row['created_at'] as String? ?? '';
    final currency = row['currency'] as String? ?? _selectedCurrency;
    final symbol = CurrencyConstants.currencySymbol(currency);
    final taxableAmount =
        MoneyHelper.readCalculatedMoney(row['taxable_amount']);
    final taxAmount = MoneyHelper.readCalculatedMoney(row['tax_amount']);

    final typeLabel = _invoiceTypeLabel(type, isReturn);
    final typeColor = _invoiceTypeColor(type, isReturn);

    String dateDisplay;
    try {
      dateDisplay = createdAt.length >= 10
          ? DateFormatter.formatDate(DateTime.parse(createdAt.substring(0, 10)))
          : '—';
    } catch (_) {
      dateDisplay = '—';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: typeColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(entityName,
                style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(dateDisplay,
                style: theme.textTheme.bodySmall, textAlign: TextAlign.end),
          ),
          Expanded(
            flex: 3,
            child: Text(
              CurrencyFormatter.format(taxableAmount, symbol: symbol),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              CurrencyFormatter.formatSigned(taxAmount, symbol: symbol),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: taxAmount < 0 ? AppColors.error : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _invoiceTypeLabel(String type, bool isReturn) {
    switch (type) {
      case 'sale':
        return isReturn ? 'مرتجع بيع' : 'بيع';
      case 'pos':
        return isReturn ? 'مرتجع POS' : 'POS';
      case 'purchase':
        return isReturn ? 'مرتجع شراء' : 'شراء';
      default:
        return type;
    }
  }

  Color _invoiceTypeColor(String type, bool isReturn) {
    if (isReturn) return AppColors.error;
    switch (type) {
      case 'sale':
      case 'pos':
        return AppColors.success;
      case 'purchase':
        return AppColors.info;
      default:
        return AppColors.textHint;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Excel export
  // ═══════════════════════════════════════════════════════════════

  Future<void> _exportToExcel() async {
    if (_detailRows.isEmpty) return;

    final rows = _detailRows.map((row) {
      final currency = row['currency'] as String? ?? _selectedCurrency;
      final symbol = CurrencyConstants.currencySymbol(currency);
      return {
        'الفاتورة': row['id'] as String? ?? '',
        'النوع': _invoiceTypeLabel(
            row['type'] as String? ?? '',
            (row['is_return'] as num?)?.toInt() == 1),
        'الكيان': row['entity_name'] as String? ?? '',
        'العملة': currency,
        'التاريخ': (row['created_at'] as String? ?? '').length >= 10
            ? (row['created_at'] as String).substring(0, 10)
            : '',
        'أساس الضريبة': CurrencyFormatter.formatValue(
            MoneyHelper.readCalculatedMoney(row['taxable_amount'])),
        'الضريبة': CurrencyFormatter.formatValue(
            MoneyHelper.readCalculatedMoney(row['tax_amount'])),
        'الرمز': symbol,
      };
    }).toList();

    // ExcelExporter.exportGenericReport expects Map<String, double> for
    // totals. We compute the numeric values (in human-readable currency
    // units, not cents) so Excel can format them as numbers.
    final totals = <String, double>{};
    if (_summaryRows.isNotEmpty) {
      final s = _summaryRows.first;
      totals['إجمالي ضريبة المخرجات'] =
          MoneyHelper.readCalculatedMoney(s['output_vat']) -
          MoneyHelper.readCalculatedMoney(s['output_vat_returns']);
      totals['إجمالي ضريبة المدخلات'] =
          MoneyHelper.readCalculatedMoney(s['input_vat']) -
          MoneyHelper.readCalculatedMoney(s['input_vat_returns']);
    } else {
      totals['إجمالي ضريبة المخرجات'] = 0.0;
      totals['إجمالي ضريبة المدخلات'] = 0.0;
    }
    if (_netPayable != null) {
      totals['الصافي المستحق'] =
          MoneyHelper.readMoney(_netPayable!['net_vat']);
    } else {
      totals['الصافي المستحق'] = 0.0;
    }

    try {
      final path = await ExcelExporter.exportGenericReport(
        reportName: 'إقرار ضريبة القيمة المضافة',
        rows: rows,
        totals: totals,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير التقرير: $path'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التصدير: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
