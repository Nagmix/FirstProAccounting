import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/helpers/avatar_helper.dart';
import 'package:firstpro/core/helpers/delete_helper.dart';
import 'package:firstpro/ui/widgets/empty_state.dart';

/// UI-10: Generic entities screen that replaces both CustomersScreen and
/// SuppliersScreen. Both were ~98% structurally identical — this widget
/// parameterizes the ~2% that differs (model type, repo callbacks,
/// labels, icons, card phone-icon behavior).
///
/// The screen provides:
///   - 3-tab filter (الكل / مدينون / دائنون).
///   - Debounced search by name + phone.
///   - Currency filter via ActionChip.
///   - Per-entity balance loading per selected currency.
///   - Add via bottom sheet.
///   - Delete with confirmation dialog.
///   - Navigate to detail screen.
///   - Card with avatar, name, phone, balance, PopupMenuButton.
class EntitiesScreen<T> extends StatefulWidget {
  const EntitiesScreen({
    super.key,
    required this.title,
    required this.entityNoun,
    required this.entityNounPlural,
    required this.deleteEntityTypeLabel,
    required this.searchHint,
    required this.addLabel,
    required this.emptyTitleAll,
    required this.emptyTitleDebit,
    required this.emptyTitleCredit,
    required this.emptySubtitleAll,
    required this.entityIcon,
    required this.addIcon,
    required this.fetchAll,
    required this.balanceForCurrency,
    required this.deleteEntity,
    required this.parseEntity,
    required this.buildAddSheet,
    required this.buildDetailScreen,
    required this.idOf,
    required this.nameOf,
    required this.phoneOf,
    this.cardPhoneIconBuilder,
  });

  // ── Labels ──
  final String title;
  final String entityNoun; // 'عميل' / 'مورد'
  final String entityNounPlural; // 'عملاء' / 'موردين'
  final String deleteEntityTypeLabel; // 'العميل' / 'المورد'
  final String searchHint;
  final String addLabel;
  final String emptyTitleAll;
  final String emptyTitleDebit;
  final String emptyTitleCredit;
  final String emptySubtitleAll;

  // ── Icons ──
  final IconData entityIcon;
  final IconData addIcon;

  // ── Repository callbacks ──
  final Future<List<Map<String, dynamic>>> Function() fetchAll;
  final Future<double> Function(T entity, String currency) balanceForCurrency;
  final Future<dynamic> Function(T entity) deleteEntity;
  final T Function(Map<String, dynamic>) parseEntity;

  // ── Widget factories ──
  final Widget Function() buildAddSheet;
  final Widget Function(T entity) buildDetailScreen;

  // ── Field accessors ──
  final int? Function(T) idOf;
  final String Function(T) nameOf;
  final String? Function(T) phoneOf;

  /// Optional: builds the phone-row icon for the card.
  /// If null, defaults to [Icons.phone].
  /// Suppliers use this to show Icons.chat for WhatsApp contacts.
  final IconData Function(T)? cardPhoneIconBuilder;

  @override
  State<EntitiesScreen<T>> createState() => _EntitiesScreenState<T>();
}

