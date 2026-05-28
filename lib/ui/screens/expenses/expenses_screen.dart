import 'package:flutter/material.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import 'expense_account_detail_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> _expenseAccounts = [];
  bool _isLoading = true;
  double _totalExpenseBalance = 0.0;
  int _totalAccounts = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final accounts = await db.getExpenseAccounts();

    double totalBalance = 0.0;
    for (final account in accounts) {
      final balance = (account['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = account['balance_type'] as String? ?? 'credit';
      final accountType = account['account_type'] as String? ?? '';
      // Use effective balance type: EXPENSE/COST/ASSET are debit-nature
      final effectiveIsDebit = (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE');
      if (effectiveIsDebit) {
        // Debit-nature: positive balance = debit (expense incurred) → add to total
        totalBalance += balance;
      } else {
        // Credit-nature: positive balance = credit → subtract from total
        totalBalance -= balance;
      }
    }

    setState(() {
      _expenseAccounts = accounts;
      _totalExpenseBalance = totalBalance;
      _totalAccounts = accounts.length;
      _isLoading = false;
    });
  }

  String _getCurrencySymbol(String? currency) {
    switch (currency) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  Color _getCurrencyColor(String? currency) {
    switch (currency) {
      case 'SAR': return AppColors.accentGreen;
      case 'USD': return AppColors.accentOrange;
      case 'YER': default: return AppColors.primary;
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
          title: const Text('حسابات المصروفات'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // Summary header
                    SliverToBoxAdapter(child: _buildSummaryHeader(theme, isDark)),

                    // Expense accounts list
                    _expenseAccounts.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(theme),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildExpenseAccountCard(_expenseAccounts[index], theme, isDark),
                              childCount: _expenseAccounts.length,
                            ),
                          ),

                    // Bottom padding
                    SliverToBoxAdapter(child: SizedBox(height: 100 + bottomPadding)),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddExpenseAccountDialog,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي المصروفات',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(_totalExpenseBalance.abs()),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryChip(
                icon: Icons.account_balance,
                label: 'عدد الحسابات',
                value: _totalAccounts.toString(),
              ),
              const SizedBox(width: 12),
              _buildSummaryChip(
                icon: Icons.trending_down,
                label: 'الحالة',
                value: _totalExpenseBalance >= 0 ? 'عليه' : 'له',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseAccountCard(Map<String, dynamic> account, ThemeData theme, bool isDark) {
    final name = account['name_ar'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'YER';
    final debtCeiling = (account['debt_ceiling'] as num?)?.toDouble() ?? 0.0;
    final balance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    final balanceType = account['balance_type'] as String? ?? 'credit';
    final accountCode = account['account_code'] as String? ?? '';
    final isSystem = (account['is_system'] as int?) == 1;
    final currencyColor = _getCurrencyColor(currency);
    final currencySymbol = _getCurrencySymbol(currency);

    // Use effective balance direction for expense accounts (debit-nature)
    final accountType = account['account_type'] as String? ?? '';
    final effectiveIsDebit = (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE');
    // For debit-nature accounts, positive balance = debit (عليه)
    final isCredit = effectiveIsDebit ? balance < 0 : balance > 0;
    final balanceColor = isCredit ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.2) : AppColors.primary.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToAccountDetail(account),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Account name and balance type
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: currencyColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSystem ? Icons.account_balance_wallet : Icons.folder_open,
                      color: currencyColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: currencyColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                accountCode,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: currencyColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                currencySymbol,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Balance amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(balance),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: balanceColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: balanceColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isCredit ? 'له' : 'عليه',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: balanceColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_back_ios, size: 16, color: AppColors.textHint),
                ],
              ),

              // Row 2: Debt ceiling info
              if (debtCeiling > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text(
                        'سقف المديونية: ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(debtCeiling),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (debtCeiling > 0 && balance > 0)
                        Text(
                          '${(balance / debtCeiling * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: balance / debtCeiling > 0.9 ? AppColors.error : AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.account_balance_wallet, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد حسابات مصروفات',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'أضف حساب مصروف جديد بالضغط على زر الإضافة',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToAccountDetail(Map<String, dynamic> account) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseAccountDetailScreen(account: account),
      ),
    );
    if (result == true) _loadData();
  }

  void _showAddExpenseAccountDialog() {
    final nameController = TextEditingController();
    final debtCeilingController = TextEditingController();
    final openingBalanceController = TextEditingController();
    final notesController = TextEditingController();
    String selectedCurrency = 'YER';
    String balanceType = 'credit'; // له

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  left: 16,
                  right: 16,
                  top: 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Title
                      Row(
                        children: [
                          Icon(Icons.create_new_folder, color: AppColors.primary, size: 24),
                          const SizedBox(width: 10),
                          Text(
                            'إضافة حساب مصروف جديد',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Account name
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الحساب *',
                          prefixIcon: Icon(Icons.text_fields),
                          hintText: 'مثال: مصاريف إيجار',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Currency selection
                      DropdownButtonFormField<String>(
                        value: selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'العملة',
                          prefixIcon: Icon(Icons.monetization_on),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'YER', child: Text('ريال يمني (ر.ي)')),
                          DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (ر.س)')),
                          DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (\$)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedCurrency = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Debt ceiling
                      TextFormField(
                        controller: debtCeilingController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سقف المديونية',
                          prefixIcon: Icon(Icons.shield),
                          hintText: '0.00',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Opening balance
                      TextFormField(
                        controller: openingBalanceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الرصيد الافتتاحي',
                          prefixIcon: Icon(Icons.attach_money),
                          hintText: '0.00',
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Balance type selector (له / عليه)
                      Text(
                        'نوع الرصيد الافتتاحي',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => balanceType = 'credit'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: balanceType == 'credit'
                                      ? AppColors.success.withOpacity(0.08)
                                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: balanceType == 'credit' ? AppColors.success : AppColors.divider,
                                    width: balanceType == 'credit' ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.south_east,
                                      size: 20,
                                      color: balanceType == 'credit' ? AppColors.success : AppColors.textHint,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'له',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: balanceType == 'credit' ? FontWeight.w700 : FontWeight.w500,
                                        color: balanceType == 'credit' ? AppColors.success : AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      '(دائن)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: balanceType == 'credit' ? AppColors.success : AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => balanceType = 'debit'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: balanceType == 'debit'
                                      ? AppColors.error.withOpacity(0.08)
                                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: balanceType == 'debit' ? AppColors.error : AppColors.divider,
                                    width: balanceType == 'debit' ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.north_west,
                                      size: 20,
                                      color: balanceType == 'debit' ? AppColors.error : AppColors.textHint,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'عليه',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: balanceType == 'debit' ? FontWeight.w700 : FontWeight.w500,
                                        color: balanceType == 'debit' ? AppColors.error : AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      '(مدين)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: balanceType == 'debit' ? AppColors.error : AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات',
                          prefixIcon: Icon(Icons.edit_note),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 20),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (nameController.text.trim().isEmpty) {
                              context.showErrorSnackBar('اسم الحساب مطلوب');
                              return;
                            }
                            final db = DatabaseHelper();
                            await db.createExpenseAccount(
                              nameAr: nameController.text.trim(),
                              currency: selectedCurrency,
                              debtCeiling: double.tryParse(debtCeilingController.text),
                              openingBalance: double.tryParse(openingBalanceController.text) ?? 0.0,
                              balanceType: balanceType,
                              notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              context.showSuccessSnackBar('تم إنشاء حساب المصروف بنجاح');
                              _loadData();
                            }
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ الحساب'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
