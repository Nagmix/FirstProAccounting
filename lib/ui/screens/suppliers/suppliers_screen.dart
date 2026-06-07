import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/supplier_repository.dart';
import '../../../data/models/supplier_model.dart';
import '../../widgets/empty_state.dart';
import 'add_supplier_sheet.dart';
import 'supplier_detail_screen.dart';

/// Professional suppliers management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or phone.
/// - Supplier list with avatar, name, phone, and balance.
/// - FAB for adding a new supplier via [AddSupplierSheet].
/// - Tap to navigate to detail/ledger screen.
/// - Long press for Edit/Delete options.
/// - Dynamic balance display based on actual financial position.
/// - Empty state when no suppliers exist.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Supplier> _suppliers = [];
  bool _isLoading = true;

  // Currency filter state
  String _selectedCurrency = 'YER';
  bool _isBalancesLoading = false;
  Map<int, double> _currencyBalances = {};

  static const _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  static const _currencyOptions = ['YER', 'SAR', 'USD'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Load suppliers from database ──────────────────────────────
  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<SupplierRepository>().getAllSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = maps.map((m) => Supplier.fromMap(m)).toList();
          _isLoading = false;
        });
        // Always load currency balances for the selected currency
        _loadCurrencyBalances();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Load balances for all suppliers filtered by the selected currency ──
  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);

    try {
      final newBalances = <int, double>{};
      final repo = locator<SupplierRepository>();

      // Load balances for all suppliers in parallel
      final futures = _suppliers.map((s) async {
        if (s.id != null) {
          final balance = await repo.getSupplierBalanceForCurrency(
            s.id!,
            _selectedCurrency,
          );
          return MapEntry(s.id!, balance);
        }
        return null;
      });

      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry != null) {
          newBalances[entry.key] = entry.value;
        }
      }

      if (mounted) {
        setState(() {
          _currencyBalances = newBalances;
          _isBalancesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBalancesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('حدث خطأ أثناء تحميل الأرصدة'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Get the currency symbol to display based on selected filter.
  String _getCurrencySymbol() {
    return _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';
  }

  /// Handle currency filter change.
  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    _loadCurrencyBalances();
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<Supplier> get _filteredSuppliers {
    var filtered = _suppliers;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered.where((s) {
        final nameMatch = s.name.contains(q);
        final phoneMatch = s.phone?.contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    return filtered;
  }

  // ── Open add-supplier bottom sheet ────────────────────────────
  Future<void> _showAddSupplierSheet({Supplier? supplier}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddSupplierSheet(supplier: supplier),
    );
    if (!mounted) return;
    _loadSuppliers();
  }

  // ── Navigate to supplier detail/ledger ────────────────────────
  Future<void> _navigateToDetail(Supplier supplier) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierDetailScreen(supplier: supplier),
      ),
    );
    if (!mounted) return;
    _loadSuppliers();
  }

  // ── Show long-press menu (Edit / Delete) ──────────────────────
  void _showContextMenu(Supplier supplier) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                supplier.name,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddSupplierSheet(supplier: supplier);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('حذف',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteSupplier(supplier);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Delete supplier ───────────────────────────────────────────
  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning,
            color: AppColors.error, size: 40),
        title: const Text('حذف المورد'),
        content: Text('هل أنت متأكد من حذف المورد "${supplier.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await locator<SupplierRepository>().deleteSupplier(supplier.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف المورد "${supplier.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadSuppliers();
    }
  }

  // ── Avatar color based on name ────────────────────────────────
  static const List<Color> _avatarColors = [
    Color(0xFF1A237E),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1B5E20),
    Color(0xFF33691E),
  ];

  Color _avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return _avatarColors[hash % _avatarColors.length];
  }

  // ── Currency Filter Widget ────────────────────────────────────────
  Widget _buildCurrencyFilter(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.currency_exchange,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'العملة:',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _currencyOptions.map((option) {
                  final isSelected = _selectedCurrency == option;
                  final label =
                      '${_currencyInfo[option]?['symbol'] ?? ''} $option';
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) => _onCurrencyChanged(option),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                      ),
                      backgroundColor: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      selectedColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Total Balance Card Widget ─────────────────────────────────────
  Widget _buildTotalBalanceCard(
    ThemeData theme,
    double totalBalance,
    String currencySymbol,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_shipping, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجمالي الرصيد (${_currencyInfo[_selectedCurrency]?['label'] ?? _selectedCurrency})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(totalBalance.abs(),
                      symbol: currencySymbol),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            totalBalance >= 0 ? 'له' : 'عليه',
            style: theme.textTheme.labelLarge?.copyWith(
              color: totalBalance >= 0 ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSuppliers;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencySymbol = _getCurrencySymbol();

    // Compute total balance for the selected currency
    double totalBalance = 0;
    if (!_isBalancesLoading) {
      for (final s in filtered) {
        totalBalance += _currencyBalances[s.id] ?? 0.0;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الموردين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
          ),
          IconButton(
            icon: const Icon(Icons.local_shipping),
            tooltip: 'إضافة مورد',
            onPressed: () => _showAddSupplierSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن مورد...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Currency Filter Row ───────────────────────────────
                _buildCurrencyFilter(theme, isDark),

                // ── Total balance card ────────────────────────────────
                if (filtered.isNotEmpty)
                  _buildTotalBalanceCard(theme, totalBalance, currencySymbol),

                // ── Supplier list ─────────────────────────────────────
                Expanded(
                  child: _isBalancesLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 32),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.local_shipping,
                              title: _searchQuery.isNotEmpty
                                  ? 'لا توجد نتائج'
                                  : 'لا يوجد موردين',
                              subtitle: _searchQuery.isNotEmpty
                                  ? 'لم يتم العثور على نتائج مطابقة للبحث'
                                  : 'قم بإضافة موردين جدد لبدء إدارة حساباتك',
                              actionLabel:
                                  _searchQuery.isEmpty ? 'إضافة مورد' : null,
                              onAction:
                                  _searchQuery.isEmpty
                                      ? _showAddSupplierSheet
                                      : null,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final supplier = filtered[index];
                                final balance =
                                    _currencyBalances[supplier.id] ?? 0.0;
                                return _SupplierCard(
                                  supplier: supplier,
                                  avatarColor: _avatarColor(supplier.name),
                                  balance: balance,
                                  currencySymbol: currencySymbol,
                                  onTap: () => _navigateToDetail(supplier),
                                  onLongPress: () =>
                                      _showContextMenu(supplier),
                                );
                              },
                            ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSupplierSheet(),
        tooltip: 'إضافة مورد',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.local_shipping),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SUPPLIER CARD
// ═══════════════════════════════════════════════════════════════════
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.avatarColor,
    required this.balance,
    required this.currencySymbol,
    this.onTap,
    this.onLongPress,
  });

  final Supplier supplier;
  final Color avatarColor;
  final double balance;
  final String currencySymbol;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    // Dynamic balance: use the per-currency computed balance
    // balance > 0 means credit (له), balance < 0 means debit (عليه)
    final balanceLabel = balance.abs() < 0.005
        ? 'متساوي'
        : balance > 0
            ? 'له'
            : 'عليه';

    final balanceColor = balanceLabel == 'متساوي'
        ? (isLight ? AppColors.textSecondary : AppColors.darkTextSecondary)
        : balanceLabel == 'له'
            ? AppColors.success
            : AppColors.error;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  supplier.name.isNotEmpty ? supplier.name[0] : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: avatarColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name, phone ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          supplier.contactMethod == 'whatsapp'
                              ? Icons.chat
                              : Icons.phone_in_talk,
                          size: 14,
                          color: isLight
                              ? AppColors.textHint
                              : AppColors.darkTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          supplier.phone ?? '—',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isLight
                                ? AppColors.textSecondary
                                : AppColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Balance ──────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(balance.abs(),
                        symbol: currencySymbol),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    balanceLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: balanceColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),

              // ── Arrow icon (RTL – points left visually) ─────
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: isLight
                    ? AppColors.textHint
                    : AppColors.darkTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
