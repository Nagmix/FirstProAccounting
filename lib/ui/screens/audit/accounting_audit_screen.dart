import 'package:flutter/material.dart';
import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/audit_service.dart';

/// Accounting audit screen that verifies all operations are linked to
/// the Chart of Accounts by currency, checks trial balance, and
/// identifies any orphaned or unbalanced transactions.
class AccountingAuditScreen extends StatefulWidget {
  const AccountingAuditScreen({super.key});

  @override
  State<AccountingAuditScreen> createState() => _AccountingAuditScreenState();
}

class _AccountingAuditScreenState extends State<AccountingAuditScreen> {
  bool _isLoading = true;
  // ignore: unused_field
  bool _hasRunAudit = false;

  // Audit results
  List<Map<String, dynamic>> _trialBalanceByCurrency = [];
  List<Map<String, dynamic>> _orphanedInvoices = [];
  List<Map<String, dynamic>> _orphanedExpenses = [];
  List<Map<String, dynamic>> _unbalancedJournals = [];
  List<Map<String, dynamic>> _accountSummaryByCurrency = [];
  int _totalTransactions = 0;
  int _totalAccounts = 0;
  int _totalInvoices = 0;
  int _totalExpenses = 0;

  // Overall health
  bool _isBalanced = true;
  int _issueCount = 0;

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  Future<void> _runAudit() async {
    setState(() => _isLoading = true);

    try {
      final auditService = locator<AuditService>();

      // 1. Trial Balance by Currency
      final trialBalance = await auditService.getTrialBalanceByCurrency();

      // 2. Account Summary by Currency and Type
      final accountSummary =
          await auditService.getAccountSummaryByCurrencyAndType();

      // 3. Orphaned Invoices (invoices without journal entries)
      final orphanedInvoices = await auditService.getOrphanedInvoices();

      // 4. Orphaned Expenses (expenses without journal entries to accounts)
      final orphanedExpenses = await auditService.getOrphanedExpenses();

      // 5. Unbalanced Journal Entries (debit != credit)
      final unbalancedJournals = await auditService.getUnbalancedJournals();

      // 6. Counts
      final txCount = await auditService.getTransactionCount();
      final accCount = await auditService.getActiveAccountCount();
      final invCount = await auditService.getInvoiceCount();
      final expCount = await auditService.getExpenseCount();

      // Check overall balance
      bool isBalanced = true;
      for (final tb in trialBalance) {
        final diff = MoneyHelper.readMoney(tb['balance_diff']);
        if (diff.abs() > 0.01) {
          isBalanced = false;
          break;
        }
      }

      int issues = orphanedInvoices.length +
          orphanedExpenses.length +
          unbalancedJournals.length;

      if (mounted) {
        setState(() {
          _trialBalanceByCurrency = trialBalance;
          _accountSummaryByCurrency = accountSummary;
          _orphanedInvoices = orphanedInvoices;
          _orphanedExpenses = orphanedExpenses;
          _unbalancedJournals = unbalancedJournals;
          _totalTransactions = txCount;
          _totalAccounts = accCount;
          _totalInvoices = invCount;
          _totalExpenses = expCount;
          _isBalanced = isBalanced;
          _issueCount = issues;
          _isLoading = false;
          _hasRunAudit = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        context.showErrorSnackBar('حدث خطأ أثناء التدقيق');
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
          title: const Text('التدقيق المحاسبي'),
          actions: [
            IconButton(
              onPressed: _runAudit,
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة التدقيق',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _runAudit,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    _buildHealthCard(theme, isDark),
                    const SizedBox(height: 16),
                    _buildOverviewStats(theme, isDark),
                    const SizedBox(height: 16),
                    _buildTrialBalanceSection(theme, isDark),
                    const SizedBox(height: 16),
                    _buildAccountSummarySection(theme, isDark),
                    if (_orphanedInvoices.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildOrphanedInvoicesSection(theme, isDark),
                    ],
                    if (_orphanedExpenses.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildOrphanedExpensesSection(theme, isDark),
                    ],
                    if (_unbalancedJournals.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildUnbalancedJournalsSection(theme, isDark),
                    ],
                    if (_issueCount == 0) ...[
                      const SizedBox(height: 32),
                      _buildAllGoodState(theme),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHealthCard(ThemeData theme, bool isDark) {
    final color = _isBalanced ? AppColors.success : AppColors.error;
    final icon = _isBalanced ? Icons.verified_user : Icons.shield;
    final title =
        _isBalanced ? 'النظام المحاسبي متوازن' : 'يوجد خلل في التوازن المحاسبي';
    final subtitle = _isBalanced
        ? 'جميع القيود مجلوبة ومتوازنة حسب العملات'
        : 'يوجد فرق بين المدين والدائن في بعض العملات';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isBalanced
              ? [
                  AppColors.success.withValues(alpha: 0.1),
                  AppColors.successLight.withValues(alpha: 0.05)
                ]
              : [
                  AppColors.error.withValues(alpha: 0.1),
                  AppColors.errorLight.withValues(alpha: 0.05)
                ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (_issueCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'عدد المشاكل: $_issueCount',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewStats(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('نظرة عامة',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildStatChip(theme, isDark, Icons.swap_horiz, 'القيود',
                  '$_totalTransactions', AppColors.primary),
              const SizedBox(width: 8),
              _buildStatChip(theme, isDark, Icons.pie_chart, 'الحسابات',
                  '$_totalAccounts', AppColors.accentBlue),
              const SizedBox(width: 8),
              _buildStatChip(theme, isDark, Icons.receipt, 'الفواتير',
                  '$_totalInvoices', AppColors.success),
              const SizedBox(width: 8),
              _buildStatChip(theme, isDark, Icons.attach_money, 'المصروفات',
                  '$_totalExpenses', AppColors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(ThemeData theme, bool isDark, IconData icon,
      String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrialBalanceSection(ThemeData theme, bool isDark) {
    final currencyNames = {
      'YER': 'ريال يمني',
      'SAR': 'ريال سعودي',
      'USD': 'دولار أمريكي'
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('ميزان المراجعة حسب العملة',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('العملة',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary))),
                Expanded(
                    flex: 2,
                    child: Text('المدين',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.error),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('الدائن',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.success),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('الفرق',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning),
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ..._trialBalanceByCurrency.map((tb) {
            final currency = tb['currency'] as String? ?? 'YER';
            final debit = MoneyHelper.readMoney(tb['total_debit']);
            final credit = MoneyHelper.readMoney(tb['total_credit']);
            final diff = MoneyHelper.readMoney(tb['balance_diff']);
            final isOk = diff.abs() <= 0.01;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.divider.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Icon(isOk ? Icons.check_circle : Icons.error_outline,
                            size: 14,
                            color: isOk ? AppColors.success : AppColors.error),
                        const SizedBox(width: 4),
                        Text(currencyNames[currency] ?? currency,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Expanded(
                      flex: 2,
                      child: Text(CurrencyFormatter.formatCompact(debit),
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.error),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text(CurrencyFormatter.formatCompact(credit),
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.success),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text(CurrencyFormatter.formatCompact(diff.abs()),
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color:
                                  isOk ? AppColors.success : AppColors.error),
                          textAlign: TextAlign.center)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAccountSummarySection(ThemeData theme, bool isDark) {
    final typeNames = {
      'ASSET': 'الأصول',
      'LIABILITY': 'الخصوم',
      'EQUITY': 'حقوق الملكية',
      'COST': 'التكاليف',
      'REVENUE': 'الإيرادات',
      'EXPENSE': 'المصاريف',
    };
    final typeColors = {
      'ASSET': AppColors.accentBlue,
      'LIABILITY': AppColors.accentPink,
      'EQUITY': AppColors.accentPurple,
      'COST': AppColors.secondary,
      'REVENUE': AppColors.success,
      'EXPENSE': AppColors.error,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('ملخص الحسابات حسب النوع والعملة',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ..._accountSummaryByCurrency.map((item) {
            final currency = item['currency'] as String? ?? 'YER';
            final type = item['account_type'] as String? ?? '';
            final count = (item['count'] as int?) ?? 0;
            final balance = MoneyHelper.readMoney(item['total_balance']);
            final color = typeColors[type] ?? AppColors.primary;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${typeNames[type] ?? type} ($currency)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('$count حساب',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Text(CurrencyFormatter.formatCompact(balance.abs()),
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrphanedInvoicesSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('فواتير بدون قيود محاسبية',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'هذه الفواتير لم يتم تسجيل قيودها في دليل الحسابات:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ..._orphanedInvoices.map((inv) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inv['entity_name'] ?? 'بدون اسم',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            '${inv['type'] == 'sale' ? 'بيع' : 'شراء'} - ${inv['currency']}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                      CurrencyFormatter.format(
                          MoneyHelper.readMoney(inv['total'])),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrphanedExpensesSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Text('مصروفات بدون حساب محاسبي',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'هذه المصروفات غير مرتبطة بأي حساب في دليل الحسابات:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ..._orphanedExpenses.map((exp) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.attach_money, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exp['title'] ?? 'بدون عنوان',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            '${exp['operation_type'] ?? 'صرف'} - ${exp['currency']}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                      CurrencyFormatter.format(
                          MoneyHelper.readMoney(exp['amount'])),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUnbalancedJournalsSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Text('قيود غير متوازنة (مدين ≠ دائن)',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: 12),
          ..._unbalancedJournals.map((j) {
            final diff = MoneyHelper.readMoney(j['diff']);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قيد #${j['journal_id']}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('${j['entry_count']} بنود',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('الفرق: ${CurrencyFormatter.format(diff.abs())}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.error)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAllGoodState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_box, size: 48, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            'التدقيق مكتمل - لا توجد مشاكل',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جميع العمليات مرتبطة بدليل الحسابات والميزان متوازن حسب العملات',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
