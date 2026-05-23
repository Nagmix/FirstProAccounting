import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/account_model.dart';
import 'add_account_sheet.dart';
import '../../../ui/navigation/app_router.dart';

class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> {
  List<Account> _accounts = [];
  bool _isLoading = true;
  String _selectedCurrency = 'الكل';

  final _currencyOptions = ['الكل', 'YER', 'SAR', 'USD'];
  final _currencyLabels = {'الكل': 'الكل', 'YER': 'ريال يمني (ر.ي)', 'SAR': 'ريال سعودي (ر.س)', 'USD': 'دولار أمريكي (\$)'};

  final _accountTypes = [
    AccountType.ASSET,
    AccountType.LIABILITY,
    AccountType.COST,
    AccountType.REVENUE,
    AccountType.EXPENSE,
  ];

  final _typeIcons = {
    AccountType.ASSET: PhosphorIconsRegular.buildings,
    AccountType.LIABILITY: PhosphorIconsRegular.handCoins,
    AccountType.COST: PhosphorIconsRegular.arrowDownLeft,
    AccountType.REVENUE: PhosphorIconsRegular.arrowUpRight,
    AccountType.EXPENSE: PhosphorIconsRegular.arrowDown,
  };

  final _typeColors = {
    AccountType.ASSET: AppColors.primary,
    AccountType.LIABILITY: AppColors.warning,
    AccountType.COST: AppColors.info,
    AccountType.REVENUE: AppColors.success,
    AccountType.EXPENSE: AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper();
    final maps = await db.getAllAccounts();
    setState(() {
      _accounts = maps.map((m) => Account.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  List<Account> _accountsByType(AccountType type) {
    var filtered = _accounts.where((a) => a.accountType == type);
    if (_selectedCurrency != 'الكل') {
      filtered = filtered.where((a) => a.currency == _selectedCurrency);
    }
    return filtered.toList();
  }

  Future<void> _showAddSheet({Account? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddAccountSheet(existing: existing),
    );
    _loadAccounts();
  }

  Future<void> _deleteAccount(Account account) async {
    if (account.isSystem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف حسابات النظام'), backgroundColor: AppColors.error),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(PhosphorIconsRegular.warning, color: AppColors.error, size: 40),
        title: const Text('حذف الحساب'),
        content: Text('هل أنت متأكد من حذف "${account.nameAr}"؟'),
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
      final result = await db.deleteAccount(account.id!);
      if (result == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حذف حسابات النظام'), backgroundColor: AppColors.error),
          );
        }
      } else if (result == -2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حذف حساب لديه حسابات فرعية'), backgroundColor: AppColors.error),
          );
        }
      } else if (result == -3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حذف حساب مرتبط بمعاملات محاسبية'), backgroundColor: AppColors.error),
          );
        }
      } else {
        _loadAccounts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دليل الحسابات'),
        actions: [
          // Currency filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButton<String>(
              value: _selectedCurrency,
              underline: const SizedBox.shrink(),
              icon: const Icon(PhosphorIconsRegular.caretDown, size: 16),
              items: _currencyOptions.map((c) => DropdownMenuItem<String>(
                value: c,
                child: Text(_currencyLabels[c] ?? c, style: const TextStyle(fontSize: 12)),
              )).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedCurrency = val);
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.plus),
            tooltip: 'إضافة حساب',
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _loadAccounts(),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: _accountTypes.map((type) {
                  final accounts = _accountsByType(type);
                  final color = _typeColors[type]!;
                  final icon = _typeIcons[type]!;
                  final typeTotal = accounts.fold<double>(0.0, (sum, a) => sum + a.balance);

                  return ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    title: Text(Account.accountTypeAr(type),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
                    subtitle: Text('${accounts.length} حساب | الرصيد: ${CurrencyFormatter.format(typeTotal.abs())}',
                        style: theme.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
                    children: accounts.map((account) {
                      return _AccountTile(
                        account: account,
                        color: color,
                        isDark: isDark,
                        onTap: () => AppRouter.pushAccountLedger(context, account),
                        onEdit: () => _showAddSheet(existing: account),
                        onDelete: account.isSystem ? null : () => _deleteAccount(account),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة حساب جديد',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(PhosphorIconsRegular.plus),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.color,
    required this.isDark,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Account account;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: account.isSystem
          ? Icon(PhosphorIconsFill.lockSimple, size: 18, color: AppColors.textHint)
          : Icon(PhosphorIconsRegular.circle, size: 10, color: color),
      title: Row(
        children: [
          Text(account.accountCode, style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600, color: color,
          )),
          const SizedBox(width: 8),
          Text(account.nameAr, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(CurrencyFormatter.format(account.balance),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if (onEdit != null)
            IconButton(
              icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 16),
              color: AppColors.info,
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(PhosphorIconsRegular.trash, size: 16),
              color: AppColors.error,
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
