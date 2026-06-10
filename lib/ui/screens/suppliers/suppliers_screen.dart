import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/helpers/currency_constants.dart';
import '../../../core/helpers/avatar_helper.dart';
import '../../../core/helpers/delete_helper.dart';
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
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((s) {
        final nameMatch = s.name.toLowerCase().contains(q);
        final phoneMatch = s.phone?.toLowerCase().contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    // Apply tab filter based on currency-specific balance
    switch (tabIndex) {
      case 1: // مدينون — negative balance (عليه)
        filtered = filtered.where((s) {
          if (s.id == null) return false;
          final balance = _currencyBalances[s.id] ?? 0.0;
          return balance < 0;
        }).toList();
        break;
      case 2: // دائنون — positive balance (له)
        filtered = filtered.where((s) {
          if (s.id == null) return false;
          final balance = _currencyBalances[s.id] ?? 0.0;
          return balance > 0;
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
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: 'المورد',
      entityName: supplier.name,
    );
    if (confirmed) {
      await locator<SupplierRepository>().deleteSupplier(supplier.id!);
      if (mounted) {
        DeleteHelper.showDeleteSuccess(context, 'المورد', supplier.name);
      }
      _loadSuppliers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final currentSymbol = CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

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
              onPressed: () => CurrencyConstants.showCurrencyFilterPopup(
                context: context,
                selectedCurrency: _selectedCurrency,
                onSelected: _onCurrencyChanged,
              ),
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
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
                        const SizedBox(width: 12),
                        Icon(Icons.calculate, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'الإجمالي: ${CurrencyFormatter.formatValue(_currencyBalances.values.fold(0.0, (sum, b) => sum + b))} $currentSymbol',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
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

                      return RefreshIndicator(
                        onRefresh: _loadSuppliers,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80, top: 2),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                          final supplier = filtered[index];
                          return _SupplierCard(
                            supplier: supplier,
                            avatarColor: AvatarHelper.avatarColor(supplier.name),
                            displayBalance: _currencyBalances[supplier.id] ?? 0.0,
                            currencySymbol: CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي',
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
                        )
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

    final balanceAbs = CurrencyFormatter.formatValue(displayBalance.abs());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppColors.border.withValues(alpha: 0.5) : AppColors.darkBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.2),
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
                      colors: [avatarColor, avatarColor.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withValues(alpha: 0.3),
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
                          ? [balanceColor.withValues(alpha: 0.12), balanceColor.withValues(alpha: 0.04)]
                          : [Colors.grey.withValues(alpha: 0.06), Colors.grey.withValues(alpha: 0.02)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0 ? balanceColor.withValues(alpha: 0.25) : AppColors.border.withValues(alpha: 0.3),
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
