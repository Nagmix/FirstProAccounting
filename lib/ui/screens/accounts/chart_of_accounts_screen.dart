import 'package:flutter/material.dart';
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
  bool _isHierarchical = false;

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
    AccountType.ASSET: Icons.business,
    AccountType.LIABILITY: Icons.savings,
    AccountType.COST: Icons.south_west,
    AccountType.REVENUE: Icons.arrow_outward,
    AccountType.EXPENSE: Icons.arrow_downward,
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

  List<Account> get _filteredAccounts {
    if (_selectedCurrency == 'الكل') return _accounts;
    return _accounts.where((a) => a.currency == _selectedCurrency).toList();
  }

  List<Account> _accountsByType(AccountType type) {
    var filtered = _accounts.where((a) => a.accountType == type);
    if (_selectedCurrency != 'الكل') {
      filtered = filtered.where((a) => a.currency == _selectedCurrency);
    }
    return filtered.toList();
  }

  /// Build hierarchical tree: returns root accounts with their children.
  List<_AccountNode> _buildTree() {
    final filtered = _filteredAccounts;
    final byId = <int, _AccountNode>{};
    final roots = <_AccountNode>[];

    // Create nodes for all accounts
    for (final account in filtered) {
      if (account.id != null) {
        byId[account.id!] = _AccountNode(account: account);
      }
    }

    // Link children to parents
    for (final account in filtered) {
      if (account.id == null) continue;
      final node = byId[account.id!]!;
      if (account.parentId != null && byId.containsKey(account.parentId)) {
        byId[account.parentId]!.children.add(node);
      } else {
        roots.add(node);
      }
    }

    // Sort roots by account code
    roots.sort((a, b) => a.account.accountCode.compareTo(b.account.accountCode));

    // Sort children recursively
    void sortChildren(_AccountNode node) {
      node.children.sort((a, b) => a.account.accountCode.compareTo(b.account.accountCode));
      for (final child in node.children) {
        sortChildren(child);
      }
    }
    for (final root in roots) {
      sortChildren(root);
    }

    return roots;
  }

  Future<void> _showAddSheet({Account? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddAccountSheet(
        existing: existing,
        allAccounts: _accounts,
      ),
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
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
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
              icon: const Icon(Icons.arrow_drop_down, size: 16),
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
            icon: const Icon(Icons.add),
            tooltip: 'إضافة حساب',
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _loadAccounts(),
              child: Column(
                children: [
                  // View toggle
                  _buildViewToggle(theme, isDark),
                  // Content
                  Expanded(
                    child: _isHierarchical
                        ? _buildHierarchicalView(theme, isDark)
                        : _buildFlatView(theme, isDark),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة حساب جديد',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  VIEW TOGGLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildViewToggle(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isHierarchical = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_isHierarchical ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.view_list,
                      size: 18,
                      color: !_isHierarchical ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'عرض مسطح',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: !_isHierarchical ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isHierarchical = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isHierarchical ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_tree,
                      size: 18,
                      color: _isHierarchical ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'عرض هرمي',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _isHierarchical ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  FLAT VIEW (grouped by type - original behavior)
  // ══════════════════════════════════════════════════════════════
  Widget _buildFlatView(ThemeData theme, bool isDark) {
    return ListView(
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
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HIERARCHICAL VIEW (tree by parent_id)
  // ══════════════════════════════════════════════════════════════
  Widget _buildHierarchicalView(ThemeData theme, bool isDark) {
    final tree = _buildTree();
    if (tree.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree, size: 64, color: AppColors.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('لا توجد حسابات', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80, top: 4),
      children: tree.map((node) => _buildTreeNode(theme, isDark, node, 0)).toList(),
    );
  }

  Widget _buildTreeNode(ThemeData theme, bool isDark, _AccountNode node, int depth) {
    final account = node.account;
    final color = _typeColors[account.accountType] ?? AppColors.primary;
    final hasChildren = node.children.isNotEmpty;

    // Calculate total balance including children
    double totalBalance = account.balance;
    void addChildBalances(_AccountNode n) {
      for (final child in n.children) {
        totalBalance += child.account.balance;
        addChildBalances(child);
      }
    }
    addChildBalances(node);

    if (hasChildren) {
      return ExpansionTile(
        initiallyExpanded: depth < 1,
        tilePadding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 16),
        childrenPadding: EdgeInsets.only(right: 8),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _typeIcons[account.accountType] ?? Icons.account_balance,
            color: color, size: 18,
          ),
        ),
        title: Row(
          children: [
            Text(account.accountCode,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(account.nameAr,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(
          '${node.children.length} حساب فرعي | الرصيد: ${CurrencyFormatter.format(totalBalance.abs())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(CurrencyFormatter.format(account.balance),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            if (!account.isSystem)
              IconButton(
                icon: const Icon(Icons.edit, size: 16),
                color: AppColors.info,
                onPressed: () => _showAddSheet(existing: account),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (!account.isSystem)
              IconButton(
                icon: const Icon(Icons.delete, size: 16),
                color: AppColors.error,
                onPressed: () => _deleteAccount(account),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
        children: [
          // Parent account is also tappable - show as a tile
          InkWell(
            onTap: () => AppRouter.pushAccountLedger(context, account),
            child: Padding(
              padding: EdgeInsets.only(left: 16.0 + (depth + 1) * 20.0, right: 16, top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_left, size: 18, color: color.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Text('عرض أستاذ الحساب',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      )),
                  const Spacer(),
                  Text(CurrencyFormatter.format(account.balance),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          // Children
          ...node.children.map((child) => _buildTreeNode(theme, isDark, child, depth + 1)).toList(),
        ],
      );
    }

    // Leaf node (no children)
    return _AccountTile(
      account: account,
      color: color,
      isDark: isDark,
      depth: depth,
      onTap: () => AppRouter.pushAccountLedger(context, account),
      onEdit: () => _showAddSheet(existing: account),
      onDelete: account.isSystem ? null : () => _deleteAccount(account),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  HELPER: Account tree node
// ═══════════════════════════════════════════════════════════════════
class _AccountNode {
  _AccountNode({required this.account});
  final Account account;
  final List<_AccountNode> children = [];
}

// ═══════════════════════════════════════════════════════════════════
//  ACCOUNT TILE WIDGET
// ═══════════════════════════════════════════════════════════════════
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.color,
    required this.isDark,
    this.depth = 0,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Account account;
  final Color color;
  final bool isDark;
  final int depth;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 24.0 + depth * 20.0, right: 16),
      leading: account.isSystem
          ? Icon(Icons.lock, size: 18, color: AppColors.textHint)
          : Icon(Icons.circle, size: 10, color: color),
      title: Row(
        children: [
          Text(account.accountCode, style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600, color: color,
          )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(account.nameAr,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(CurrencyFormatter.format(account.balance),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              color: AppColors.info,
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
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
