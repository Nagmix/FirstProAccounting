import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/report_service.dart';

// ═══════════════════════════════════════════════════════════════════
//  Trial Balance Screen (ميزان المراجعة)
//  Shows all accounts with debit/credit balances and verifies
//  that total debits equal total credits.
// ═══════════════════════════════════════════════════════════════════

class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  bool _isLoading = false;
  String _selectedCurrency = 'ر.ي';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  List<Map<String, dynamic>> _accounts = [];
  double _totalDebit = 0;
  double _totalCredit = 0;

  static const _currencyOptions = ['ر.ي', 'ر.س', r'$'];

  String? _currencyCode() {
    switch (_selectedCurrency) {
      case 'ر.ي':
        return 'YER';
      case 'ر.س':
        return 'SAR';
      case r'$':
        return 'USD';
      default:
        return null;
    }
  }

  String _accountTypeAr(String type) {
    switch (type) {
      case 'ASSET':
        return 'أصول';
      case 'LIABILITY':
        return 'خصوم';
      case 'EQUITY':
        return 'حقوق الملكية';
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final cc = _currencyCode();
      final results = await locator<ReportService>().getTrialBalanceData(
        currency: cc,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

      double totalDebit = 0;
      double totalCredit = 0;
      final accounts = <Map<String, dynamic>>[];

      for (final row in results) {
        // Use readCalculatedMoney for SQL SUM results which may be REAL
        final totalDebitRaw =
            MoneyHelper.readCalculatedMoney(row['total_debit']);
        final totalCreditRaw =
            MoneyHelper.readCalculatedMoney(row['total_credit']);
        final netBalance = totalDebitRaw - totalCreditRaw;

        if (MoneyHelper.isZero(netBalance)) continue;

        final balanceType = row['balance_type'] as String? ?? 'credit';
        // Determine which column the net balance goes to
        // debit-type accounts (ASSET, COST): positive balance → debit column
        // credit-type accounts (LIABILITY, REVENUE, EXPENSE): positive balance → credit column
        final isDebitBalance =
            balanceType == 'debit' ? netBalance > 0 : netBalance < 0;
        final debitAmount = isDebitBalance ? netBalance.abs() : 0.0;
        final creditAmount = isDebitBalance ? 0.0 : netBalance.abs();

        totalDebit += debitAmount;
        totalCredit += creditAmount;

        accounts.add({
          'id': row['id'],
          'account_code': row['account_code'] as String? ?? '',
          'name_ar': row['name_ar'] as String? ?? '',
          'account_type': row['account_type'] as String? ?? '',
          'balance_type': balanceType,
          'debit': debitAmount,
          'credit': creditAmount,
        });
      }

      if (mounted) {
        setState(() {
          _accounts = accounts;
          _totalDebit = totalDebit;
          _totalCredit = totalCredit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dateFrom = picked);
      _loadData();
    }
  }

  Future<void> _pickDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dateTo = picked);
      _loadData();
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '---';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final difference = (_totalDebit - _totalCredit).abs();
    final isBalanced = MoneyHelper.isZero(difference);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ميزان المراجعة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadData,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewPadding.bottom + 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Filters Card ──
                    _buildFiltersCard(theme, isDark),
                    const SizedBox(height: 16),

                    // ── Summary Card ──
                    _buildSummaryCard(theme, isDark, isBalanced, difference),
                    const SizedBox(height: 16),

                    // ── Accounts Table ──
                    _buildAccountsTable(theme, isDark),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFiltersCard(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('خيارات التصقية',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          // Currency selector
          Row(
            children: [
              Text('العملة:',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrency,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                    items: _currencyOptions
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child:
                                  Text(c, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCurrency = val);
                        _loadData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Date range
          Row(
            children: [
              Expanded(
                child: _buildDateChip(
                  theme,
                  Icons.calendar_today,
                  'من: ${_fmtDate(_dateFrom)}',
                  _pickDateFrom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateChip(
                  theme,
                  Icons.calendar_today,
                  'إلى: ${_fmtDate(_dateTo)}',
                  _pickDateTo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(
      ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      ThemeData theme, bool isDark, bool isBalanced, double difference) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isBalanced
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.error.withValues(alpha: 0.08),
            isBalanced
                ? AppColors.success.withValues(alpha: 0.03)
                : AppColors.error.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (isBalanced ? AppColors.success : AppColors.error)
                .withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.balance, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('ملخص ميزان المراجعة',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isBalanced ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isBalanced ? Icons.check_circle : Icons.warning,
                        size: 14,
                        color:
                            isBalanced ? AppColors.success : AppColors.error),
                    const SizedBox(width: 4),
                    Text(
                      isBalanced ? 'متوازن' : 'غير متوازن',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isBalanced ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Total Debit
              Expanded(
                child: _buildSummaryItem(theme, 'إجمالي المدين', _totalDebit,
                    AppColors.info, Icons.add_circle_outline),
              ),
              const SizedBox(width: 12),
              // Total Credit
              Expanded(
                child: _buildSummaryItem(theme, 'إجمالي الدائن', _totalCredit,
                    AppColors.success, Icons.remove_circle_outline),
              ),
              const SizedBox(width: 12),
              // Difference
              Expanded(
                child: _buildSummaryItem(
                  theme,
                  'الفرق',
                  difference,
                  isBalanced ? AppColors.success : AppColors.error,
                  isBalanced ? Icons.verified : Icons.error_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'عدد الحسابات: ${_accounts.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
      ThemeData theme, String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.format(value, symbol: _selectedCurrency),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsTable(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('تفاصيل الحسابات',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          if (_accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.balance,
                        size: 48,
                        color: AppColors.textHint.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text('لا توجد حسابات ذات أرصدة',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textHint)),
                  ],
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    AppColors.primary.withValues(alpha: 0.08)),
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: [
                  DataColumn(
                      label: Text('كود الحساب',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary))),
                  DataColumn(
                      label: Text('اسم الحساب',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary))),
                  DataColumn(
                      label: Text('نوع الحساب',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary))),
                  DataColumn(
                      label: Text('مدين',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.info))),
                  DataColumn(
                      label: Text('دائن',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.success))),
                ],
                rows: [
                  ..._accounts.map((account) => DataRow(cells: [
                        DataCell(Text(account['account_code'] as String? ?? '',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(account['name_ar'] as String? ?? '',
                            style: theme.textTheme.bodySmall)),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accountTypeColor(
                                    account['account_type'] as String? ?? '')
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _accountTypeAr(
                                account['account_type'] as String? ?? ''),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _accountTypeColor(
                                  account['account_type'] as String? ?? ''),
                            ),
                          ),
                        )),
                        DataCell(Text(
                          ((account['debit'] as num?)?.toDouble() ?? 0.0) > 0
                              ? CurrencyFormatter.formatValue(
                                  (account['debit'] as num?)?.toDouble() ?? 0.0)
                              : '-',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ((account['debit'] as num?)?.toDouble() ??
                                        0.0) >
                                    0
                                ? AppColors.info
                                : AppColors.textHint,
                          ),
                          textAlign: TextAlign.left,
                        )),
                        DataCell(Text(
                          ((account['credit'] as num?)?.toDouble() ?? 0.0) > 0
                              ? CurrencyFormatter.formatValue(
                                  (account['credit'] as num?)?.toDouble() ??
                                      0.0)
                              : '-',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ((account['credit'] as num?)?.toDouble() ??
                                        0.0) >
                                    0
                                ? AppColors.success
                                : AppColors.textHint,
                          ),
                          textAlign: TextAlign.left,
                        )),
                      ])),
                  // Totals row
                  DataRow(
                    color: WidgetStateProperty.all(
                        AppColors.primary.withValues(alpha: 0.05)),
                    cells: [
                      DataCell(Text('الإجمالي',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary))),
                      const DataCell(SizedBox.shrink()),
                      const DataCell(SizedBox.shrink()),
                      DataCell(Text(
                        CurrencyFormatter.formatValue(_totalDebit),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900, color: AppColors.info),
                        textAlign: TextAlign.left,
                      )),
                      DataCell(Text(
                        CurrencyFormatter.formatValue(_totalCredit),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.success),
                        textAlign: TextAlign.left,
                      )),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _accountTypeColor(String type) {
    switch (type) {
      case 'ASSET':
        return AppColors.info;
      case 'LIABILITY':
        return AppColors.error;
      case 'EQUITY':
        return AppColors.accentPurple;
      case 'COST':
        return AppColors.warning;
      case 'REVENUE':
        return AppColors.success;
      case 'EXPENSE':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }
}
