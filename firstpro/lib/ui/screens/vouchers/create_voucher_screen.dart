import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Transaction;
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/datasources/database_helper.dart';

class CreateVoucherScreen extends StatefulWidget {
  final String? initialType;
  final int? initialSupplierId;

  const CreateVoucherScreen({super.key, this.initialType, this.initialSupplierId});

  @override
  State<CreateVoucherScreen> createState() => _CreateVoucherScreenState();
}

class _CreateVoucherScreenState extends State<CreateVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  String _selectedType = 'receipt';
  DateTime _selectedDate = DateTime.now();
  String _selectedCurrency = 'YER';
  int? _selectedCashBoxId;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  List<_VoucherLineItem> _lineItems = [_VoucherLineItem()];
  bool _isSaving = false;
  List<Map<String, dynamic>> _filteredAccounts = [];
  bool _isSearching = false;

  static const _voucherTypes = [
    {'value': 'receipt', 'label': 'سند قبض', 'icon': Icons.arrow_downward},
    {'value': 'payment', 'label': 'سند صرف', 'icon': Icons.arrow_upward},
    {'value': 'settlement', 'label': 'سند تسوية', 'icon': Icons.swap_horiz},
    {'value': 'compound', 'label': 'سند مزدوج', 'icon': Icons.compare_arrows},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _selectedType = widget.initialType!;
    }
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _searchController.dispose();
    for (final item in _lineItems) {
      item.debitController.dispose();
      item.creditController.dispose();
      item.descriptionController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final accounts = await db.getAllAccounts();
    final cashBoxes = await db.getAllCashBoxes();
    setState(() {
      _accounts = accounts.where((a) => (a['is_active'] as int?) == 1).toList();
      _cashBoxes = cashBoxes.where((c) => (c['is_active'] as int?) == 1).toList();
      _filteredAccounts = _accounts;
    });
  }

  String _getTitle() {
    switch (_selectedType) {
      case 'receipt':
        return 'سند قبض';
      case 'payment':
        return 'سند صرف';
      case 'settlement':
        return 'سند تسوية';
      case 'compound':
        return 'سند مزدوج';
      default:
        return 'سند جديد';
    }
  }

  Color _getTypeColor() {
    switch (_selectedType) {
      case 'receipt':
        return AppColors.success;
      case 'payment':
        return AppColors.error;
      case 'settlement':
        return AppColors.info;
      case 'compound':
        return AppColors.accentOrange;
      default:
        return AppColors.primary;
    }
  }

  double get _totalDebit {
    double total = 0.0;
    for (final item in _lineItems) {
      total += double.tryParse(item.debitController.text) ?? 0.0;
    }
    return total;
  }

  double get _totalCredit {
    double total = 0.0;
    for (final item in _lineItems) {
      total += double.tryParse(item.creditController.text) ?? 0.0;
    }
    return total;
  }

  bool get _isBalanced => (_totalDebit - _totalCredit).abs() < 0.01;

  void _addLineItem() {
    setState(() {
      _lineItems.add(_VoucherLineItem());
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

  Future<void> _saveVoucher() async {
    // التحقق من صحة البيانات
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

    setState(() => _isSaving = true);

    try {
      final dbHelper = DatabaseHelper();
      final voucherNumber = await dbHelper.getNextVoucherNumber(_selectedType);
      final now = DateTime.now().toIso8601String();
      final totalAmount = _totalDebit;
      final dateStr = _selectedDate.toIso8601String().split('T').first;

      final voucherMap = {
        'voucher_number': voucherNumber,
        'voucher_type': _selectedType,
        'date': dateStr,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'currency': _selectedCurrency,
        'total_amount': totalAmount,
        'cash_box_id': _selectedCashBoxId,
        'supplier_id': widget.initialSupplierId,
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      };

      final items = <Map<String, dynamic>>[];
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

      // إنشاء السند مع القيود اليومية وتحديث الأرصدة في معاملة واحدة
      await _saveVoucherWithJournalEntries(voucherMap, items);

      if (mounted) {
        context.showSuccessSnackBar('تم حفظ السند بنجاح');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('حدث خطأ أثناء الحفظ: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// حفظ السند مع إنشاء قيود يومية وتحديث أرصدة الحسابات والصندوق
  Future<void> _saveVoucherWithJournalEntries(
    Map<String, dynamic> voucherMap,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await DatabaseHelper().database;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;
    final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';
    final totalAmount = (voucherMap['total_amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = voucherMap['date'] as String? ?? now;

    await db.transaction((txn) async {
      // 1. إدراج السند
      final voucherId = await txn.insert('vouchers', voucherMap);

      // 2. إدراج بنود السند وإنشاء قيود يومية لكل بند وتحديث رصيد الحساب
      for (final item in items) {
        final itemMap = Map<String, dynamic>.from(item);
        itemMap['voucher_id'] = voucherId;
        itemMap['created_at'] = now;
        await txn.insert('voucher_items', itemMap);

        // إنشاء قيد يومي لكل بند
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
        if (accountId != null && (debit > 0 || credit > 0)) {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': debit,
            'credit': credit,
            'description': item['description'] ?? voucherMap['description'] ?? 'سند ${voucherMap['voucher_number']}',
            'date': dateStr,
            'created_at': now,
          });

          // تحديث رصيد الحساب
          await _updateAccountBalance(txn, accountId, debit, credit, now);
        }
      }

      // 3. تحديث رصيد الصندوق للسندات من نوع قبض أو صرف
      final cashBoxId = voucherMap['cash_box_id'];
      if (cashBoxId != null && totalAmount > 0 &&
          (voucherType == 'receipt' || voucherType == 'payment')) {
        if (voucherType == 'receipt') {
          // سند قبض: زيادة رصيد الصندوق
          await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [totalAmount, now, cashBoxId],
          );
        } else if (voucherType == 'payment') {
          // سند صرف: نقص رصيد الصندوق
          await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [totalAmount, now, cashBoxId],
          );
        }
      }
    });
  }

  /// تحديث رصيد الحساب باستخدام منطق المدين والدائن
  /// المدين يزيد حسابات الأصول والتكاليف والمصاريف
  /// الدائن يزيد حسابات الخصوم والإيرادات
  Future<void> _updateAccountBalance(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final accountRow = await txn.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (accountRow.isEmpty) return;

    final account = accountRow.first;
    final accountType = account['account_type'] as String? ?? '';
    // حسابات الأصول والتكاليف والمصاريف: طبيعتها مدينة
    // حسابات الخصوم والإيرادات: طبيعتها دائنة
    final effectiveType =
        (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE')
            ? 'debit'
            : 'credit';

    double currentBalance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    if (effectiveType == 'debit') {
      currentBalance = currentBalance + debit - credit;
    } else {
      currentBalance = currentBalance + credit - debit;
    }

    await txn.update(
      'accounts',
      {'balance': currentBalance, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [accountId],
    );
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
          title: Text(_getTitle()),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveVoucher,
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
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 100 + bottomPadding,
            ),
            children: [
              // نوع السند
              _buildSectionTitle(theme, 'نوع السند'),
              const SizedBox(height: 8),
              _buildVoucherTypeSelector(theme, isDark),
              const SizedBox(height: 20),

              // التاريخ
              _buildSectionTitle(theme, 'التاريخ'),
              const SizedBox(height: 8),
              _buildDatePicker(theme, isDark),
              const SizedBox(height: 20),

              // العملة
              _buildSectionTitle(theme, 'العملة'),
              const SizedBox(height: 8),
              _buildCurrencySelector(theme, isDark),
              const SizedBox(height: 20),

              // الصندوق (اختياري)
              if (_selectedType == 'receipt' || _selectedType == 'payment') ...[
                _buildSectionTitle(theme, 'الصندوق (اختياري)'),
                const SizedBox(height: 8),
                _buildCashBoxDropdown(theme, isDark),
                const SizedBox(height: 20),
              ],

              // الوصف
              _buildSectionTitle(theme, 'الوصف'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: 'وصف السند...',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // بنود السند
              Row(
                children: [
                  _buildSectionTitle(theme, 'بنود السند'),
                  const Spacer(),
                  IconButton(
                    onPressed: _addLineItem,
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    tooltip: 'إضافة بند',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // جدول البنود
              ..._buildLineItems(theme, isDark),

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
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ السند'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getTypeColor(),
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
            color: _getTypeColor(),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: _getTypeColor(),
          ),
        ),
      ],
    );
  }

  Widget _buildVoucherTypeSelector(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: _voucherTypes.map((type) {
          final isSelected = _selectedType == type['value'];
          final color = _getTypeColorForType(type['value'] as String);
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = type['value'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: color, width: 2) : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      type['icon'] as IconData,
                      size: 18,
                      color: isSelected ? color : AppColors.textHint,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? color : AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getTypeColorForType(String type) {
    switch (type) {
      case 'receipt':
        return AppColors.success;
      case 'payment':
        return AppColors.error;
      case 'settlement':
        return AppColors.info;
      case 'compound':
        return AppColors.accentOrange;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildDatePicker(ThemeData theme, bool isDark) {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              _selectedDate.toIso8601String().split('T').first,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySelector(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildCurrencyOption('YER', 'ر.ي', theme, isDark),
          _buildCurrencyOption('SAR', 'ر.س', theme, isDark),
          _buildCurrencyOption('USD', r'$', theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCurrencyOption(String code, String symbol, ThemeData theme, bool isDark) {
    final isSelected = _selectedCurrency == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCurrency = code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Center(
            child: Text(
              '$code ($symbol)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCashBoxDropdown(ThemeData theme, bool isDark) {
    return DropdownButtonFormField<int?>(
      value: _selectedCashBoxId,
      decoration: InputDecoration(
        hintText: 'اختر الصندوق',
        prefixIcon: const Icon(Icons.account_balance_wallet),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('بدون صندوق')),
        ..._cashBoxes.map((cb) => DropdownMenuItem<int?>(
              value: (cb['id'] as num?)?.toInt(),
              child: Text('${cb['name']} (${cb['currency'] ?? 'YER'})'),
            )),
      ],
      onChanged: (val) => setState(() => _selectedCashBoxId = val),
    );
  }

  List<Widget> _buildLineItems(ThemeData theme, bool isDark) {
    return List.generate(_lineItems.length, (index) {
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
            // عنوان البند مع زر الحذف
            Row(
              children: [
                Text(
                  'بند ${index + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _getTypeColor(),
                  ),
                ),
                const Spacer(),
                if (_lineItems.length > 1)
                  IconButton(
                    onPressed: () => _removeLineItem(index),
                    icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                    tooltip: 'حذف البند',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // اختيار الحساب
            DropdownButtonFormField<int>(
              value: item.accountId,
              decoration: InputDecoration(
                hintText: 'اختر الحساب',
                prefixIcon: const Icon(Icons.pie_chart, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              items: _accounts.map((acc) {
                final name = acc['name_ar'] as String? ?? '';
                final code = acc['account_code'] as String? ?? '';
                return DropdownMenuItem<int>(
                  value: (acc['id'] as num?)?.toInt(),
                  child: Text('$code - $name', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) => setState(() => item.accountId = val),
            ),
            const SizedBox(height: 8),

            // مدين ودائن
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.debitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'مدين',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.creditController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'دائن',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // وصف البند
            TextFormField(
              controller: item.descriptionController,
              decoration: InputDecoration(
                hintText: 'وصف البند (اختياري)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTotalsCard(ThemeData theme, bool isDark) {
    final isBalanced = _isBalanced;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isBalanced
            ? AppColors.success.withValues(alpha: 0.06)
            : AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBalanced
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.2),
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
                    Text(
                      'إجمالي المدين',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(_totalDebit),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجمالي الدائن',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(_totalCredit),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.accentOrange,
                      ),
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
              Icon(
                isBalanced ? Icons.check_circle : Icons.error,
                color: isBalanced ? AppColors.success : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isBalanced ? 'السند متوازن ✓' : 'السند غير متوازن - الفرق: ${CurrencyFormatter.format((_totalDebit - _totalCredit).abs())}',
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

class _VoucherLineItem {
  int? accountId;
  final TextEditingController debitController = TextEditingController();
  final TextEditingController creditController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
}
