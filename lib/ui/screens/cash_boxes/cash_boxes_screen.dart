import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/cash_box_model.dart';
import 'add_cash_box_sheet.dart';

class CashBoxesScreen extends StatefulWidget {
  const CashBoxesScreen({super.key});

  @override
  State<CashBoxesScreen> createState() => _CashBoxesScreenState();
}

class _CashBoxesScreenState extends State<CashBoxesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CashBox> _cashBoxes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCashBoxes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCashBoxes() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      final maps = await db.getAllCashBoxes();
      if (mounted) {
        setState(() {
          _cashBoxes = maps.map((m) => CashBox.fromMap(m)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<CashBox> _filterByTab(int tabIndex) {
    switch (tabIndex) {
      case 1: return _cashBoxes.where((c) => c.isCashBox).toList();
      case 2: return _cashBoxes.where((c) => c.isBank).toList();
      default: return _cashBoxes;
    }
  }

  Future<void> _showAddSheet({CashBox? existing}) async {
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      builder: (context) => AddCashBoxSheet(existing: existing),
    );
    _loadCashBoxes();
  }

  Future<void> _deleteCashBox(CashBox cashBox) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف الصندوق'),
        content: Text('هل أنت متأكد من حذف "${cashBox.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = DatabaseHelper();
      await db.deleteCashBox(cashBox.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف "${cashBox.name}"'), backgroundColor: AppColors.success),
        );
      }
      _loadCashBoxes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الصناديق والبنوك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة',
            onPressed: () => _showAddSheet(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'صناديق'),
            Tab(text: 'بنوك'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: List.generate(3, (tabIndex) {
                final filtered = _filterByTab(tabIndex);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet, size: 72, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(tabIndex == 0 ? 'لا توجد صناديق أو بنوك' : tabIndex == 1 ? 'لا توجد صناديق' : 'لا توجد بنوك',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _showAddSheet(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('إضافة جديدة'),
                        ),
                      ],
                    ),
                  );
                }

                double totalBalance = 0;
                for (final cb in filtered) {
                  totalBalance += cb.balanceType == 'credit' ? cb.balance : -cb.balance;
                }

                return Column(
                  children: [
                    // Total balance card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('إجمالي الرصيد', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary)),
                                Text(CurrencyFormatter.format(totalBalance.abs()),
                                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ],
                            ),
                          ),
                          Text(totalBalance >= 0 ? 'له' : 'عليه',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: totalBalance >= 0 ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                    // List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final cashBox = filtered[index];
                          return _CashBoxCard(
                            cashBox: cashBox,
                            isDark: isDark,
                            onTap: () => _showAddSheet(existing: cashBox),
                            onDelete: () => _deleteCashBox(cashBox),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة صندوق أو بنك',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CashBoxCard extends StatelessWidget {
  const _CashBoxCard({required this.cashBox, required this.isDark, this.onTap, this.onDelete});

  final CashBox cashBox;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Compute actual balance dynamically: credit = positive, debit = negative
    // The balance_type stored in DB is ONLY for the opening balance direction
    final effectiveBalance = cashBox.balanceType == 'credit' ? cashBox.balance : -cashBox.balance;
    final isCredit = effectiveBalance >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: cashBox.isBank
                      ? AppColors.info.withOpacity(0.12)
                      : AppColors.secondaryDark.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  cashBox.isBank ? Icons.account_balance : Icons.account_balance_wallet,
                  color: cashBox.isBank ? AppColors.info : AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(cashBox.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cashBox.isBank
                                ? AppColors.info.withOpacity(0.1)
                                : AppColors.secondaryDark.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(cashBox.typeAr,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cashBox.isBank ? AppColors.info : AppColors.secondaryDark,
                              )),
                        ),
                      ],
                    ),
                    if (cashBox.isBank && cashBox.bankName != null) ...[
                      const SizedBox(height: 4),
                      Text('${cashBox.bankName}${cashBox.bankBranch != null ? ' - ${cashBox.bankBranch}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(CurrencyFormatter.format(effectiveBalance.abs()),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(isCredit ? 'له' : 'عليه',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isCredit ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
