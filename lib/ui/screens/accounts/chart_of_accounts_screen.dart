import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/account_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/models/account_model.dart';
import 'package:firstpro/ui/screens/accounts/add_account_sheet.dart';
import 'package:firstpro/ui/navigation/app_router.dart';

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

  /// Exchange rates loaded from DB: currency code → rate vs YER (functional currency)
  /// YER rate is always 1.0; SAR and USD rates are loaded from currencies table.
  final Map<String, double> _exchangeRates = {'YER': 1.0};

  /// Currency symbols loaded from DB: currency code → symbol
  final Map<String, String> _currencySymbols = {'YER': 'ر.ي'};

  List<String> get _currencyOptions => CurrencyConstants.currencyOptionsWithAll;
  
  String _currencyLabel(String code) {
    if (code == 'الكل') return 'الكل';
    return '${CurrencyConstants.currencyLabel(code)} (${CurrencyConstants.currencySymbol(code)})';
  }

  final _accountTypes = [
    AccountType.ASSET,
    AccountType.LIABILITY,
    AccountType.EQUITY,
    AccountType.COST,
    AccountType.REVENUE,
    AccountType.EXPENSE,
  ];

  final _typeIcons = {
    AccountType.ASSET: Icons.business,
    AccountType.LIABILITY: Icons.savings,
    AccountType.EQUITY: Icons.account_balance,
    AccountType.COST: Icons.south_west,
    AccountType.REVENUE: Icons.arrow_outward,
    AccountType.EXPENSE: Icons.arrow_downward,
  };

  final _typeColors = {
    AccountType.ASSET: AppColors.primary,
    AccountType.LIABILITY: AppColors.warning,
    AccountType.EQUITY: AppColors.accentPurple,
    AccountType.COST: AppColors.info,
    AccountType.REVENUE: AppColors.success,
    AccountType.EXPENSE: AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<AccountRepository>().getAllAccounts();
      // Load exchange rates from DB for currency conversion
      await _loadExchangeRates();
      if (mounted) {
        setState(() {
          _accounts = maps.map((m) => Account.fromMap(m)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Load exchange rates and symbols from the currencies table.
  /// This is essential for converting foreign currency balances to the
  /// functional currency (YER) when displaying aggregated totals.
  Future<void> _loadExchangeRates() async {
    try {
      final currencies =
          await locator<ReferenceDataRepository>().getAllCurrencies();
      for (final c in currencies) {
        final code = c['code'] as String? ?? '';
        final rate = (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final symbol = c['symbol'] as String? ?? code;
        if (code.isNotEmpty) {
          _exchangeRates[code] = rate;
          _currencySymbols[code] = symbol;
        }
      }
    } catch (_) {
      // Fallback: use hardcoded rates if DB query fails
      _exchangeRates['YER'] = 1.0;
      _exchangeRates['SAR'] = 140.0;
      _exchangeRates['USD'] = 530.0;
      _currencySymbols['YER'] = 'ر.ي';
      _currencySymbols['SAR'] = 'ر.س';
      _currencySymbols['USD'] = r'$';
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  CURRENCY HELPERS (IAS 21 Compliant)
  //  According to IAS 21, each entity has a functional currency
  //  (YER in our case). Foreign currency balances are translated
  //  to the functional currency using exchange rates for aggregation.
  //  Individual accounts display in their native currency.
  // ══════════════════════════════════════════════════════════════

  /// Get the display symbol for a currency code.
  String _getCurrencySymbol(String currencyCode) {
    return _currencySymbols[currencyCode] ?? currencyCode;
  }

  /// Format an amount with the correct currency symbol for the given currency code.
  String _formatWithCurrency(double amount, String currencyCode) {
    return CurrencyFormatter.format(amount,
        symbol: _getCurrencySymbol(currencyCode));
  }

  /// Convert an amount from its native currency to the functional currency (YER).
  /// Uses the exchange rates loaded from the currencies table.
  /// This follows IAS 21: foreign currency balances are translated using
  /// the closing rate (current exchange rate) for balance sheet items.
  double _convertToFunctionalCurrency(double amount, String fromCurrency) {
    if (fromCurrency == 'YER') return amount;
    final rate = _exchangeRates[fromCurrency] ?? 1.0;
    return amount * rate;
  }

  /// Convert an amount from functional currency (YER) to a target currency.
  double _convertFromFunctionalCurrency(double amountYER, String toCurrency) {
    if (toCurrency == 'YER') return amountYER;
    final rate = _exchangeRates[toCurrency] ?? 1.0;
    if (rate == 0) return amountYER;
    return amountYER / rate;
  }

  /// Convert an amount from one currency to another via the functional currency.
  // ignore: unused_element
  double _convertCurrency(
      double amount, String fromCurrency, String toCurrency) {
    if (fromCurrency == toCurrency) return amount;
    final amountInYER = _convertToFunctionalCurrency(amount, fromCurrency);
    return _convertFromFunctionalCurrency(amountInYER, toCurrency);
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
      final id = account.id;
      if (id != null) {
        byId[id] = _AccountNode(account: account);
      }
    }

    // Link children to parents
    for (final account in filtered) {
      final id = account.id;
      if (id == null) continue;
      final node = byId[id];
      if (node == null) continue;
      final parentId = account.parentId;
      if (parentId != null) {
        final parentNode = byId[parentId];
        if (parentNode != null) {
          parentNode.children.add(node);
        } else {
          roots.add(node);
        }
      } else {
        roots.add(node);
      }
    }

    // Sort roots by account code
    roots
        .sort((a, b) => a.account.accountCode.compareTo(b.account.accountCode));

    // Sort children recursively
    void sortChildren(_AccountNode node) {
      node.children.sort(
          (a, b) => a.account.accountCode.compareTo(b.account.accountCode));
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
    _loadData();
  }

  Future<void> _deleteAccount(Account account) async {
    if (account.isSystem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يمكن حذف حسابات النظام'),
            backgroundColor: AppColors.error),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result =
          await locator<AccountRepository>().deleteAccount(account.id!);
      if (result == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('لا يمكن حذف حسابات النظام'),
                backgroundColor: AppColors.error),
          );
        }
      } else if (result == -2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('لا يمكن حذف حساب لديه حسابات فرعية'),
                backgroundColor: AppColors.error),
          );
        }
      } else if (result == -3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('لا يمكن حذف حساب مرتبط بمعاملات محاسبية'),
                backgroundColor: AppColors.error),
          );
        }
      } else if (result == -4) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('لا يمكن حذف حساب مرتبط ببنود سندات'),
                backgroundColor: AppColors.error),
          );
        }
      } else {
        _loadData();
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
              items: _currencyOptions
                  .map((c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(_currencyLabel(c),
                            style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
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
              onRefresh: () async => _loadData(),
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
                  color:
                      !_isHierarchical ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.view_list,
                      size: 18,
                      color: !_isHierarchical
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'عرض مسطح',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: !_isHierarchical
                            ? Colors.white
                            : AppColors.textSecondary,
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
                  color:
                      _isHierarchical ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_tree,
                      size: 18,
                      color: _isHierarchical
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'عرض هرمي',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _isHierarchical
                            ? Colors.white
                            : AppColors.textSecondary,
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
  //  FLAT VIEW (grouped by type - with per-currency subtotals)
  //  IAS 21 Compliance: When "All" currencies are selected, we show
  //  per-currency subtotals within each account type group. This avoids
  //  mixing different currencies into a meaningless sum.
  //  When a specific currency is selected, all balances are in that currency.
  // ══════════════════════════════════════════════════════════════
  Widget _buildFlatView(ThemeData theme, bool isDark) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: _accountTypes.map((type) {
        final accounts = _accountsByType(type);
        final color = _typeColors[type]!;
        final icon = _typeIcons[type]!;

        // Group accounts by currency for proper subtotals
        final byCurrency = <String, List<Account>>{};
        for (final acc in accounts) {
          byCurrency.putIfAbsent(acc.currency, () => []).add(acc);
        }

        return ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(Account.accountTypeAr(type),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          subtitle: _buildFlatViewSubtitle(theme, accounts, byCurrency),
          children: _buildFlatViewChildren(
              theme, isDark, accounts, byCurrency, color),
        );
      }).toList(),
    );
  }

  /// Build the subtitle for a type group in flat view.
  /// Shows account count and per-currency subtotals (when "All" is selected)
  /// or a single total (when a specific currency is selected).
  Widget _buildFlatViewSubtitle(ThemeData theme, List<Account> accounts,
      Map<String, List<Account>> byCurrency) {
    if (_selectedCurrency != 'الكل') {
      // Single currency selected - show simple total in that currency
      final total = accounts.fold<double>(0.0, (sum, a) => sum + a.balance);
      return Text(
          '${accounts.length} حساب | الرصيد: ${_formatWithCurrency(total.abs(), _selectedCurrency)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary));
    }

    // "All" currencies - show per-currency subtotals
    final parts = <String>[];
    for (final entry in byCurrency.entries) {
      final total = entry.value.fold<double>(0.0, (sum, a) => sum + a.balance);
      final symbol = _getCurrencySymbol(entry.key);
      parts.add('${CurrencyFormatter.formatValue(total.abs())} $symbol');
    }

    return Text('${accounts.length} حساب | ${parts.join(' | ')}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: AppColors.textSecondary));
  }

  /// Build the children (account tiles) for a type group in flat view.
  /// When "All" currencies is selected, includes currency separator headers.
  List<Widget> _buildFlatViewChildren(
    ThemeData theme,
    bool isDark,
    List<Account> accounts,
    Map<String, List<Account>> byCurrency,
    Color color,
  ) {
    if (_selectedCurrency != 'الكل') {
      // Single currency - simple list
      return accounts.map((account) {
        return _AccountTile(
          account: account,
          color: color,
          isDark: isDark,
          currencySymbol: account.currencySymbol,
          onTap: () => AppRouter.pushAccountLedger(context, account),
          onEdit: () => _showAddSheet(existing: account),
          onDelete: account.isSystem ? null : () => _deleteAccount(account),
        );
      }).toList();
    }

    // "All" currencies - group by currency with headers
    final children = <Widget>[];
    final sortedCurrencies = byCurrency.keys.toList()
      ..sort((a, b) {
        // YER first, then alphabetical
        if (a == 'YER') return -1;
        if (b == 'YER') return 1;
        return a.compareTo(b);
      });

    for (final currency in sortedCurrencies) {
      final currencyAccounts = byCurrency[currency]!;
      // Currency group header
      children.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.currency_exchange, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                _currencyLabel(currency),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                _formatWithCurrency(
                  currencyAccounts
                      .fold<double>(0.0, (sum, a) => sum + a.balance)
                      .abs(),
                  currency,
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      );

      // Account tiles for this currency
      for (final account in currencyAccounts) {
        children.add(
          _AccountTile(
            account: account,
            color: color,
            isDark: isDark,
            currencySymbol: account.currencySymbol,
            onTap: () => AppRouter.pushAccountLedger(context, account),
            onEdit: () => _showAddSheet(existing: account),
            onDelete: account.isSystem ? null : () => _deleteAccount(account),
          ),
        );
      }
    }

    return children;
  }

  // ══════════════════════════════════════════════════════════════
  //  HIERARCHICAL VIEW (tree by parent_id)
  //  IAS 21 Compliance: Parent accounts display their aggregated
  //  balance in their own native currency. Since the current
  //  architecture creates separate parent accounts per currency
  //  (e.g., Assets-YER, Assets-SAR, Assets-USD), each parent only
  //  has children of the same currency, so the sum is always
  //  in a single currency.
  // ══════════════════════════════════════════════════════════════
  Widget _buildHierarchicalView(ThemeData theme, bool isDark) {
    final tree = _buildTree();
    if (tree.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree,
                size: 64, color: AppColors.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('لا توجد حسابات',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: AppColors.textHint)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80, top: 4),
      children:
          tree.map((node) => _buildTreeNode(theme, isDark, node, 0)).toList(),
    );
  }

  /// حساب رصيد الحساب الأب مع تحويل العملات حسب IAS 21
  /// عند تجميع أرصدة الأبناء، نقوم بتحويل كل رصيد إلى العملة الوظيفية (YER)
  /// ثم نعرض الرصيد المجمع بالعملة الوظيفية، مع عرض تفصيلي لكل عملة
  Map<String, double> _calculateChildBalancesByCurrency(_AccountNode node) {
    final balancesByCurrency = <String, double>{};

    void addBalance(_AccountNode n) {
      final acc = n.account;
      final curr = acc.currency;
      balancesByCurrency[curr] =
          (balancesByCurrency[curr] ?? 0.0) + acc.balance;
      for (final child in n.children) {
        addBalance(child);
      }
    }

    // Include the parent's own balance
    balancesByCurrency[node.account.currency] =
        (balancesByCurrency[node.account.currency] ?? 0.0) +
            node.account.balance;

    // Add children balances
    for (final child in node.children) {
      addBalance(child);
    }

    return balancesByCurrency;
  }

  /// حساب الرصيد الإجمالي بالعملة الوظيفية (YER) حسب IAS 21
  double _calculateTotalBalanceInFunctionalCurrency(_AccountNode node) {
    final balancesByCurrency = _calculateChildBalancesByCurrency(node);
    double totalInYER = 0.0;
    for (final entry in balancesByCurrency.entries) {
      totalInYER += _convertToFunctionalCurrency(entry.value, entry.key);
    }
    return totalInYER;
  }

  /// بناء نص الأرصدة المتعددة العملات للعرض
  String _buildMultiCurrencyBalanceText(
      Map<String, double> balancesByCurrency) {
    if (balancesByCurrency.length <= 1) {
      // عملة واحدة فقط
      final entry = balancesByCurrency.entries.first;
      return CurrencyFormatter.format(entry.value.abs(),
          symbol: _getCurrencySymbol(entry.key));
    }
    // عدة عملات: عرض كل عملة بشكل منفصل
    final parts = <String>[];
    final sortedCurrencies = balancesByCurrency.keys.toList()
      ..sort((a, b) {
        if (a == 'YER') return -1;
        if (b == 'YER') return 1;
        return a.compareTo(b);
      });
    for (final curr in sortedCurrencies) {
      final balance = balancesByCurrency[curr]!;
      if (balance.abs() > 0.001) {
        parts.add(
            '${CurrencyFormatter.formatValue(balance.abs())} ${_getCurrencySymbol(curr)}');
      }
    }
    if (parts.isEmpty) return '0';
    return parts.join(' | ');
  }

  Widget _buildTreeNode(
      ThemeData theme, bool isDark, _AccountNode node, int depth) {
    final account = node.account;
    final color = _typeColors[account.accountType] ?? AppColors.primary;
    final hasChildren = node.children.isNotEmpty;
    final currencySymbol = account.currencySymbol;

    // Calculate total balance including children with IAS 21 currency conversion
    // If all children are the same currency, show in that currency
    // If mixed currencies, show total in functional currency (YER) with per-currency breakdown
    final balancesByCurrency = _calculateChildBalancesByCurrency(node);
    final totalInYER = _calculateTotalBalanceInFunctionalCurrency(node);
    final hasMixedCurrencies = balancesByCurrency.length > 1;

    // For display: use per-currency breakdown if mixed, otherwise simple total
    final balanceDisplayText = hasMixedCurrencies
        ? _buildMultiCurrencyBalanceText(balancesByCurrency)
        : CurrencyFormatter.format(balancesByCurrency.values.first.abs(),
            symbol: currencySymbol);

    // Total in functional currency for the trailing display
    final functionalTotalDisplay = hasMixedCurrencies
        ? CurrencyFormatter.format(totalInYER.abs(), symbol: 'ر.ي')
        : null;

    if (hasChildren) {
      return ExpansionTile(
        initiallyExpanded: depth < 1,
        tilePadding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 16),
        childrenPadding: EdgeInsets.only(right: 8),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _typeIcons[account.accountType] ?? Icons.account_balance,
            color: color,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Text(account.accountCode,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(account.nameAr,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(
          '${node.children.length} حساب فرعي | الرصيد: $balanceDisplayText',
          style: theme.textTheme.bodySmall?.copyWith(
            color:
                isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show own balance or functional currency total if mixed
            if (functionalTotalDisplay != null)
              Text(functionalTotalDisplay,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  )),
            if (functionalTotalDisplay == null)
              Text(
                  CurrencyFormatter.format(account.balance,
                      symbol: currencySymbol),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
              padding: EdgeInsets.only(
                  left: 16.0 + (depth + 1) * 20.0,
                  right: 16,
                  top: 4,
                  bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_left,
                      size: 18, color: color.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Text('عرض أستاذ الحساب',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      )),
                  const Spacer(),
                  Text(
                      CurrencyFormatter.format(account.balance,
                          symbol: currencySymbol),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          // Children
          ...node.children
              .map((child) => _buildTreeNode(theme, isDark, child, depth + 1))
              .toList(),
        ],
      );
    }

    // Leaf node (no children)
    return _AccountTile(
      account: account,
      color: color,
      isDark: isDark,
      depth: depth,
      currencySymbol: currencySymbol,
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
//  Updated to display balances with the correct currency symbol
//  instead of always using the default (YER) symbol.
// ═══════════════════════════════════════════════════════════════════
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.color,
    required this.isDark,
    this.depth = 0,
    this.currencySymbol = 'ر.ي',
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Account account;
  final Color color;
  final bool isDark;
  final int depth;
  final String currencySymbol;
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
          Text(account.accountCode,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(account.nameAr,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              CurrencyFormatter.format(account.balance, symbol: currencySymbol),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
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