class _EntitiesScreenState<T> extends State<EntitiesScreen<T>>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<T> _entities = [];
  bool _isLoading = true;
  String _selectedCurrency = 'YER';
  bool _isBalancesLoading = false;
  Map<int, double> _currencyBalances = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _searchQuery = _searchController.text.toLowerCase());
        }
      });
    });
    _loadEntities();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntities() async {
    setState(() => _isLoading = true);
    try {
      final results = await widget.fetchAll();
      if (!mounted) return;
      setState(() {
        _entities = results.map(widget.parseEntity).toList();
        _isLoading = false;
      });
      _loadCurrencyBalances();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء تحميل البيانات'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loadCurrencyBalances() async {
    setState(() => _isBalancesLoading = true);
    try {
      final entries = await Future.wait(
        _entities.map((e) async {
          final id = widget.idOf(e);
          if (id == null) return null;
          final balance = await widget.balanceForCurrency(e, _selectedCurrency);
          return MapEntry(id, balance);
        }),
      );
      if (!mounted) return;
      final newBalances = <int, double>{};
      for (final entry in entries) {
        if (entry != null) newBalances[entry.key] = entry.value;
      }
      setState(() {
        _currencyBalances = newBalances;
        _isBalancesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBalancesLoading = false);
    }
  }

  void _onCurrencyChanged(String currency) {
    setState(() => _selectedCurrency = currency);
    _loadCurrencyBalances();
  }

  List<T> _filterEntities(int tabIndex) {
    final q = _searchQuery;
    return _entities.where((e) {
      final name = widget.nameOf(e).toLowerCase();
      final phone = (widget.phoneOf(e) ?? '').toLowerCase();
      if (q.isNotEmpty && !name.contains(q) && !phone.contains(q)) {
        return false;
      }
      if (tabIndex == 1) {
        // مدينون — negative balance (عليه)
        final balance = _currencyBalances[widget.idOf(e)] ?? 0.0;
        return balance < 0;
      } else if (tabIndex == 2) {
        // دائنون — positive balance (له)
        final balance = _currencyBalances[widget.idOf(e)] ?? 0.0;
        return balance > 0;
      }
      return true;
    }).toList();
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => widget.buildAddSheet(),
    ).whenComplete(() {
      if (mounted) _loadEntities();
    });
  }

  Future<void> _deleteEntity(T entity) async {
    final name = widget.nameOf(entity);
    final confirmed = await DeleteHelper.showDeleteConfirmation(
      context: context,
      entityType: widget.deleteEntityTypeLabel,
      entityName: name,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.deleteEntity(entity);
      if (!mounted) return;
      DeleteHelper.showDeleteSuccess(
          context, widget.deleteEntityTypeLabel, name);
      _loadEntities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الحذف: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLight = !isDark;
    final currentSymbol =
        CurrencyConstants.currencyInfo[_selectedCurrency]?['symbol'] ?? 'ر.ي';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                avatar: Icon(Icons.currency_exchange,
                    size: 16, color: AppColors.primary),
                label: Text(
                  '$currentSymbol $_selectedCurrency',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  CurrencyConstants.showCurrencyFilterPopup(
                    context: context,
                    selectedCurrency: _selectedCurrency,
                    onSelected: _onCurrencyChanged,
                  );
                },
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _showAddSheet,
              icon: Icon(widget.addIcon),
              tooltip: widget.addLabel,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: SearchBar(
                      controller: _searchController,
                      hintText: widget.searchHint,
                      leading: const Icon(Icons.search, size: 20),
                      trailing: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isLight
                          ? AppColors.surface
                          : AppColors.darkSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLight
                            ? AppColors.border.withValues(alpha: 0.5)
                            : AppColors.darkBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(widget.entityIcon,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${_entities.length} ${widget.entityNoun}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isLight
                                ? AppColors.textSecondary
                                : AppColors.darkTextSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (_isBalancesLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else ...[
                          Icon(Icons.account_balance_wallet,
                              size: 14,
                              color: isLight
                                  ? AppColors.textHint
                                  : AppColors.darkTextSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'العملة: $_selectedCurrency',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isLight
                                  ? AppColors.textHint
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.calculate,
                              size: 14,
                              color: isLight
                                  ? AppColors.textHint
                                  : AppColors.darkTextSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'الإجمالي: ${CurrencyFormatter.formatValue(_currencyBalances.values.fold(0.0, (a, b) => a + b))} $currentSymbol',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isLight
                                  ? AppColors.textHint
                                  : AppColors.darkTextSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: List.generate(3, (tabIndex) {
                        final filtered = _filterEntities(tabIndex);
                        if (filtered.isEmpty) {
                          return EmptyState(
                            icon: tabIndex == 0
                                ? widget.entityIcon
                                : tabIndex == 1
                                    ? Icons.trending_down
                                    : Icons.trending_up,
                            title: tabIndex == 0
                                ? widget.emptyTitleAll
                                : tabIndex == 1
                                    ? widget.emptyTitleDebit
                                    : widget.emptyTitleCredit,
                            subtitle: tabIndex == 0
                                ? widget.emptySubtitleAll
                                : 'لم يتم العثور على نتائج مطابقة',
                            actionLabel:
                                tabIndex == 0 ? widget.addLabel : null,
                            onAction:
                                tabIndex == 0 ? _showAddSheet : null,
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: _loadEntities,
                          child: ListView.builder(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                                bottom: 80, top: 2),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final entity = filtered[index];
                              final id = widget.idOf(entity);
                              final balance =
                                  _currencyBalances[id] ?? 0.0;
                              final avatarColor =
                                  AvatarHelper.avatarColor(
                                      widget.nameOf(entity));
                              return _EntityCard<T>(
                                entity: entity,
                                name: widget.nameOf(entity),
                                phone: widget.phoneOf(entity),
                                avatarColor: avatarColor,
                                displayBalance: balance,
                                currencySymbol: currentSymbol,
                                isLight: isLight,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          widget.buildDetailScreen(entity),
                                    ),
                                  ).then((_) {
                                    if (mounted) _loadEntities();
                                  });
                                },
                                onDelete: () =>
                                    _deleteEntity(entity),
                                phoneIcon: widget.cardPhoneIconBuilder !=
                                        null
                                    ? widget.cardPhoneIconBuilder!(entity)
                                    : Icons.phone,
                              );
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddSheet,
          tooltip: widget.addLabel,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: Icon(widget.addIcon),
          label: Text(widget.addLabel),
        ),
      ),
    );
  }
}

/// Generic entity card used by [EntitiesScreen].
class _EntityCard<T> extends StatelessWidget {
  const _EntityCard({
    required this.entity,
    required this.name,
    required this.phone,
    required this.avatarColor,
    required this.displayBalance,
    required this.currencySymbol,
    required this.isLight,
    required this.phoneIcon,
    this.onTap,
    this.onDelete,
  });

  final T entity;
  final String name;
  final String? phone;
  final Color avatarColor;
  final double displayBalance;
  final String currencySymbol;
  final bool isLight;
  final IconData phoneIcon;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = !isLight;
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
          color: isLight
              ? AppColors.border.withValues(alpha: 0.5)
              : AppColors.darkBorder.withValues(alpha: 0.5),
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
                      colors: [
                        avatarColor,
                        avatarColor.withValues(alpha: 0.7)
                      ],
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
                      name.isNotEmpty ? name[0] : '?',
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
                        name,
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
                            phoneIcon,
                            size: 13,
                            color: isLight
                                ? AppColors.textHint
                                : AppColors.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone ?? '—',
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

                const SizedBox(width: 8),

                // ── Balance Section ──────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: displayBalance != 0
                          ? [
                              balanceColor.withValues(alpha: 0.12),
                              balanceColor.withValues(alpha: 0.04)
                            ]
                          : [
                              Colors.grey.withValues(alpha: 0.06),
                              Colors.grey.withValues(alpha: 0.02)
                            ],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: displayBalance != 0
                          ? balanceColor.withValues(alpha: 0.25)
                          : AppColors.border.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDebit
                            ? Icons.trending_down
                            : isCredit
                                ? Icons.trending_up
                                : Icons.remove,
                        size: 14,
                        color: displayBalance != 0
                            ? balanceColor
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$balanceAbs $currencySymbol',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: displayBalance != 0
                              ? balanceColor
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // ── PopupMenuButton (UI-09) ──────────────────────
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: isLight
                        ? AppColors.textHint
                        : AppColors.darkTextSecondary,
                  ),
                  tooltip: 'خيارات',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'detail',
                      child: Row(children: [
                        Icon(Icons.visibility, size: 18),
                        SizedBox(width: 8),
                        Text('عرض التفاصيل'),
                      ]),
                    ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete,
                              size: 18, color: AppColors.error),
                          const SizedBox(width: 8),
                          Text('حذف',
                              style:
                                  TextStyle(color: AppColors.error)),
                        ]),
                      ),
                  ],
                  onSelected: (value) {
                    if (value == 'detail' && onTap != null) onTap!();
                    if (value == 'delete' && onDelete != null) onDelete!();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
