import 'package:flutter/material.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';

/// شاشة إنشاء قيد عام (من حساب → إلى حساب)
/// القيد المحاسبي: "من حساب" = دائن (يعطي قيمة)، "إلى حساب" = مدين (يستقبل قيمة)
class CreateGeneralEntryScreen extends StatefulWidget {
  const CreateGeneralEntryScreen({super.key});

  @override
  State<CreateGeneralEntryScreen> createState() =>
      _CreateGeneralEntryScreenState();
}

class _CreateGeneralEntryScreenState extends State<CreateGeneralEntryScreen> {
  // ── Controllers ─────────────────────────────────────────────────
  final _fromAmountController = TextEditingController();
  final _toAmountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _fromSearchController = TextEditingController();
  final _toSearchController = TextEditingController();

  // ── State ───────────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  String _fromCurrency = 'YER';
  String _toCurrency = 'YER';

  Map<String, dynamic>? _fromEntity;
  Map<String, dynamic>? _toEntity;
  String _fromEntityTypeFilter = 'all';
  String _toEntityTypeFilter = 'all';

  List<Map<String, dynamic>> _allEntities = [];
  List<Map<String, dynamic>> _currencies = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Entity type filter options ──────────────────────────────────
  static const _entityTypeFilters = [
    {'value': 'all', 'label': 'الكل', 'icon': Icons.apps},
    {
      'value': VoucherAutoMappingService.entityCustomer,
      'label': 'عملاء',
      'icon': Icons.person
    },
    {
      'value': VoucherAutoMappingService.entitySupplier,
      'label': 'موردين',
      'icon': Icons.local_shipping
    },
    {
      'value': VoucherAutoMappingService.entityEmployee,
      'label': 'موظفين',
      'icon': Icons.badge
    },
    {
      'value': VoucherAutoMappingService.entityExpense,
      'label': 'مصروفات',
      'icon': Icons.receipt_long
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadEntities();
  }

  @override
  void dispose() {
    _fromAmountController.dispose();
    _toAmountController.dispose();
    _descriptionController.dispose();
    _fromSearchController.dispose();
    _toSearchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  Data Loading
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadEntities() async {
    try {
      final autoMappingService = locator<VoucherAutoMappingService>();
      final refRepo = locator<ReferenceDataRepository>();
      final results = await Future.wait([
        autoMappingService.getAllEntities(),
        refRepo.getAllCurrencies(),
      ]);
      if (mounted) {
        setState(() {
          _allEntities = results[0];
          _currencies = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        context.showErrorSnackBar('حدث خطأ أثناء تحميل البيانات');
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredEntities(
      String typeFilter, String searchText) {
    var filtered = _allEntities;

    // Filter by entity type
    if (typeFilter != 'all') {
      filtered = filtered.where((e) => e['type'] == typeFilter).toList();
    }

    // Filter by search text
    if (searchText.trim().isNotEmpty) {
      final query = searchText.trim().toLowerCase();
      filtered = filtered.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        return name.contains(query);
      }).toList();
    }

    return filtered;
  }

  // ═══════════════════════════════════════════════════════════════
  //  Date Picker
  // ═══════════════════════════════════════════════════════════════

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Entity Selection Bottom Sheet
  // ═══════════════════════════════════════════════════════════════

  Future<void> _showEntityPicker({
    required bool isFrom,
    required Color accentColor,
  }) async {
    final searchController =
        isFrom ? _fromSearchController : _toSearchController;
    final selectedEntity = isFrom ? _fromEntity : _toEntity;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredEntities = _getFilteredEntities(
              isFrom ? _fromEntityTypeFilter : _toEntityTypeFilter,
              searchController.text,
            );

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                padding: const EdgeInsets.only(
                    top: 8, left: 16, right: 16, bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.textHint.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Title
                    Text(
                      isFrom
                          ? 'اختر الحساب المصدر (من)'
                          : 'اختر الحساب الوجهة (إلى)',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Entity type filter chips
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _entityTypeFilters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final filter = _entityTypeFilters[index];
                          final currentFilter = isFrom
                              ? _fromEntityTypeFilter
                              : _toEntityTypeFilter;
                          final isSelected = currentFilter == filter['value'];

                          return ChoiceChip(
                            label: Text(filter['label'] as String),
                            avatar: Icon(filter['icon'] as IconData, size: 16),
                            selected: isSelected,
                            selectedColor: accentColor.withValues(alpha: 0.15),
                            side: BorderSide(
                              color:
                                  isSelected ? accentColor : AppColors.divider,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? accentColor
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  if (isFrom) {
                                    _fromEntityTypeFilter =
                                        filter['value'] as String;
                                  } else {
                                    _toEntityTypeFilter =
                                        filter['value'] as String;
                                  }
                                });
                                setModalState(() {});
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search field
                    TextField(
                      controller: searchController,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchController.clear();
                                  setModalState(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Entity list
                    Flexible(
                      child: filteredEntities.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48,
                                      color:
                                          AppColors.textHint.withValues(alpha: 0.5)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'لا توجد نتائج',
                                    style: TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredEntities.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, index) {
                                final entity = filteredEntities[index];
                                final isSelected = selectedEntity != null &&
                                    selectedEntity['id'] == entity['id'] &&
                                    selectedEntity['type'] == entity['type'];
                                final entityType =
                                    entity['type'] as String? ?? '';
                                final entityName =
                                    entity['name'] as String? ?? '';
                                final balance =
                                    (entity['balance'] as num?)?.toDouble() ??
                                        0.0;
                                final balanceType =
                                    entity['balance_type'] as String? ??
                                        'debit';
                                final currency =
                                    entity['currency'] as String? ?? 'YER';

                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isFrom) {
                                        _fromEntity = entity;
                                        if (currency.isNotEmpty) {
                                          _fromCurrency = currency;
                                        }
                                      } else {
                                        _toEntity = entity;
                                        if (currency.isNotEmpty) {
                                          _toCurrency = currency;
                                        }
                                      }
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? accentColor.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isSelected
                                          ? Border.all(
                                              color: accentColor, width: 1.5)
                                          : Border.all(
                                              color: AppColors.divider
                                                  .withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        _buildEntityTypeIcon(
                                            entityType, accentColor),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entityName,
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _getEntityTypeLabel(entityType),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (balance != 0.0 &&
                                            entityType !=
                                                VoucherAutoMappingService
                                                    .entityExpense)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: balanceType == 'debit'
                                                  ? AppColors.error
                                                      .withValues(alpha: 0.08)
                                                  : AppColors.success
                                                      .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _formatBalance(balance,
                                                  balanceType, currency),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: balanceType == 'debit'
                                                    ? AppColors.error
                                                    : AppColors.success,
                                              ),
                                            ),
                                          ),
                                        if (isSelected)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 4),
                                            child: Icon(Icons.check_circle,
                                                color: accentColor, size: 20),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Clear search after closing
    searchController.clear();
  }

  Widget _buildEntityTypeIcon(String type, Color color) {
    IconData icon;
    switch (type) {
      case VoucherAutoMappingService.entityCustomer:
        icon = Icons.person;
        break;
      case VoucherAutoMappingService.entitySupplier:
        icon = Icons.local_shipping;
        break;
      case VoucherAutoMappingService.entityEmployee:
        icon = Icons.badge;
        break;
      case VoucherAutoMappingService.entityExpense:
        icon = Icons.receipt_long;
        break;
      default:
        icon = Icons.circle;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  String _getEntityTypeLabel(String type) {
    return VoucherAutoMappingService.entityTypeLabelsAr[type] ?? type;
  }

  String _formatBalance(double balance, String balanceType, String currency) {
    final symbol = _getCurrencySymbol(currency);
    if (balanceType == 'debit') {
      return '${CurrencyFormatter.formatValue(balance)} $symbol عليه';
    } else {
      return '${CurrencyFormatter.formatValue(balance)} $symbol له';
    }
  }

  String _getCurrencySymbol(String code) {
    final currency = _currencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => <String, dynamic>{'symbol': code},
    );
    return currency['symbol'] as String? ?? code;
  }

  // ═══════════════════════════════════════════════════════════════
  //  Validation & Save
  // ═══════════════════════════════════════════════════════════════

  bool _validate() {
    if (_fromEntity == null) {
      context.showErrorSnackBar('يجب اختيار الحساب المصدر (من حساب)');
      return false;
    }
    if (_toEntity == null) {
      context.showErrorSnackBar('يجب اختيار الحساب الوجهة (إلى حساب)');
      return false;
    }

    final fromAmount = double.tryParse(_fromAmountController.text) ?? 0.0;
    final toAmount = double.tryParse(_toAmountController.text) ?? 0.0;

    if (fromAmount <= 0) {
      context.showErrorSnackBar('يجب إدخال مبلغ صحيح للحساب المصدر');
      return false;
    }
    if (toAmount <= 0) {
      context.showErrorSnackBar('يجب إدخال مبلغ صحيح للحساب الوجهة');
      return false;
    }

    // Check same entity selected for both sides
    if (_fromEntity!['id'] == _toEntity!['id'] &&
        _fromEntity!['type'] == _toEntity!['type']) {
      context.showErrorSnackBar('لا يمكن تحويل من وإلى نفس الحساب');
      return false;
    }

    return true;
  }

  Future<void> _saveGeneralEntry() async {
    if (!_validate()) return;

    setState(() => _isSaving = true);

    try {
      final autoMappingService = locator<VoucherAutoMappingService>();

      final fromAmount = double.tryParse(_fromAmountController.text) ?? 0.0;
      final toAmount = double.tryParse(_toAmountController.text) ?? 0.0;
      // B-1/A-5: store a FULL timestamp (selected day + current time) so
      // chronological sorting and running balances work across all
      // movement types. Day-only storage broke ordering vs full timestamps.
      final dateStr = DateFormatter.storageTimestamp(_selectedDate);

      await autoMappingService.createGeneralEntry(
        fromEntityType: _fromEntity!['type'] as String,
        fromEntityId: (_fromEntity!['id'] as num?)?.toInt() ?? 0,
        fromEntityAccountId: (_fromEntity!['account_id'] as num?)?.toInt(),
        fromAmount: fromAmount,
        fromCurrency: _fromCurrency,
        toEntityType: _toEntity!['type'] as String,
        toEntityId: (_toEntity!['id'] as num?)?.toInt() ?? 0,
        toEntityAccountId: (_toEntity!['account_id'] as num?)?.toInt(),
        toAmount: toAmount,
        toCurrency: _toCurrency,
        date: dateStr,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ القيد العام بنجاح'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().contains('لم يتم العثور')
            ? e.toString().replaceAll('Exception: ', '')
            : 'حدث خطأ أثناء الحفظ';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Clear the form after successful save to prepare for next entry.
  void _clearForm() {
    _fromAmountController.clear();
    _toAmountController.clear();
    _descriptionController.clear();
    _fromSearchController.clear();
    _toSearchController.clear();
    setState(() {
      _fromEntity = null;
      _toEntity = null;
      _selectedDate = DateTime.now();
      _fromEntityTypeFilter = 'all';
      _toEntityTypeFilter = 'all';
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قيد عام'),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveGeneralEntry,
              icon: const Icon(Icons.save, color: Colors.white),
              label: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 100 + bottomPadding,
                ),
                children: [
                  // ── Date Section ──────────────────────────────────
                  _buildSectionTitle(theme, 'التاريخ', AppColors.primary),
                  const SizedBox(height: 8),
                  _buildDatePicker(theme, isDark),
                  const SizedBox(height: 24),

                  // ── From Account Section (Orange) ─────────────────
                  _buildAccountSection(
                    theme: theme,
                    isDark: isDark,
                    title: 'من حساب',
                    subtitle: 'دائن — يعطي القيمة',
                    accentColor: AppColors.secondary,
                    entity: _fromEntity,
                    entityTypeFilter: _fromEntityTypeFilter,
                    amountController: _fromAmountController,
                    currency: _fromCurrency,
                    onCurrencyChanged: (c) => setState(() => _fromCurrency = c),
                    onEntityTypeFilterChanged: (f) =>
                        setState(() => _fromEntityTypeFilter = f),
                    onEntityTap: () => _showEntityPicker(
                        isFrom: true, accentColor: AppColors.secondary),
                    onClearEntity: () => setState(() => _fromEntity = null),
                  ),

                  const SizedBox(height: 16),

                  // ── Transfer Arrow ────────────────────────────────
                  _buildTransferArrow(theme, isDark),

                  const SizedBox(height: 16),

                  // ── To Account Section (Blue) ─────────────────────
                  _buildAccountSection(
                    theme: theme,
                    isDark: isDark,
                    title: 'إلى حساب',
                    subtitle: 'مدين — يستقبل القيمة',
                    accentColor: AppColors.info,
                    entity: _toEntity,
                    entityTypeFilter: _toEntityTypeFilter,
                    amountController: _toAmountController,
                    currency: _toCurrency,
                    onCurrencyChanged: (c) => setState(() => _toCurrency = c),
                    onEntityTypeFilterChanged: (f) =>
                        setState(() => _toEntityTypeFilter = f),
                    onEntityTap: () => _showEntityPicker(
                        isFrom: false, accentColor: AppColors.info),
                    onClearEntity: () => setState(() => _toEntity = null),
                  ),

                  const SizedBox(height: 24),

                  // ── Description Section ───────────────────────────
                  _buildSectionTitle(
                      theme, 'التفاصيل', AppColors.textSecondary),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      hintText: 'وصف القيد...',
                      prefixIcon: const Icon(Icons.description_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                    minLines: 2,
                  ),

                  const SizedBox(height: 32),

                  // ── Save Button ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveGeneralEntry,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label:
                          Text(_isSaving ? 'جاري الحفظ...' : 'حفظ القيد العام'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  UI Builders
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSectionTitle(ThemeData theme, String title, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: accentColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(ThemeData theme, bool isDark) {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:
              isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              _selectedDate.toIso8601String().split('T').first,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Map<String, dynamic>? entity,
    required String entityTypeFilter,
    required TextEditingController amountController,
    required String currency,
    required ValueChanged<String> onCurrencyChanged,
    required ValueChanged<String> onEntityTypeFilterChanged,
    required VoidCallback onEntityTap,
    required VoidCallback onClearEntity,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  title == 'من حساب'
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Entity type filter chips (compact)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _entityTypeFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, index) {
                final filter = _entityTypeFilters[index];
                final isSelected = entityTypeFilter == filter['value'];

                return ChoiceChip(
                  label: Text(
                    filter['label'] as String,
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: isSelected,
                  selectedColor: accentColor.withValues(alpha: 0.15),
                  side: BorderSide(
                    color: isSelected ? accentColor : AppColors.divider,
                    width: isSelected ? 1.5 : 1,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? accentColor : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (selected) {
                    if (selected) {
                      onEntityTypeFilterChanged(filter['value'] as String);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Entity selector
          _buildEntitySelector(
            theme: theme,
            isDark: isDark,
            entity: entity,
            accentColor: accentColor,
            onTap: onEntityTap,
            onClear: onClearEntity,
          ),
          const SizedBox(height: 12),

          // Amount & Currency row
          Row(
            children: [
              // Amount field
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Currency selector
              Expanded(
                flex: 2,
                child: _buildCurrencyDropdown(
                  theme: theme,
                  isDark: isDark,
                  selectedCurrency: currency,
                  accentColor: accentColor,
                  onChanged: onCurrencyChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntitySelector({
    required ThemeData theme,
    required bool isDark,
    required Map<String, dynamic>? entity,
    required Color accentColor,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final hasEntity = entity != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: hasEntity
              ? accentColor.withValues(alpha: 0.05)
              : (isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasEntity ? accentColor.withValues(alpha: 0.3) : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            if (hasEntity) ...[
              _buildEntityTypeIcon(
                  entity['type'] as String? ?? '', accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entity['name'] as String? ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _getEntityTypeLabel(entity['type'] as String? ?? ''),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        // Show balance for non-expense entities
                        if (entity['type'] !=
                            VoucherAutoMappingService.entityExpense) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (entity['balance_type'] == 'debit'
                                      ? AppColors.error
                                      : AppColors.success)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _formatBalance(
                                (entity['balance'] as num?)?.toDouble() ?? 0.0,
                                entity['balance_type'] as String? ?? 'debit',
                                entity['currency'] as String? ?? 'YER',
                              ),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: entity['balance_type'] == 'debit'
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: AppColors.textHint,
              ),
            ] else ...[
              Icon(Icons.search, color: AppColors.textHint, size: 20),
              const SizedBox(width: 10),
              Text(
                'اختر الحساب...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textHint,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_drop_down, color: AppColors.textHint),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown({
    required ThemeData theme,
    required bool isDark,
    required String selectedCurrency,
    required Color accentColor,
    required ValueChanged<String> onChanged,
  }) {
    // استخدام قائمة منسدلة احترافية مع العملات من قاعدة البيانات
    return DropdownButtonFormField<String>(
      value: _currencies.any((c) => c['code'] == selectedCurrency)
          ? selectedCurrency
          : null,
      decoration: InputDecoration(
        labelText: 'العملة',
        prefixIcon: Icon(Icons.currency_exchange, size: 20, color: accentColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      items: _currencies.map((c) {
        final code = c['code'] as String? ?? '';
        final symbol = c['symbol'] as String? ?? code;
        final nameAr = c['name_ar'] as String? ?? code;
        return DropdownMenuItem<String>(
          value: code,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(symbol,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(nameAr,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
      isExpanded: true,
      icon: Icon(Icons.arrow_drop_down, color: accentColor),
    );
  }

  Widget _buildTransferArrow(ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color:
              isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.swap_vert,
          color: AppColors.primary,
          size: 24,
        ),
      ),
    );
  }
}
