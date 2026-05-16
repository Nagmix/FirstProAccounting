import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/expense_model.dart';
import 'add_expense_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  double _totalThisMonth = 0.0;
  double _totalToday = 0.0;
  String _mostSpentCategory = '';
  double _mostSpentAmount = 0.0;

  String? _filterCategory;
  String? _filterPaymentMethod;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final now = DateTime.now();

    final results = await Future.wait([
      db.getAllExpenses(),
      db.getTotalExpensesThisMonth(),
      db.getTotalExpensesForDate(now),
    ]);

    // Find most spent category this month
    String topCategory = '';
    double topAmount = 0.0;
    for (final cat in Expense.categoriesAr.keys) {
      final amount = await db.getTotalExpensesByCategory(cat);
      if (amount > topAmount) {
        topAmount = amount;
        topCategory = cat;
      }
    }

    setState(() {
      _expenses = results[0] as List<Map<String, dynamic>>;
      _totalThisMonth = (results[1] as num?)?.toDouble() ?? 0.0;
      _totalToday = (results[2] as num?)?.toDouble() ?? 0.0;
      _mostSpentCategory = topCategory;
      _mostSpentAmount = topAmount;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    var filtered = _expenses;
    if (_filterCategory != null) {
      filtered = filtered.where((e) => e['category'] == _filterCategory).toList();
    }
    if (_filterPaymentMethod != null) {
      filtered = filtered.where((e) => e['payment_method'] == _filterPaymentMethod).toList();
    }
    return filtered;
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'rent': return PhosphorIconsRegular.house;
      case 'salary': return PhosphorIconsRegular.users;
      case 'utility': return PhosphorIconsRegular.lightning;
      case 'transport': return PhosphorIconsRegular.truck;
      case 'office': return PhosphorIconsRegular.desktop;
      case 'maintenance': return PhosphorIconsRegular.wrench;
      case 'marketing': return PhosphorIconsRegular.megaphone;
      case 'insurance': return PhosphorIconsRegular.shieldCheck;
      case 'tax': return PhosphorIconsRegular.bank;
      default: return PhosphorIconsRegular.currencyDollar;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'rent': return AppColors.accentBlue;
      case 'salary': return AppColors.accentGreen;
      case 'utility': return AppColors.warning;
      case 'transport': return AppColors.accentOrange;
      case 'office': return AppColors.info;
      case 'maintenance': return AppColors.accentPink;
      case 'marketing': return AppColors.primary;
      case 'insurance': return AppColors.success;
      case 'tax': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  String _getPaymentMethodAr(String? method) {
    switch (method) {
      case 'cash': return 'نقدي';
      case 'check': return 'شيك';
      case 'transfer': return 'حوالة';
      case 'bank': return 'بنك';
      default: return 'نقدي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المصروفات'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(PhosphorIconsRegular.funnel),
              tooltip: 'تصفية',
              onSelected: (value) {
                if (value == 'clear') {
                  setState(() {
                    _filterCategory = null;
                    _filterPaymentMethod = null;
                  });
                } else if (value.startsWith('cat:')) {
                  setState(() => _filterCategory = value.substring(4));
                } else if (value.startsWith('pay:')) {
                  setState(() => _filterPaymentMethod = value.substring(4));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'clear', child: Text('إلغاء التصفية')),
                const PopupMenuDivider(),
                const PopupMenuItem(enabled: false, child: Text('التصنيف:', style: TextStyle(fontWeight: FontWeight.w700))),
                ...Expense.categoriesAr.entries.map((e) =>
                  PopupMenuItem(value: 'cat:${e.key}', child: Text(e.value)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(enabled: false, child: Text('طريقة الدفع:', style: TextStyle(fontWeight: FontWeight.w700))),
                const PopupMenuItem(value: 'pay:cash', child: Text('نقدي')),
                const PopupMenuItem(value: 'pay:check', child: Text('شيك')),
                const PopupMenuItem(value: 'pay:transfer', child: Text('حوالة')),
                const PopupMenuItem(value: 'pay:bank', child: Text('بنك')),
              ],
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // Summary cards
                    SliverToBoxAdapter(child: _buildSummaryCards(theme, isDark)),

                    // Active filters
                    if (_filterCategory != null || _filterPaymentMethod != null)
                      SliverToBoxAdapter(child: _buildActiveFilters()),

                    // Expenses list
                    _filteredExpenses.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(theme),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildExpenseCard(_filteredExpenses[index], theme, isDark),
                              childCount: _filteredExpenses.length,
                            ),
                          ),

                    // Bottom padding
                    SliverToBoxAdapter(child: SizedBox(height: 100 + bottomPadding)),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _navigateToAddExpense,
          backgroundColor: AppColors.primary,
          child: const Icon(PhosphorIconsFill.plus, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              title: 'مصروفات الشهر',
              value: CurrencyFormatter.format(_totalThisMonth),
              icon: PhosphorIconsRegular.chartLine,
              color: AppColors.error,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              title: 'مصروفات اليوم',
              value: CurrencyFormatter.format(_totalToday),
              icon: PhosphorIconsRegular.calendarBlank,
              color: AppColors.accentOrange,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.funnel, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                if (_filterCategory != null)
                  Chip(
                    label: Text(Expense.getCategoryAr(_filterCategory), style: const TextStyle(fontSize: 12)),
                    onDeleted: () => setState(() => _filterCategory = null),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (_filterPaymentMethod != null)
                  Chip(
                    label: Text(_getPaymentMethodAr(_filterPaymentMethod), style: const TextStyle(fontSize: 12)),
                    onDeleted: () => setState(() => _filterPaymentMethod = null),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense, ThemeData theme, bool isDark) {
    final category = expense['category'] as String?;
    final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
    final amountBase = (expense['amount_base'] as num?)?.toDouble() ?? 0.0;
    final currency = expense['currency'] as String? ?? 'YER';
    final title = expense['title'] as String? ?? '';
    final expenseDate = expense['expense_date'] as String? ?? '';
    final paymentMethod = expense['payment_method'] as String? ?? 'cash';
    final beneficiary = expense['beneficiary'] as String?;
    final categoryColor = _getCategoryColor(category);
    final categoryIcon = _getCategoryIcon(category);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToEditExpense(expense),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Category icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Title and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          Expense.getCategoryAr(category),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: categoryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getPaymentMethodAr(paymentMethod),
                            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                          ),
                        ),
                        if (beneficiary != null && beneficiary.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            beneficiary,
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Amount and date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                  if (currency != 'YER' && amountBase > 0)
                    Text(
                      CurrencyFormatter.format(amountBase),
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(expenseDate),
                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),

              const SizedBox(width: 4),
              Icon(PhosphorIconsRegular.caretLeft, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(PhosphorIconsRegular.currencyDollar, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد مصروفات',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'أضف مصروف جديد بالضغط على زر الإضافة',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _navigateToAddExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
    );
    if (result == true) _loadData();
  }

  Future<void> _navigateToEditExpense(Map<String, dynamic> expense) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(expenseId: expense['id'] as int),
      ),
    );
    if (result == true) _loadData();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
