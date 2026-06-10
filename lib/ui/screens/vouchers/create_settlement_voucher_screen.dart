import 'package:flutter/material.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/repositories/account_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/voucher_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/models/account_model.dart';

/// واجهة إنشاء سندات التسوية والتسوية المزدوجة
/// هذه الواجهة تتعامل مباشرة مع حسابات شجرة المحاسبة
/// وهي مخصصة للمحاسبين لضبط الأرصدة وتسوية الحسابات
///
/// الفرق بين التسوية العادية والمزدوجة:
/// - سند تسوية: قيد بسيط بين حسابين (مدين واحد، دائن واحد)
/// - سند مزدوج: قيد متعدد البنود (عدة مدين ودائن)
class CreateSettlementVoucherScreen extends StatefulWidget {
  final bool isCompound;
  const CreateSettlementVoucherScreen({super.key, this.isCompound = false});

  @override
  State<CreateSettlementVoucherScreen> createState() =>
      _CreateSettlementVoucherScreenState();
}

class _CreateSettlementVoucherScreenState
    extends State<CreateSettlementVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _selectedCurrency = 'YER';
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _filteredAccounts = [];
  List<Map<String, dynamic>> _currencies = [];
  List<_SettlementLineItem> _lineItems = [_SettlementLineItem()];
  bool _isSaving = false;
  // ignore: unused_field
  bool _isSearching = false;
  bool _isLoading = true;

  // حقول التسوية البسيطة
  int? _debitAccountId;
  int? _creditAccountId;
  final _amountController = TextEditingController();

  Color get _accentColor =>
      widget.isCompound ? AppColors.secondary : AppColors.info;

  String get _title => widget.isCompound ? 'سند تسوية مزدوج' : 'سند تسوية';
  String get _subtitle => widget.isCompound
      ? 'قيد متعدد البنود بين حسابات شجرة المحاسبة'
      : 'قيد تسوية بسيط بين حسابين في شجرة المحاسبة';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _searchController.dispose();
    _amountController.dispose();
    for (final item in _lineItems) {
      item.debitController.dispose();
      item.creditController.dispose();
      item.descriptionController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final accountRepo = locator<AccountRepository>();
      final refRepo = locator<ReferenceDataRepository>();
      final results = await Future.wait([
        accountRepo.getAllAccounts(),
        refRepo.getAllCurrencies(),
      ]);
      if (mounted) {
        setState(() {
          _accounts =
              (results[0]).where((a) => (a['is_active'] as int?) == 1).toList();
          _currencies = results[1];
          _isLoading = false;
          _filterAccounts();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        context.showErrorSnackBar('حدث خطأ أثناء تحميل البيانات');
      }
    }
  }

  void _filterAccounts() {
    final query = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> result = _accounts;

    // فلترة حسب العملة
    result = result.where((a) => a['currency'] == _selectedCurrency).toList();

    // فلترة حسب البحث
    if (query.isNotEmpty) {
      result = result.where((a) {
        final name = (a['name_ar'] as String? ?? '').toLowerCase();
        final code = (a['account_code'] as String? ?? '').toLowerCase();
        return name.contains(query) || code.contains(query);
      }).toList();
    }

    // ترتيب حسب كود الحساب
    result.sort((a, b) => (a['account_code'] as String? ?? '')
        .compareTo(b['account_code'] as String? ?? ''));

    setState(() {
      _filteredAccounts = result;
    });
  }

  double get _totalDebit {
    if (!widget.isCompound) {
      return double.tryParse(_amountController.text) ?? 0.0;
    }
    double total = 0.0;
    for (final item in _lineItems) {
      total += double.tryParse(item.debitController.text) ?? 0.0;
    }
    return total;
  }

  double get _totalCredit {
    if (!widget.isCompound) {
      return double.tryParse(_amountController.text) ?? 0.0;
    }
    double total = 0.0;
    for (final item in _lineItems) {
      total += double.tryParse(item.creditController.text) ?? 0.0;
    }
    return total;
  }

  bool get _isBalanced => (_totalDebit - _totalCredit).abs() < 0.01;

  String _getCurrencySymbol(String code) {
    final currency = _currencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => <String, dynamic>{'symbol': code},
    );
    return currency['symbol'] as String? ?? code;
  }

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

  void _addLineItem() {
    setState(() {
      _lineItems.add(_SettlementLineItem());
    });
  }

  void _removeLineItem(int index) {
    if (_lineItems.length <= 1) return;
    setState(() {
      _lineItems[index].debitController.dispose();
      _lineItems[index].creditController.dispose();
      _lineItems[index].descriptionController.dispose();
      _lineItems.removeAt(index);
    });
  }

  Future<void> _saveVoucher() async {
    // التحقق من صحة البيانات
    if (widget.isCompound) {
      // التحقق من وجود بنود بمبالغ
      if (_lineItems.every((item) =>
          (double.tryParse(item.debitController.text) ?? 0.0) == 0 &&
          (double.tryParse(item.creditController.text) ?? 0.0) == 0)) {
        context.showErrorSnackBar('يجب إضافة بند واحد على الأقل بمبلغ');
        return;
      }

      // التحقق من اختيار الحسابات
      for (int i = 0; i < _lineItems.length; i++) {
        final item = _lineItems[i];
        if (item.accountId == null &&
            ((double.tryParse(item.debitController.text) ?? 0.0) > 0 ||
                (double.tryParse(item.creditController.text) ?? 0.0) > 0)) {
          context.showErrorSnackBar('يجب اختيار حساب للبند ${i + 1}');
          return;
        }
      }

      if (!_isBalanced) {
        context.showErrorSnackBar('يجب أن يتساوى مجموع المدين مع مجموع الدائن');
        return;
      }
    } else {
      // التحقق من التسوية البسيطة
      if (_debitAccountId == null) {
        context.showErrorSnackBar('يجب اختيار الحساب المدين');
        return;
      }
      if (_creditAccountId == null) {
        context.showErrorSnackBar('يجب اختيار الحساب الدائن');
        return;
      }
      if (_debitAccountId == _creditAccountId) {
        context
            .showErrorSnackBar('لا يمكن أن يكون الحساب المدين والدائن واحداً');
        return;
      }
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      if (amount <= 0) {
        context.showErrorSnackBar('يجب إدخال مبلغ صحيح');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final voucherType = widget.isCompound ? 'compound' : 'settlement';
      final voucherNumber =
          await locator<CashBoxService>().getNextVoucherNumber(voucherType);
      final now = DateTime.now().toIso8601String();
      // B-1/A-5: store a FULL timestamp (selected day + current time) so
      // chronological sorting and running balances work across all
      // movement types. Day-only storage broke ordering vs full timestamps.
      final dateStr = DateFormatter.storageTimestamp(_selectedDate);

      final voucherMap = {
        'voucher_number': voucherNumber,
        'voucher_type': voucherType,
        'date': dateStr,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'currency': _selectedCurrency,
        'total_amount': _totalDebit,
        'cash_box_id': null, // سندات التسوية لا تتعلق بصندوق
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      };

      final items = <Map<String, dynamic>>[];

      if (widget.isCompound) {
        // بنود متعددة
        for (final item in _lineItems) {
          if (item.accountId != null) {
            items.add({
              'account_id': item.accountId,
              'debit': double.tryParse(item.debitController.text) ?? 0.0,
              'credit': double.tryParse(item.creditController.text) ?? 0.0,
              'description': item.descriptionController.text.trim().isEmpty
                  ? null
                  : item.descriptionController.text.trim(),
            });
          }
        }
      } else {
        // تسوية بسيطة: بند مدين + بند دائن
        final amount = double.tryParse(_amountController.text) ?? 0.0;
        final desc = _descriptionController.text.trim().isEmpty
            ? 'سند تسوية'
            : _descriptionController.text.trim();

        items.add({
          'account_id': _debitAccountId,
          'debit': amount,
          'credit': 0.0,
          'description': desc,
        });
        items.add({
          'account_id': _creditAccountId,
          'debit': 0.0,
          'credit': amount,
          'description': desc,
        });
      }

      await locator<VoucherRepository>()
          .saveVoucherWithJournalEntry(voucherMap, items);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ سند التسوية بنجاح'),
            backgroundColor: AppColors.info,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: ${e.toString()}'),
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
    _descriptionController.clear();
    _searchController.clear();
    _amountController.clear();
    for (final item in _lineItems) {
      item.debitController.clear();
      item.creditController.clear();
      item.descriptionController.clear();
    }
    setState(() {
      _debitAccountId = null;
      _creditAccountId = null;
      _selectedDate = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveVoucher,
              icon: const Icon(Icons.save, color: Colors.white),
              label: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 100 + bottomPadding),
                  children: [
                    // عنوان فرعي
                    _buildInfoCard(theme, isDark),
                    const SizedBox(height: 20),

                    // التاريخ والعملة
                    Row(
                      children: [
                        Expanded(child: _buildDatePicker(theme, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildCurrencySelector(theme, isDark)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // الوصف
                    _buildSectionTitle(theme, 'البيان'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: 'وصف سند التسوية...',
                        prefixIcon: const Icon(Icons.description),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),

                    // محتوى القيد
                    if (widget.isCompound)
                      _buildCompoundView(theme, isDark)
                    else
                      _buildSimpleView(theme, isDark),

                    const SizedBox(height: 16),

                    // المجاميع
                    _buildTotalsCard(theme, isDark),

                    const SizedBox(height: 24),

                    // زر الحفظ
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveVoucher,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(
                            _isSaving ? 'جاري الحفظ...' : 'حفظ سند التسوية'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: _accentColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
              color: _accentColor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: _accentColor)),
      ],
    );
  }

  Widget _buildDatePicker(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, 'التاريخ'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: _accentColor, size: 20),
                const SizedBox(width: 12),
                Text(_selectedDate.toIso8601String().split('T').first,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencySelector(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, 'العملة'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _currencies.any((c) => c['code'] == _selectedCurrency)
              ? _selectedCurrency
              : null,
          decoration: InputDecoration(
            prefixIcon:
                Icon(Icons.currency_exchange, size: 20, color: _accentColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(nameAr,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12))),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedCurrency = val;
                _debitAccountId = null;
                _creditAccountId = null;
                for (final item in _lineItems) {
                  item.accountId = null;
                }
              });
              _filterAccounts();
            }
          },
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: _accentColor),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  واجهة التسوية البسيطة
  // ══════════════════════════════════════════════════════════════
  Widget _buildSimpleView(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الحساب المدين
        _buildSectionTitle(theme, 'الحساب المدين'),
        const SizedBox(height: 4),
        Text('يزيد رصيد هذا الحساب',
            style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _buildAccountDropdown(
          theme: theme,
          isDark: isDark,
          selectedId: _debitAccountId,
          hintText: 'اختر الحساب المدين',
          prefixIcon: Icons.add_circle_outline,
          onChanged: (val) => setState(() => _debitAccountId = val),
        ),
        const SizedBox(height: 20),

        // سهم تحويل
        Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.swap_vert, color: _accentColor, size: 28),
          ),
        ),
        const SizedBox(height: 20),

        // الحساب الدائن
        _buildSectionTitle(theme, 'الحساب الدائن'),
        const SizedBox(height: 4),
        Text('ينقص رصيد هذا الحساب',
            style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.success, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _buildAccountDropdown(
          theme: theme,
          isDark: isDark,
          selectedId: _creditAccountId,
          hintText: 'اختر الحساب الدائن',
          prefixIcon: Icons.remove_circle_outline,
          onChanged: (val) => setState(() => _creditAccountId = val),
        ),
        const SizedBox(height: 20),

        // المبلغ
        _buildSectionTitle(theme, 'المبلغ'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'أدخل المبلغ',
            prefixIcon: const Icon(Icons.attach_money),
            suffixText: _getCurrencySymbol(_selectedCurrency),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildAccountDropdown({
    required ThemeData theme,
    required bool isDark,
    required int? selectedId,
    required String hintText,
    required IconData prefixIcon,
    required ValueChanged<int?> onChanged,
  }) {
    // التأكد من أن القيمة المختارة موجودة في القائمة
    final validItems = _filteredAccounts
        .map((acc) => (acc['id'] as num?)?.toInt() ?? 0)
        .toList();
    final safeValue = (selectedId != null && validItems.contains(selectedId))
        ? selectedId
        : null;

    return DropdownButtonFormField<int>(
      value: safeValue,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _filteredAccounts.map((acc) {
        final name = acc['name_ar'] as String? ?? '';
        final code = acc['account_code'] as String? ?? '';
        final type = acc['account_type'] as String? ?? '';
        final typeAr = Account.accountTypeAr(
          AccountType.values.firstWhere((e) => e.name == type,
              orElse: () => AccountType.ASSET),
        );
        return DropdownMenuItem<int>(
          value: (acc['id'] as num?)?.toInt(),
          child: Row(
            children: [
              Text('$code',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('$name',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(typeAr,
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  واجهة التسوية المزدوجة
  // ══════════════════════════════════════════════════════════════
  Widget _buildCompoundView(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle(theme, 'بنود القيد'),
            const Spacer(),
            IconButton(
              onPressed: _addLineItem,
              icon: Icon(Icons.add_circle, color: _accentColor),
              tooltip: 'إضافة بند',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('بند ${index + 1}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _accentColor,
                        )),
                    const Spacer(),
                    if (_lineItems.length > 1)
                      IconButton(
                        onPressed: () => _removeLineItem(index),
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error, size: 20),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // اختيار الحساب
                _buildAccountDropdown(
                  theme: theme,
                  isDark: isDark,
                  selectedId: item.accountId,
                  hintText: 'اختر الحساب',
                  prefixIcon: Icons.pie_chart,
                  onChanged: (val) => setState(() => item.accountId = val),
                ),
                const SizedBox(height: 8),

                // مدين ودائن
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item.debitController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'مدين',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: item.creditController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'دائن',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: item.descriptionController,
                  decoration: InputDecoration(
                    hintText: 'وصف البند (اختياري)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTotalsCard(ThemeData theme, bool isDark) {
    final isBalanced = _isBalanced;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isBalanced
            ? AppColors.success.withOpacity(0.06)
            : AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBalanced
              ? AppColors.success.withOpacity(0.2)
              : AppColors.error.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجمالي المدين',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(_totalDebit,
                          symbol: _getCurrencySymbol(_selectedCurrency)),
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800, color: AppColors.error),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجمالي الدائن',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(_totalCredit,
                          symbol: _getCurrencySymbol(_selectedCurrency)),
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(isBalanced ? Icons.check_circle : Icons.error,
                  color: isBalanced ? AppColors.success : AppColors.error,
                  size: 20),
              const SizedBox(width: 8),
              Text(
                isBalanced
                    ? 'القيد متوازن'
                    : 'القيد غير متوازن - الفرق: ${CurrencyFormatter.format((_totalDebit - _totalCredit).abs(), symbol: _getCurrencySymbol(_selectedCurrency))}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isBalanced ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettlementLineItem {
  int? accountId;
  final TextEditingController debitController = TextEditingController();
  final TextEditingController creditController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
}
