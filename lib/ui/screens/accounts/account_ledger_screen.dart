import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/account_model.dart';
import 'package:intl/intl.dart' as intl;

class AccountLedgerScreen extends StatefulWidget {
  final Account account;

  const AccountLedgerScreen({super.key, required this.account});

  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  DateTime? _fromDate;
  DateTime? _toDate;

  final _typeColors = {
    AccountType.ASSET: AppColors.primary,
    AccountType.LIABILITY: AppColors.warning,
    AccountType.EQUITY: AppColors.accentPurple,
    AccountType.COST: AppColors.info,
    AccountType.REVENUE: AppColors.success,
    AccountType.EXPENSE: AppColors.error,
  };

  final _typeIcons = {
    AccountType.ASSET: Icons.business,
    AccountType.LIABILITY: Icons.savings,
    AccountType.EQUITY: Icons.account_balance,
    AccountType.COST: Icons.south_west,
    AccountType.REVENUE: Icons.arrow_outward,
    AccountType.EXPENSE: Icons.arrow_downward,
  };

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper();
    if (widget.account.id != null) {
      final maps = await db.getTransactionsByAccount(widget.account.id!);
      setState(() {
        _transactions = maps;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_fromDate == null && _toDate == null) return _transactions;
    return _transactions.where((tx) {
      final dateStr = tx['date'] as String? ?? tx['created_at'] as String? ?? '';
      DateTime? txDate;
      try { txDate = DateTime.parse(dateStr); } catch (_) { return true; }
      if (_fromDate != null && txDate.isBefore(_fromDate!)) return false;
      if (_toDate != null && txDate.isAfter(_toDate!)) return false;
      return true;
    }).toList();
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'من تاريخ',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked != null) setState(() => _fromDate = picked);
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'إلى تاريخ',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked != null) setState(() => _toDate = picked);
  }

  void _clearDateFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _typeColors[widget.account.accountType] ?? AppColors.primary;
    final icon = _typeIcons[widget.account.accountType] ?? Icons.menu_book;

    final filteredTx = _filteredTransactions;

    // Compute summary totals (always from ALL transactions for correct running balance)
    double totalDebit = 0;
    double totalCredit = 0;
    for (final tx in filteredTx) {
      totalDebit += MoneyHelper.readMoney(tx['debit']);
      totalCredit += MoneyHelper.readMoney(tx['credit']);
    }
    final netBalance = totalDebit - totalCredit;

    // Compute running balances
    // Start from opening balance so final running balance matches account's current balance
    // When date filter is active, compute opening balance for the filtered set
    double openingBalance;
    if (_fromDate == null && _toDate == null) {
      openingBalance = widget.account.balance - netBalance;
    } else {
      // Compute opening balance from all transactions before the filter range
      double preFilterDebit = 0;
      double preFilterCredit = 0;
      for (final tx in _transactions) {
        final dateStr = tx['date'] as String? ?? tx['created_at'] as String? ?? '';
        DateTime? txDate;
        try { txDate = DateTime.parse(dateStr); } catch (_) { txDate = null; }
        if (txDate != null && _fromDate != null && txDate.isBefore(_fromDate!)) {
          preFilterDebit += MoneyHelper.readMoney(tx['debit']);
          preFilterCredit += MoneyHelper.readMoney(tx['credit']);
        }
      }
      openingBalance = (widget.account.balance - (_transactions.fold<double>(0, (sum, tx) =>
        sum + (MoneyHelper.readMoney(tx['debit'])) - (MoneyHelper.readMoney(tx['credit'])))))
        + preFilterDebit - preFilterCredit;
    }
    final runningBalances = <double>[];
    double running = openingBalance;
    // Transactions are ordered date DESC, so reverse for running balance
    final reversed = filteredTx.reversed.toList();
    for (final tx in reversed) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
      running += debit - credit;
      runningBalances.add(running);
    }
    // Map back: index in original list -> running balance
    // original index i corresponds to reversed index (len - 1 - i)
    final runningMap = <int, double>{};
    for (int i = 0; i < filteredTx.length; i++) {
      final revIdx = filteredTx.length - 1 - i;
      runningMap[i] = runningBalances[revIdx];
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('دفتر حساب: ${widget.account.nameAr}'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadTransactions,
                child: CustomScrollView(
                  slivers: [
                    // ── Account Header ────────────────────────────
                    SliverToBoxAdapter(
                      child: _AccountHeader(
                        account: widget.account,
                        color: color,
                        icon: icon,
                        isDark: isDark,
                      ),
                    ),

                    // ── Summary Row ───────────────────────────────
                    SliverToBoxAdapter(
                      child: _SummaryRow(
                        totalDebit: totalDebit,
                        totalCredit: totalCredit,
                        netBalance: netBalance,
                        isDark: isDark,
                      ),
                    ),

                    // ── Date Filter Bar ──────────────────────────────
                    SliverToBoxAdapter(
                      child: _DateFilterBar(
                        fromDate: _fromDate,
                        toDate: _toDate,
                        onFromTap: _pickFromDate,
                        onToTap: _pickToDate,
                        onClear: _clearDateFilter,
                        isDark: isDark,
                      ),
                    ),

                    // ── Transactions List or Empty State ───────────
                    if (filteredTx.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(color: color),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = filteredTx[index];
                            final running = runningMap[index] ?? 0.0;
                            return _TransactionCard(
                              transaction: tx,
                              runningBalance: running,
                              isDark: isDark,
                              isLast: index == filteredTx.length - 1,
                            );
                          },
                          childCount: filteredTx.length,
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Account Header Widget
// ═══════════════════════════════════════════════════════════════════════

class _AccountHeader extends StatelessWidget {
  final Account account;
  final Color color;
  final IconData icon;
  final bool isDark;

  const _AccountHeader({
    required this.account,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
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
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.nameAr,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            account.accountCode,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            Account.accountTypeAr(account.accountType),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: color,
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
              Text('الرصيد الحالي',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  )),
              Text(
                CurrencyFormatter.format(account.balance),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: account.balance >= 0 ? color : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Summary Row Widget
// ═══════════════════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  final double totalDebit;
  final double totalCredit;
  final double netBalance;
  final bool isDark;

  const _SummaryRow({
    required this.totalDebit,
    required this.totalCredit,
    required this.netBalance,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Total Debit
          Expanded(
            child: _SummaryItem(
              label: 'مدين',
              value: CurrencyFormatter.format(totalDebit),
              color: AppColors.error,
              icon: Icons.north_west,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
          // Total Credit
          Expanded(
            child: _SummaryItem(
              label: 'دائن',
              value: CurrencyFormatter.format(totalCredit),
              color: AppColors.success,
              icon: Icons.south_east,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: isDark ? AppColors.darkDivider : AppColors.divider,
          ),
          // Net Balance
          Expanded(
            child: _SummaryItem(
              label: 'الصافي',
              value: CurrencyFormatter.format(netBalance),
              color: netBalance >= 0 ? AppColors.primary : AppColors.error,
              icon: Icons.balance,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
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
}

// ═══════════════════════════════════════════════════════════════════════
//  Date Filter Bar Widget
// ═══════════════════════════════════════════════════════════════════════

class _DateFilterBar extends StatelessWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  final VoidCallback onClear;
  final bool isDark;

  const _DateFilterBar({
    required this.fromDate,
    required this.toDate,
    required this.onFromTap,
    required this.onToTap,
    required this.onClear,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilter = fromDate != null || toDate != null;
    final dateFormat = intl.DateFormat('yyyy/MM/dd');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: hasFilter
            ? AppColors.primary.withOpacity(0.06)
            : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
        borderRadius: BorderRadius.circular(12),
        border: hasFilter
            ? Border.all(color: AppColors.primary.withOpacity(0.3))
            : null,
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 18, color: hasFilter ? AppColors.primary : AppColors.textHint),
          const SizedBox(width: 8),
          // From date button
          Expanded(
            child: InkWell(
              onTap: onFromTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: fromDate != null
                      ? AppColors.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 14,
                      color: fromDate != null ? AppColors.primary : AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      fromDate != null ? dateFormat.format(fromDate!) : 'من تاريخ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: fromDate != null ? AppColors.primary : AppColors.textHint,
                        fontWeight: fromDate != null ? FontWeight.w700 : FontWeight.w500,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('—', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
          const SizedBox(width: 4),
          // To date button
          Expanded(
            child: InkWell(
              onTap: onToTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: toDate != null
                      ? AppColors.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 14,
                      color: toDate != null ? AppColors.primary : AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      toDate != null ? dateFormat.format(toDate!) : 'إلى تاريخ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: toDate != null ? AppColors.primary : AppColors.textHint,
                        fontWeight: toDate != null ? FontWeight.w700 : FontWeight.w500,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Clear button
          if (hasFilter) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.close, size: 16, color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Transaction Card Widget
// ═══════════════════════════════════════════════════════════════════════

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final double runningBalance;
  final bool isDark;
  final bool isLast;

  const _TransactionCard({
    required this.transaction,
    required this.runningBalance,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debit = MoneyHelper.readMoney(transaction['debit']);
    final credit = MoneyHelper.readMoney(transaction['credit']);
    final description = (transaction['description'] as String?) ?? 'بدون وصف';
    final dateStr = transaction['date'] as String? ?? '';
    final createdAt = transaction['created_at'] as String? ?? '';

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
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Date & Description
          Row(
            children: [
              // Date badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    if (formattedTime.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryLight,
                          fontFamily: 'Cairo',
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
                  color: (runningBalance >= 0 ? AppColors.primary : AppColors.error).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  CurrencyFormatter.format(runningBalance),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: runningBalance >= 0 ? AppColors.primary : AppColors.error,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Description
          Row(
            children: [
              const Icon(Icons.article, size: 16, color: AppColors.textSecondary),
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

          // Row 3: Debit & Credit amounts
          Row(
            children: [
              // Debit
              Expanded(
                child: debit > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'مدين',
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
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (debit > 0 && credit > 0) const SizedBox(width: 8),
              // Credit
              Expanded(
                child: credit > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'دائن',
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
                                fontFamily: 'Cairo',
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
}

// ═══════════════════════════════════════════════════════════════════════
//  Empty State Widget
// ═══════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final Color color;

  const _EmptyState({required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.book,
                size: 36,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد حركات',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم تسجيل أي قيود محاسبية على هذا الحساب بعد',
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
}
