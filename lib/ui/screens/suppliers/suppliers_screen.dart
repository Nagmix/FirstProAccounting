import 'dart:async';
import 'package:flutter/material.dart';
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
/// - Tab bar: الكل / مدينون / دائنون.
/// - Supplier list with avatar, name, phone, and balance.
/// - Compact filter button for currency selection.
/// - FAB for adding a new supplier via [AddSupplierSheet].
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Supplier> _suppliers = [];
  bool _isLoading = true;

  // Currency filter state
  String _selectedCurrency = 'YER';
  bool _isBalancesLoading = false;
  Map<int, double> _currencyBalances = {};

  /// Currency display info.
  static const _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  /// Currency filter options.
  static const _currencyOptions = ['YER', 'SAR', 'USD'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.trim());
      });
    });
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<SupplierRepository>().getAllSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = maps.map((m) => Supplier.fromMap(m)).toList();
          _isLoading = false;
        });
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

  // ── Currency balance loading ──────────────────────────────────
  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);
    try {
      final newBalances = <int, double>{};
      final repo = locator<SupplierRepository>();

      final futures = _suppliers.map((s) async {
        if (s.id != null) {
          final balance = await repo.getSupplierBalanceForCurrency(s.id!, _selectedCurrency);
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
      if (mounted) setState(() => _isBalancesLoading = false);
    }
  }

  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    _loadCurrencyBalances();
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<Supplier> _filterSuppliers(int tabIndex) {
    var filtered = _suppliers;

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered.where((s) {
        final nameMatch = s.name.contains(q);
        final phoneMatch = s.phone?.contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    // Apply tab filter based on balance and balance_type
    switch (tabIndex) {
      case 1: // مدينون
        filtered = filtered.where((s) {
          if (s.balanceType == 'debit' && s.balance > 0) return true;
          return false;
        }).toList();
        break;
      case 2: // دائنون
        filtered = filtered.where((s) {
          if (s.balanceType == 'credit' && s.balance > 0) return true;
          return false;
        }).toList();
        break;
    }

    return filtered;
  }

  // ── Open add-supplier bottom sheet ────────────────────────────
  Future<void> _showAddSupplierSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddSupplierSheet(),
    );
    _loadSuppliers();
  }

  // ── Delete supplier ───────────────────────────────────────────
  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
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

  // ── Show currency filter popup ────────────────────────────────
  void _showCurrencyFilterPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تصفية حسب العملة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ..._currencyOptions.map((option) {
                final isSelected = _selectedCurrency == option;
                final label = _currencyInfo[option]?['label'] ?? option;
                final symbol = _currencyInfo[option]?['symbol'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _onCurrencyChanged(option);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.circle_outlined,
                            color: isSelected ? AppColors.primary : AppColors.textHint,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$label ($option)',
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            symbol,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الموردين'),
        actions: [
          // Filter button (currency)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              avatar: Icon(Icons.currency_exchange, size: 16, color: AppColors.primary),
              label: Text(
                '$currentSymbol $_selectedCurrency',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
              onPressed: _showCurrencyFilterPopup,
              backgroundColor: AppColors.primary.withOpacity(0.08),
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.local_shipping),
            tooltip: 'إضافة مورد',
            onPressed: _showAddSupplierSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'مدينون'),
            Tab(text: 'دائنون'),
          ],
        ),
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
                    hintText: 'بحث عن مورد بالاسم أو الهاتف...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Summary bar ───────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isLight ? AppColors.border : AppColors.darkBorder, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_suppliers.length} مورد',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (_isBalancesLoading)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else ...[
                        Icon(Icons.account_balance_wallet, size: 16, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          'العملة: $_selectedCurrency',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textHint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Supplier list ─────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(3, (tabIndex) {
                      final filtered = _filterSuppliers(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.local_shipping
                              : tabIndex == 1
                                  ? Icons.trending_down
                                  : Icons.trending_up,
                          title: tabIndex == 0
                              ? 'لا يوجد موردين'
                              : tabIndex == 1
                                  ? 'لا يوجد موردين مدينون'
                                  : 'لا يوجد موردين دائنون',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة موردين جدد لبدء إدارة حساباتك'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel: tabIndex == 0 ? 'إضافة مورد' : null,
                          onAction: tabIndex == 0 ? _showAddSupplierSheet : null,
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80, top: 2),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final supplier = filtered[index];
                          return _SupplierCard(
                            supplier: supplier,
                            avatarColor: _avatarColor(supplier.name),
                            displayBalance: _currencyBalances[supplier.id] ?? 0.0,
                            currencySymbol: _currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
                            isLight: isLight,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SupplierDetailScreen(supplier: supplier),
                                ),
                              ).then((_) => _loadSuppliers());
                            },
                            onDelete: () => _deleteSupplier(supplier),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSupplierSheet,
        tooltip: 'إضافة مورد',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_shipping),
        label: const Text('إضافة مورد'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SUPPLIER CARD — Modern, Professional Design
// ═══════════════════════════════════════════════════════════════════
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.avatarColor,
    required this.displayBalance,
    required this.currencySymbol,
    required this.isLight,
    this.onTap,
    this.onDelete,
  });

  final Supplier supplier;
  final Color avatarColor;
  final double displayBalance;
  final String currencySymbol;
  final bool isLight;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDebit = displayBalance < 0;
    final isCredit = displayBalance > 0;
    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    final balanceAbs = CurrencyFormatter.format(displayBalance.abs());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppColors.border.withOpacity(0.5) : AppColors.darkBorder.withOpacity(0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.04 : 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── Avatar ───────────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarColor, avatarColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      supplier.name.isNotEmpty ? supplier.name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

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
                            size: 13,
                            color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            supplier.phone ?? '—',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLight ? AppColors.textSecondary : AppColors.darkTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ── Balance Section - الرصيد with color ──────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayBalance != 0
                          ? [balanceColor.withOpacity(0.12), balanceColor.withOpacity(0.04)]
                          : [Colors.grey.withOpacity(0.06), Colors.grey.withOpacity(0.02)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0 ? balanceColor.withOpacity(0.25) : AppColors.border.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDebit ? Icons.trending_down : isCredit ? Icons.trending_up : Icons.remove,
                        size: 14,
                        color: displayBalance != 0 ? balanceColor : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balanceAbs $currencySymbol',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: displayBalance != 0 ? balanceColor : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // ── Arrow icon ──────────────────────────────────
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 12,
                    color: isLight ? AppColors.textHint : AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
