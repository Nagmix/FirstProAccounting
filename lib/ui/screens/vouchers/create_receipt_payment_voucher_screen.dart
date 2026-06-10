import 'package:flutter/material.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/datasources/services/cash_box_service.dart';

/// شاشة إنشاء سندات القبض والصرف
///
/// تدعم إنشاء سند قبض (استلام نقدية) أو سند صرف (دفع نقدية)
/// مع إنشاء القيود المحاسبية تلقائياً في الخلفية.
class CreateReceiptPaymentVoucherScreen extends StatefulWidget {
  /// true = سند قبض، false = سند صرف
  final bool isReceipt;

  const CreateReceiptPaymentVoucherScreen({
    super.key,
    this.isReceipt = true,
  });

  @override
  State<CreateReceiptPaymentVoucherScreen> createState() =>
      _CreateReceiptPaymentVoucherScreenState();
}

class _CreateReceiptPaymentVoucherScreenState
    extends State<CreateReceiptPaymentVoucherScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _entitySearchController = TextEditingController();

  // ── State ────────────────────────────────────────────────────────
  bool _isReceipt = true;
  String _selectedCurrency = 'YER';
  DateTime _selectedDate = DateTime.now();
  int? _selectedCashBoxId;
  Map<String, dynamic>? _selectedEntity;
  String _selectedEntityFilter = 'all';

  // ── Data ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allEntities = [];
  List<Map<String, dynamic>> _filteredEntities = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // ── Animation ────────────────────────────────────────────────────
  late AnimationController _typeAnimController;
  late Animation<Color?> _typeColorAnimation;

  // ── Entity filter chips ──────────────────────────────────────────
  static const _entityFilterOptions = [
    {'key': 'all', 'label': 'الكل'},
    {'key': VoucherAutoMappingService.entityCustomer, 'label': 'عملاء'},
    {'key': VoucherAutoMappingService.entitySupplier, 'label': 'موردين'},
    {'key': VoucherAutoMappingService.entityEmployee, 'label': 'موظفين'},
    {'key': VoucherAutoMappingService.entityExpense, 'label': 'مصروفات'},
  ];

  // ── Currency data (loaded from DB) ───────────────────────────────
  List<Map<String, dynamic>> _currencies = [];

  /// جلب رمز العملة من القائمة الديناميكية
  String _getCurrencySymbol(String code) {
    final currency = _currencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => <String, dynamic>{'symbol': code},
    );
    return currency['symbol'] as String? ?? code;
  }

  // ════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _isReceipt = widget.isReceipt;

    _typeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _typeColorAnimation = ColorTween(
      begin: _isReceipt ? AppColors.success : AppColors.error,
      end: _isReceipt ? AppColors.success : AppColors.error,
    ).animate(CurvedAnimation(
      parent: _typeAnimController,
      curve: Curves.easeInOut,
    ));
    _typeAnimController.value = 1.0;

    _entitySearchController.addListener(_filterEntities);
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _entitySearchController.dispose();
    _typeAnimController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  //  Data Loading
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final autoMappingService = locator<VoucherAutoMappingService>();
      final cashBoxService = locator<CashBoxService>();
      final refRepo = locator<ReferenceDataRepository>();

      final results = await Future.wait([
        autoMappingService.getAllEntities(),
        cashBoxService.getAllCashBoxes(),
        refRepo.getAllCurrencies(),
      ]);

      if (!mounted) return;

      setState(() {
        _allEntities = results[0];
        _cashBoxes = results[1];
        _currencies = results[2];
        _isLoading = false;
        _applyEntityFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ أثناء تحميل البيانات';
      });
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  Entity Filtering
  // ════════════════════════════════════════════════════════════════

  void _applyEntityFilter() {
    List<Map<String, dynamic>> result = _allEntities;

    // Filter by entity type
    if (_selectedEntityFilter != 'all') {
      result = result.where((e) => e['type'] == _selectedEntityFilter).toList();
    }

    // Filter by search query
    final query = _entitySearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((e) {
        final name = (e['name'] as String? ?? '').toLowerCase();
        return name.contains(query);
      }).toList();
    }

    _filteredEntities = result;
  }

  void _filterEntities() {
    setState(() {
      _applyEntityFilter();
    });
  }

  void _onEntityFilterChanged(String filterKey) {
    setState(() {
      _selectedEntityFilter = filterKey;
      _selectedEntity = null;
      _applyEntityFilter();
    });
  }

  // ════════════════════════════════════════════════════════════════
  //  Cash Box Filtering
  // ════════════════════════════════════════════════════════════════

  // Cash boxes are currency-agnostic — show all boxes, don't filter by currency
  List<Map<String, dynamic>> get _filteredCashBoxes {
    return _cashBoxes;
  }

  // ════════════════════════════════════════════════════════════════
  //  Operation Type Toggle
  // ════════════════════════════════════════════════════════════════

  void _toggleOperationType(bool isReceipt) {
    if (_isReceipt == isReceipt) return;
    setState(() {
      _isReceipt = isReceipt;
      _typeColorAnimation = ColorTween(
        begin: _typeColorAnimation.value,
        end: isReceipt ? AppColors.success : AppColors.error,
      ).animate(CurvedAnimation(
        parent: _typeAnimController,
        curve: Curves.easeInOut,
      ));
      _typeAnimController.forward(from: 0.0);
    });
  }

  // ════════════════════════════════════════════════════════════════
  //  Currency
  // ════════════════════════════════════════════════════════════════

  void _onCurrencyChanged(String currency) {
    setState(() {
      _selectedCurrency = currency;
      _selectedCashBoxId = null; // Reset cash box when currency changes
    });
  }

  // ════════════════════════════════════════════════════════════════
  //  Date Picker
  // ════════════════════════════════════════════════════════════════

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

  // ════════════════════════════════════════════════════════════════
  //  Validation & Save
  // ════════════════════════════════════════════════════════════════

  bool _validate() {
    if (_selectedEntity == null) {
      context.showErrorSnackBar('يرجى اختيار اسم الحساب');
      return false;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      context.showErrorSnackBar('يرجى إدخال مبلغ صحيح أكبر من صفر');
      return false;
    }

    if (_filteredCashBoxes.isEmpty) {
      context.showErrorSnackBar('لا يوجد صندوق بالعملة المحددة');
      return false;
    }

    if (_selectedCashBoxId == null) {
      context.showErrorSnackBar('يرجى اختيار حساب الصندوق');
      return false;
    }

    return true;
  }

  Future<void> _saveVoucher() async {
    if (!_validate()) return;

    setState(() => _isSaving = true);

    try {
      final autoMappingService = locator<VoucherAutoMappingService>();

      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
      // B-1/A-5: store a FULL timestamp (selected day + current time) so
      // chronological sorting and running balances work across all
      // movement types. Day-only storage broke ordering vs full timestamps.
      final dateStr = DateFormatter.storageTimestamp(_selectedDate);
      final entityId = (_selectedEntity!['id'] as num?)?.toInt() ?? 0;
      final entityAccountId = (_selectedEntity!['account_id'] as num?)?.toInt();

      await autoMappingService.createReceiptPaymentVoucher(
        voucherType: _isReceipt ? 'receipt' : 'payment',
        entityType: _selectedEntity!['type'] as String,
        entityId: entityId,
        entityAccountId: entityAccountId,
        cashBoxId: _selectedCashBoxId,
        amount: amount,
        currency: _selectedCurrency,
        date: dateStr,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isReceipt ? 'تم حفظ سند القبض بنجاح' : 'تم حفظ سند الصرف بنجاح',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Clear form for next voucher entry instead of popping
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.isNotEmpty ? msg : 'حدث خطأ أثناء الحفظ'),
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

  /// Clear the form after successful save to prepare for next voucher entry.
  void _clearForm() {
    _descriptionController.clear();
    _amountController.clear();
    _entitySearchController.clear();
    setState(() {
      _selectedEntity = null;
      _selectedCashBoxId = null;
      _selectedDate = DateTime.now();
      _selectedEntityFilter = 'all';
    });
    _applyEntityFilter();
  }

  // ════════════════════════════════════════════════════════════════
  //  Helpers
  // ════════════════════════════════════════════════════════════════

  Color get _typeColor => _isReceipt ? AppColors.success : AppColors.error;

  String get _title => _isReceipt ? 'سند قبض' : 'سند صرف';

  String _getEntityTypeName(String? type) {
    if (type == null) return '';
    return VoucherAutoMappingService.entityTypeLabelsAr[type] ?? type;
  }

  IconData _getEntityTypeIcon(String? type) {
    switch (type) {
      case VoucherAutoMappingService.entityCustomer:
        return Icons.person;
      case VoucherAutoMappingService.entitySupplier:
        return Icons.local_shipping;
      case VoucherAutoMappingService.entityEmployee:
        return Icons.badge;
      case VoucherAutoMappingService.entityExpense:
        return Icons.receipt_long;
      default:
        return Icons.category;
    }
  }

  String _formatBalance(dynamic balance, String? balanceType) {
    final amount = MoneyHelper.readMoney(balance);
    if (amount == 0.0) return '';
    final typeLabel = balanceType == 'debit' ? 'عليه' : 'له';
    final symbol = _getCurrencySymbol(_selectedCurrency);
    return '$typeLabel ${CurrencyFormatter.formatValue(amount)} $symbol';
  }

  String _formatCashBoxBalance(Map<String, dynamic> cb) {
    final balance = MoneyHelper.readMoney(cb['balance']);
    // Cash box is currency-agnostic; use selected currency symbol for display
    final symbol = _getCurrencySymbol(_selectedCurrency);
    return '${CurrencyFormatter.formatValue(balance)} $symbol';
  }

  // ════════════════════════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _title,
              key: ValueKey(_isReceipt),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveVoucher,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'حفظ',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
        body: _isLoading
            ? _buildLoadingState()
            : _errorMessage != null
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: 100 + bottomPadding,
                      ),
                      children: [
                        // ── Operation Type Toggle ──────────────────
                        _buildOperationTypeToggle(theme, isDark),
                        const SizedBox(height: 24),

                        // ── Entity Name (اسم الحساب) ──────────────
                        _buildSectionTitle(theme, 'اسم الحساب'),
                        const SizedBox(height: 10),
                        _buildEntityFilterChips(theme, isDark),
                        const SizedBox(height: 10),
                        _buildEntitySearchBar(theme, isDark),
                        const SizedBox(height: 10),
                        _buildEntityDropdown(theme, isDark),
                        const SizedBox(height: 24),

                        // ── Fund Account (حساب الصندوق) ───────────
                        _buildSectionTitle(theme, 'حساب الصندوق'),
                        const SizedBox(height: 10),
                        _buildCashBoxDropdown(theme, isDark),
                        const SizedBox(height: 24),

                        // ── Date (التاريخ) ───────────────────────
                        _buildSectionTitle(theme, 'التاريخ'),
                        const SizedBox(height: 10),
                        _buildDatePicker(theme, isDark),
                        const SizedBox(height: 24),

                        // ── Description (البيان) ──────────────────
                        _buildSectionTitle(theme, 'البيان'),
                        const SizedBox(height: 10),
                        _buildDescriptionField(theme, isDark),
                        const SizedBox(height: 24),

                        // ── Amount & Currency ─────────────────────
                        _buildSectionTitle(theme, 'المبلغ والعملة'),
                        const SizedBox(height: 10),
                        _buildCurrencySelector(theme, isDark),
                        const SizedBox(height: 12),
                        _buildAmountField(theme, isDark),
                        const SizedBox(height: 32),

                        // ── Save Button ───────────────────────────
                        _buildSaveButton(theme, isDark),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Loading & Error States
  // ════════════════════════════════════════════════════════════════

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _typeColor),
          const SizedBox(height: 16),
          Text(
            'جاري تحميل البيانات...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ غير متوقع',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _typeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Section Title
  // ════════════════════════════════════════════════════════════════

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _typeAnimController,
          builder: (context, child) {
            return Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: _typeColorAnimation.value ?? _typeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        AnimatedBuilder(
          animation: _typeAnimController,
          builder: (context, child) {
            return Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _typeColorAnimation.value ?? _typeColor,
              ),
            );
          },
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Operation Type Toggle (صرف / قبض)
  // ════════════════════════════════════════════════════════════════

  Widget _buildOperationTypeToggle(ThemeData theme, bool isDark) {
    return AnimatedBuilder(
      animation: _typeAnimController,
      builder: (context, child) {
        final animatedColor = _typeColorAnimation.value ?? _typeColor;

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: animatedColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // ── سند قبض ──
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleOperationType(true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isReceipt
                          ? AppColors.success.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _isReceipt
                          ? Border.all(color: AppColors.success, width: 2)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                          color: _isReceipt
                              ? AppColors.success
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'قبض',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                _isReceipt ? FontWeight.w700 : FontWeight.w500,
                            color: _isReceipt
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // ── سند صرف ──
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleOperationType(false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isReceipt
                          ? AppColors.error.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: !_isReceipt
                          ? Border.all(color: AppColors.error, width: 2)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: !_isReceipt
                              ? AppColors.error
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'صرف',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                !_isReceipt ? FontWeight.w700 : FontWeight.w500,
                            color: !_isReceipt
                                ? AppColors.error
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
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Entity Filter Chips
  // ════════════════════════════════════════════════════════════════

  Widget _buildEntityFilterChips(ThemeData theme, bool isDark) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _entityFilterOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = _entityFilterOptions[index];
          final key = option['key'] as String;
          final label = option['label'] as String;
          final isSelected = _selectedEntityFilter == key;

          return GestureDetector(
            onTap: () => _onEntityFilterChanged(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? _typeColor.withValues(alpha: 0.12)
                    : isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? Border.all(color: _typeColor, width: 1.5)
                    : Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.divider,
                      ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? _typeColor
                        : isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Entity Search Bar
  // ════════════════════════════════════════════════════════════════

  Widget _buildEntitySearchBar(ThemeData theme, bool isDark) {
    return TextField(
      controller: _entitySearchController,
      decoration: InputDecoration(
        hintText: 'بحث عن حساب...',
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
          fontSize: 13,
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        ),
        suffixIcon: _entitySearchController.text.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
                onPressed: () {
                  _entitySearchController.clear();
                },
              )
            : null,
        filled: true,
        fillColor:
            isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _typeColor, width: 1.5),
        ),
      ),
      style: TextStyle(fontSize: 13),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Entity Dropdown
  // ════════════════════════════════════════════════════════════════

  Widget _buildEntityDropdown(ThemeData theme, bool isDark) {
    // Compute effective selected ID, ensuring it exists in the filtered list
    int? selectedId;
    if (_selectedEntity != null) {
      final id = (_selectedEntity!['id'] as num?)?.toInt();
      if (id != null &&
          _filteredEntities.any((e) => (e['id'] as num?)?.toInt() == id)) {
        selectedId = id;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.divider,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: selectedId,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              _filteredEntities.isEmpty ? 'لا توجد حسابات' : 'اختر الحساب',
              style: TextStyle(
                color:
                    isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                fontSize: 14,
              ),
            ),
          ),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          icon: Icon(
            Icons.arrow_drop_down,
            color:
                isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
          items: _filteredEntities.map((entity) {
            final id = (entity['id'] as num?)?.toInt();
            final name = entity['name'] as String? ?? '';
            final type = entity['type'] as String? ?? '';
            final balance = entity['balance'];
            final balanceType = entity['balance_type'] as String?;
            final typeName = _getEntityTypeName(type);
            final icon = _getEntityTypeIcon(type);
            final balanceStr = _formatBalance(balance, balanceType);

            return DropdownMenuItem<int?>(
              value: id,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: _typeColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (typeName.isNotEmpty)
                          Text(
                            typeName,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (balanceStr.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (balanceType == 'debit'
                                ? AppColors.error
                                : AppColors.success)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        balanceStr,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: balanceType == 'debit'
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val == null) {
              setState(() => _selectedEntity = null);
              return;
            }
            final entity = _filteredEntities.firstWhere(
              (e) => (e['id'] as num?)?.toInt() == val,
              orElse: () => <String, dynamic>{},
            );
            setState(() {
              _selectedEntity = entity.isNotEmpty ? entity : null;
            });
          },
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Cash Box Dropdown
  // ════════════════════════════════════════════════════════════════

  Widget _buildCashBoxDropdown(ThemeData theme, bool isDark) {
    final filtered = _filteredCashBoxes;

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warningLight.withValues(alpha: isDark ? 0.1 : 1.0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'لا يوجد صندوق بالعملة المحددة (${_getCurrencySymbol(_selectedCurrency)})',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Ensure selected cash box is valid for the current currency
    // If not, treat as null to avoid DropdownButton assertion error
    int? effectiveCashBoxId = _selectedCashBoxId;
    if (effectiveCashBoxId != null &&
        !filtered
            .any((cb) => (cb['id'] as num?)?.toInt() == effectiveCashBoxId)) {
      effectiveCashBoxId = null;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.divider,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: effectiveCashBoxId,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'اختر حساب الصندوق',
              style: TextStyle(
                color:
                    isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                fontSize: 14,
              ),
            ),
          ),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          icon: Icon(
            Icons.arrow_drop_down,
            color:
                isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
          items: filtered.map((cb) {
            final id = (cb['id'] as num?)?.toInt();
            final name = cb['name'] as String? ?? '';
            final balanceStr = _formatCashBoxBalance(cb);
            final cbType = cb['type'] as String? ?? '';
            final isBank = cbType == 'bank';

            return DropdownMenuItem<int?>(
              value: id,
              child: Row(
                children: [
                  Icon(
                    isBank
                        ? Icons.account_balance
                        : Icons.account_balance_wallet,
                    size: 18,
                    color: _typeColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          isBank ? 'بنك' : 'صندوق',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      balanceStr,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() => _selectedCashBoxId = val);
          },
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Date Picker
  // ════════════════════════════════════════════════════════════════

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
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: _typeColor, size: 20),
            const SizedBox(width: 12),
            Text(
              _selectedDate.toIso8601String().split('T').first,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_drop_down,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Description Field
  // ════════════════════════════════════════════════════════════════

  Widget _buildDescriptionField(ThemeData theme, bool isDark) {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: 'أدخل البيان (اختياري)...',
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
          fontSize: 13,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Icon(
            Icons.description_outlined,
            color: _typeColor,
            size: 20,
          ),
        ),
        filled: true,
        fillColor:
            isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _typeColor, width: 1.5),
        ),
      ),
      style: TextStyle(
        fontSize: 14,
        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Currency Selector (Segmented Control)
  // ════════════════════════════════════════════════════════════════

  Widget _buildCurrencySelector(ThemeData theme, bool isDark) {
    // قائمة منسدلة احترافية مع العملات من قاعدة البيانات
    return DropdownButtonFormField<String>(
      value: _currencies.any((c) => c['code'] == _selectedCurrency)
          ? _selectedCurrency
          : null,
      decoration: InputDecoration(
        labelText: 'العملة',
        prefixIcon: Icon(Icons.currency_exchange, size: 20, color: _typeColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        if (val != null) _onCurrencyChanged(val);
      },
      isExpanded: true,
      icon: Icon(Icons.arrow_drop_down, color: _typeColor),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Amount Field
  // ════════════════════════════════════════════════════════════════

  Widget _buildAmountField(ThemeData theme, bool isDark) {
    final symbol = _getCurrencySymbol(_selectedCurrency);

    return TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: _typeColor,
      ),
      decoration: InputDecoration(
        hintText: '0.00',
        hintStyle: TextStyle(
          color: AppColors.textHint.withValues(alpha: 0.4),
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Center(
            widthFactor: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                symbol,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _typeColor,
                ),
              ),
            ),
          ),
        ),
        filled: true,
        fillColor:
            isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _typeColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  Save Button
  // ════════════════════════════════════════════════════════════════

  Widget _buildSaveButton(ThemeData theme, bool isDark) {
    return AnimatedBuilder(
      animation: _typeAnimController,
      builder: (context, child) {
        final buttonColor = _typeColorAnimation.value ?? _typeColor;

        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveVoucher,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isReceipt
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                  ),
            label: Text(
              _isSaving
                  ? 'جاري الحفظ...'
                  : _isReceipt
                      ? 'حفظ سند القبض'
                      : 'حفظ سند الصرف',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: buttonColor.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
          ),
        );
      },
    );
  }
}
