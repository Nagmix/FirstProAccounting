import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/expense_model.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, this.expenseId});

  final int? expenseId;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _exchangeRateController = TextEditingController();
  final _beneficiaryController = TextEditingController();
  final _referenceNumberController = TextEditingController();
  final _notesController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCurrency = 'YER';
  double _selectedExchangeRate = 1.0;
  double _amountBase = 0.0;
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String _paymentMethod = 'cash';
  int? _selectedCashBoxId;
  int? _selectedAccountId;
  bool _isRecurring = false;
  String? _recurringPeriod;

  // Data from DB
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  List<Map<String, dynamic>> _expenseAccounts = [];
  bool _isLoading = true;
  bool _isEditing = false;

  Map<String, dynamic>? _existingExpense;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.expenseId != null;
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCurrencies(),
      db.getAllCashBoxes(),
      db.getAccountsByType('EXPENSE'),
    ]);

    setState(() {
      _currencies = results[0];
      _cashBoxes = results[1];
      _expenseAccounts = results[2];
      _isLoading = false;
    });

    // If editing, load existing expense data
    if (_isEditing && widget.expenseId != null) {
      final db2 = DatabaseHelper();
      final expense = await db2.getExpenseById(widget.expenseId!);
      if (expense != null) {
        setState(() {
          _existingExpense = expense;
          _titleController.text = expense['title'] as String? ?? '';
          _descriptionController.text = expense['description'] as String? ?? '';
          _amountController.text = (expense['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '';
          _selectedCurrency = expense['currency'] as String? ?? 'YER';
          _selectedExchangeRate = (expense['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          _exchangeRateController.text = _selectedExchangeRate.toStringAsFixed(4);
          _amountBase = (expense['amount_base'] as num?)?.toDouble() ?? 0.0;
          _selectedCategory = expense['category'] as String?;
          _paymentMethod = expense['payment_method'] as String? ?? 'cash';
          _selectedCashBoxId = expense['cash_box_id'] as int?;
          _selectedAccountId = expense['account_id'] as int?;
          _beneficiaryController.text = expense['beneficiary'] as String? ?? '';
          _referenceNumberController.text = expense['reference_number'] as String? ?? '';
          _notesController.text = expense['notes'] as String? ?? '';
          _isRecurring = (expense['is_recurring'] as int?) == 1;
          _recurringPeriod = expense['recurring_period'] as String?;
          try {
            _selectedDate = DateTime.parse(expense['expense_date'] as String? ?? '');
          } catch (_) {}
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _exchangeRateController.dispose();
    _beneficiaryController.dispose();
    _referenceNumberController.dispose();
    _notesController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _updateAmountBase() {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final rate = double.tryParse(_exchangeRateController.text) ?? _selectedExchangeRate;
    setState(() {
      _amountBase = amount * rate;
    });
  }

  void _onCurrencyChanged(String? code) {
    if (code == null) return;
    setState(() {
      _selectedCurrency = code;
      // Auto-fill exchange rate from currencies table
      final currency = _currencies.where((c) => c['code'] == code).firstOrNull;
      if (currency != null) {
        _selectedExchangeRate = (currency['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        _exchangeRateController.text = _selectedExchangeRate.toStringAsFixed(4);
      }
      _updateAmountBase();
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
          title: Text(_isEditing ? 'تعديل المصروف' : 'إضافة مصروف'),
          actions: [
            IconButton(
              onPressed: _saveExpense,
              icon: const Icon(PhosphorIconsRegular.floppyDisk),
              tooltip: 'حفظ',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitleSection(),
                      const SizedBox(height: 12),
                      _buildAmountSection(),
                      const SizedBox(height: 12),
                      _buildDateSection(),
                      const SizedBox(height: 12),
                      _buildCategorySection(),
                      const SizedBox(height: 12),
                      _buildPaymentMethodSection(),
                      if (_paymentMethod == 'cash' || _paymentMethod == 'transfer') ...[
                        const SizedBox(height: 12),
                        _buildCashBoxSection(),
                      ],
                      const SizedBox(height: 12),
                      _buildExpenseAccountSection(),
                      const SizedBox(height: 12),
                      _buildDetailsSection(),
                      const SizedBox(height: 12),
                      _buildRecurringSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return _buildSectionCard(
      title: 'بيانات المصروف',
      icon: PhosphorIconsRegular.article,
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'العنوان *',
              prefixIcon: Icon(PhosphorIconsRegular.textAa),
              hintText: 'مثال: إيجار المحل',
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'العنوان مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'الوصف',
              prefixIcon: Icon(PhosphorIconsRegular.notepad),
              hintText: 'وصف اختياري للمصروف',
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection() {
    return _buildSectionCard(
      title: 'المبلغ والعملة',
      icon: PhosphorIconsRegular.currencyDollar,
      child: Column(
        children: [
          Row(
            children: [
              // Amount field
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    prefixIcon: Icon(PhosphorIconsRegular.currencyDollar),
                    hintText: '0.00',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'المبلغ مطلوب';
                    if (double.tryParse(v) == null) return 'أدخل رقم صحيح';
                    return null;
                  },
                  onChanged: (_) => _updateAmountBase(),
                ),
              ),
              const SizedBox(width: 10),
              // Currency dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCurrency,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    prefixIcon: Icon(PhosphorIconsRegular.coin),
                  ),
                  items: _currencies.map((c) => DropdownMenuItem<String>(
                    value: c['code'] as String,
                    child: Text(c['code'] as String, style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: _onCurrencyChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Exchange rate
          TextFormField(
            controller: _exchangeRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'سعر الصرف',
              prefixIcon: Icon(PhosphorIconsRegular.arrowsLeftRight),
              hintText: '1.0000',
            ),
            onChanged: (_) {
              _selectedExchangeRate = double.tryParse(_exchangeRateController.text) ?? 1.0;
              _updateAmountBase();
            },
          ),
          const SizedBox(height: 12),
          // Amount in base currency (read-only)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المبلغ بالعملة الأساسية', style: context.textTheme.bodyMedium),
                Text(
                  CurrencyFormatter.format(_amountBase),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    return _buildSectionCard(
      title: 'تاريخ المصروف',
      icon: PhosphorIconsRegular.calendarBlank,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          if (picked != null) setState(() => _selectedDate = picked);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: context.dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.calendarDots, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(dateStr, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(PhosphorIconsRegular.caretLeft, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    return _buildSectionCard(
      title: 'التصنيف',
      icon: PhosphorIconsRegular.tag,
      child: DropdownButtonFormField<String>(
        value: _selectedCategory,
        decoration: const InputDecoration(
          labelText: 'تصنيف المصروف',
          prefixIcon: Icon(PhosphorIconsRegular.tag),
          hintText: 'اختر التصنيف',
        ),
        items: Expense.categoryList.map((e) => DropdownMenuItem<String>(
          value: e.key,
          child: Text(e.value),
        )).toList(),
        onChanged: (val) => setState(() => _selectedCategory = val),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    const methods = [
      ('cash', 'نقدي', PhosphorIconsFill.money, AppColors.success),
      ('check', 'شيك', PhosphorIconsFill.note, AppColors.accentBlue),
      ('transfer', 'حوالة', PhosphorIconsFill.arrowsLeftRight, AppColors.accentOrange),
      ('bank', 'بنك', PhosphorIconsFill.bank, AppColors.primary),
    ];

    return _buildSectionCard(
      title: 'طريقة الدفع',
      icon: PhosphorIconsRegular.creditCard,
      child: Row(
        children: methods.map((m) {
          final selected = _paymentMethod == m.$1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => setState(() => _paymentMethod = m.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? m.$4.withValues(alpha: 0.08) : context.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? m.$4 : context.dividerColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(m.$3, size: 20, color: selected ? m.$4 : AppColors.textHint),
                      const SizedBox(height: 6),
                      Text(
                        m.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? m.$4 : AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCashBoxSection() {
    if (_cashBoxes.isEmpty) return const SizedBox.shrink();
    return _buildSectionCard(
      title: 'صندوق الدفع',
      icon: PhosphorIconsRegular.vault,
      child: DropdownButtonFormField<int>(
        value: _selectedCashBoxId,
        decoration: const InputDecoration(
          hintText: 'اختر الصندوق',
          prefixIcon: Icon(PhosphorIconsRegular.vault),
        ),
        items: _cashBoxes.map((cb) {
          final balance = (cb['balance'] as num?)?.toDouble() ?? 0.0;
          final bt = cb['balance_type'] as String? ?? 'credit';
          return DropdownMenuItem<int>(
            value: cb['id'] as int,
            child: Text('${cb['name']} (${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'})', overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        onChanged: (val) => setState(() => _selectedCashBoxId = val),
      ),
    );
  }

  Widget _buildExpenseAccountSection() {
    if (_expenseAccounts.isEmpty) return const SizedBox.shrink();
    return _buildSectionCard(
      title: 'حساب المصروف',
      icon: PhosphorIconsRegular.chartPie,
      child: DropdownButtonFormField<int>(
        value: _selectedAccountId,
        decoration: const InputDecoration(
          hintText: 'اختر الحساب',
          prefixIcon: Icon(PhosphorIconsRegular.chartPie),
        ),
        items: _expenseAccounts.map((a) => DropdownMenuItem<int>(
          value: a['id'] as int,
          child: Text('${a['account_code']} - ${a['name_ar']}', overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (val) => setState(() => _selectedAccountId = val),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return _buildSectionCard(
      title: 'تفاصيل إضافية',
      icon: PhosphorIconsRegular.notepad,
      child: Column(
        children: [
          TextFormField(
            controller: _beneficiaryController,
            decoration: const InputDecoration(
              labelText: 'المستفيد',
              prefixIcon: Icon(PhosphorIconsRegular.user),
              hintText: 'من استلم الدفع',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _referenceNumberController,
            decoration: const InputDecoration(
              labelText: 'رقم المرجع',
              prefixIcon: Icon(PhosphorIconsRegular.hash),
              hintText: 'رقم الشيك أو الإيصال',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'ملاحظات',
              prefixIcon: Icon(PhosphorIconsRegular.notepad),
              alignLabelWithHint: true,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringSection() {
    return _buildSectionCard(
      title: 'المصروف المتكرر',
      icon: PhosphorIconsRegular.repeat,
      child: Column(
        children: [
          CheckboxListTile(
            value: _isRecurring,
            onChanged: (v) => setState(() {
              _isRecurring = v ?? false;
              if (!_isRecurring) _recurringPeriod = null;
            }),
            title: Text('مصروف متكرر', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            dense: true,
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _recurringPeriod,
              decoration: const InputDecoration(
                labelText: 'فترة التكرار',
                prefixIcon: Icon(PhosphorIconsRegular.repeat),
              ),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('يومي')),
                DropdownMenuItem(value: 'weekly', child: Text('أسبوعي')),
                DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                DropdownMenuItem(value: 'yearly', child: Text('سنوي')),
              ],
              onChanged: (val) => setState(() => _recurringPeriod = val),
              validator: (v) => _isRecurring && v == null ? 'اختر فترة التكرار' : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsRegular.x),
                label: const Text('إلغاء'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _saveExpense,
                icon: const Icon(PhosphorIconsRegular.floppyDisk),
                label: Text(_isEditing ? 'تحديث' : 'حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final exchangeRate = double.tryParse(_exchangeRateController.text) ?? _selectedExchangeRate;
    final amountBase = amount * exchangeRate;
    final now = DateTime.now().toIso8601String();
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    final expenseMap = {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'amount': amount,
      'currency': _selectedCurrency,
      'exchange_rate': exchangeRate,
      'amount_base': amountBase,
      'expense_date': dateStr,
      'category': _selectedCategory,
      'payment_method': _paymentMethod,
      'cash_box_id': _selectedCashBoxId,
      'account_id': _selectedAccountId,
      'beneficiary': _beneficiaryController.text.trim().isEmpty ? null : _beneficiaryController.text.trim(),
      'reference_number': _referenceNumberController.text.trim().isEmpty ? null : _referenceNumberController.text.trim(),
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'is_recurring': _isRecurring ? 1 : 0,
      'recurring_period': _isRecurring ? _recurringPeriod : null,
      'updated_at': now,
    };

    final db = DatabaseHelper();

    if (_isEditing && widget.expenseId != null) {
      await db.updateExpense(widget.expenseId!, expenseMap);
    } else {
      expenseMap['created_at'] = now;
      await db.saveExpenseWithJournalEntry(expenseMap);
    }

    if (mounted) {
      context.showSuccessSnackBar(_isEditing ? 'تم تحديث المصروف بنجاح' : 'تم حفظ المصروف بنجاح');
      Navigator.pop(context, true);
    }
  }
}
