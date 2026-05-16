import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import 'add_expense_screen.dart';

class ExpenseAccountDetailScreen extends StatefulWidget {
  final Map<String, dynamic> account;

  const ExpenseAccountDetailScreen({super.key, required this.account});

  @override
  State<ExpenseAccountDetailScreen> createState() => _ExpenseAccountDetailScreenState();
}

class _ExpenseAccountDetailScreenState extends State<ExpenseAccountDetailScreen> {
  List<Map<String, dynamic>> _transactions = [];
  // List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  double _currentBalance = 0.0;
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int get _accountId => widget.account['id'] as int;
  String get _accountName => widget.account['name_ar'] as String? ?? '';
  String get _currency => widget.account['currency'] as String? ?? 'YER';

  String get _currencySymbol {
    switch (_currency) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      default: return 'ر.ي';
    }
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAccountTransactions(_accountId),
      db.getExpensesByAccountId(_accountId),
    ]);

    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final tx in results[0]) {
      totalDebit += (tx['debit'] as num?)?.toDouble() ?? 0.0;
      totalCredit += (tx['credit'] as num?)?.toDouble() ?? 0.0;
    }

    setState(() {
      _transactions = results[0];
      // _expenses = results[1];
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _currentBalance = totalDebit - totalCredit;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final debtCeiling = (widget.account['debt_ceiling'] as num?)?.toDouble() ?? 0.0;
    final balanceType = widget.account['balance_type'] as String? ?? 'credit';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_accountName),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // Account header
                    SliverToBoxAdapter(
                      child: _buildAccountHeader(theme, isDark, debtCeiling, balanceType),
                    ),

                    // Summary row
                    SliverToBoxAdapter(
                      child: _buildSummaryRow(theme, isDark),
                    ),

                    // Section title
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(PhosphorIconsRegular.listBullets, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'العمليات المالية',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Transactions list
                    if (_transactions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(theme),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = _transactions[index];
                            // Calculate running balance up to this point
                            double running = 0.0;
                            for (int i = 0; i <= index; i++) {
                              final d = (_transactions[i]['debit'] as num?)?.toDouble() ?? 0.0;
                              final c = (_transactions[i]['credit'] as num?)?.toDouble() ?? 0.0;
                              running += d - c;
                            }
                            return _buildTransactionCard(tx, running, theme, isDark);
                          },
                          childCount: _transactions.length,
                        ),
                      ),

                    SliverToBoxAdapter(child: SizedBox(height: 100 + bottomPadding)),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _navigateToAddExpense,
          backgroundColor: AppColors.primary,
          tooltip: 'إضافة مصروف جديد',
          child: const Icon(PhosphorIconsFill.plus, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAccountHeader(ThemeData theme, bool isDark, double debtCeiling, String balanceType) {
    final isCredit = _currentBalance >= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(PhosphorIconsFill.wallet, color: AppColors.error, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _accountName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.account['account_code'] as String? ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _currencySymbol,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الرصيد الحالي',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isCredit ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCredit ? 'له' : 'عليه',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isCredit ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.format(_currentBalance.abs()),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isCredit ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (debtCeiling > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(PhosphorIconsRegular.shieldWarning, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  'سقف المديونية: ${CurrencyFormatter.format(debtCeiling)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Total Debit (صرف)
          Expanded(
            child: _buildSummaryItem(
              label: 'صرف (عليه)',
              value: CurrencyFormatter.format(_totalDebit),
              color: AppColors.error,
              icon: PhosphorIconsRegular.arrowUpLeft,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
          // Total Credit (قبض)
          Expanded(
            child: _buildSummaryItem(
              label: 'قبض (له)',
              value: CurrencyFormatter.format(_totalCredit),
              color: AppColors.success,
              icon: PhosphorIconsRegular.arrowDownRight,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
          // Net Balance
          Expanded(
            child: _buildSummaryItem(
              label: 'الصافي',
              value: CurrencyFormatter.format(_currentBalance),
              color: _currentBalance >= 0 ? AppColors.primary : AppColors.error,
              icon: PhosphorIconsRegular.scales,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, double runningBalance, ThemeData theme, bool isDark) {
    final debit = (tx['debit'] as num?)?.toDouble() ?? 0.0;
    final credit = (tx['credit'] as num?)?.toDouble() ?? 0.0;
    final description = (tx['description'] as String?) ?? 'بدون وصف';
    final dateStr = tx['date'] as String? ?? '';
    final createdAt = tx['created_at'] as String? ?? '';

    DateTime? txDate;
    try {
      txDate = DateTime.parse(dateStr.isNotEmpty ? dateStr : createdAt);
    } catch (_) {
      try {
        txDate = DateTime.parse(createdAt);
      } catch (_) {
        txDate = null;
      }
    }

    final formattedDate = txDate != null ? DateFormatter.formatDate(txDate) : '';
    final formattedTime = txDate != null ? DateFormatter.formatTime(txDate) : '';
    // final isDebit = debit > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Date & Running balance
          Row(
            children: [
              // Date badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsRegular.calendarBlank, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (formattedTime.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              // Running balance
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (runningBalance >= 0 ? AppColors.primary : AppColors.error).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  CurrencyFormatter.format(runningBalance),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: runningBalance >= 0 ? AppColors.primary : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Description
          Row(
            children: [
              Icon(PhosphorIconsRegular.article, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: Debit/Credit amounts
          Row(
            children: [
              // Debit (صرف)
              Expanded(
                child: debit > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'صرف',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              CurrencyFormatter.format(debit),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (debit > 0 && credit > 0) const SizedBox(width: 8),
              // Credit (قبض)
              Expanded(
                child: credit > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'قبض',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              CurrencyFormatter.format(credit),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                PhosphorIconsRegular.notebook,
                size: 36,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد عمليات',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم تسجيل أي عمليات مالية على هذا الحساب بعد',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToAddExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(expenseAccountId: _accountId),
      ),
    );
    if (result == true) _loadData();
  }
}
