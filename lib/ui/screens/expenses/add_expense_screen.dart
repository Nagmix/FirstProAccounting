import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Transaction;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';

class AddExpenseScreen extends StatefulWidget {
  final int? expenseId;
  final int? expenseAccountId;

  const AddExpenseScreen({super.key, this.expenseId, this.expenseAccountId});

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

  String _selectedCurrency = 'YER';
  double _selectedExchangeRate = 1.0;
  double _amountBase = 0.0;
  DateTime _selectedDate = DateTime.now();
  int? _selectedCashBoxId;
  bool _isRecurring = false;
  String? _recurringPeriod;

  // New fields
  String _operationType = 'صرف'; // 'صرف' or 'قبض'
  String? _attachmentPath;

  // Data from DB
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _cashBoxes = [];
  bool _isLoading = true;
  bool _isEditing = false;

  Map<String, dynamic>? _existingExpense; // Stored for reversing old journal entries on edit

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
    ]);

    setState(() {
      _currencies = results[0];
      _cashBoxes = results[1];
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
          _amountController.text = (expense['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '';
          _selectedCurrency = expense['currency'] as String? ?? 'YER';
          _selectedExchangeRate = (expense['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          _exchangeRateController.text = _selectedExchangeRate.toStringAsFixed(4);
          _amountBase = (expense['amount_base'] as num?)?.toDouble() ?? 0.0;
          _selectedCashBoxId = expense['cash_box_id'] as int?;
          _beneficiaryController.text = expense['beneficiary'] as String? ?? '';
          _referenceNumberController.text = expense['reference_number'] as String? ?? '';
          _notesController.text = expense['notes'] as String? ?? '';
          _isRecurring = (expense['is_recurring'] as int?) == 1;
          _recurringPeriod = expense['recurring_period'] as String?;
          _operationType = expense['operation_type'] as String? ?? 'صرف';
          _attachmentPath = expense['attachment_path'] as String?;
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
      final currency = _currencies.where((c) => c['code'] == code).firstOrNull;
      if (currency != null) {
        _selectedExchangeRate = (currency['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        _exchangeRateController.text = _selectedExchangeRate.toStringAsFixed(4);
      }
      _updateAmountBase();
    });
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked.path);
      if (savedPath != null) {
        setState(() => _attachmentPath = savedPath);
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) {
      final savedPath = await _saveImageLocally(picked.path);
      if (savedPath != null) {
        setState(() => _attachmentPath = savedPath);
      }
    }
  }

  Future<String?> _saveImageLocally(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final attachmentsDir = p.join(dir.path, 'attachments');
      await Directory(attachmentsDir).create(recursive: true);
      final fileName = 'expense_${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';
      final destPath = p.join(attachmentsDir, fileName);
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل المصروف' : 'إضافة مصروف'),
          actions: [
            IconButton(
              onPressed: _saveExpense,
              icon: const Icon(Icons.save),
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
                      _buildAttachmentSection(),
                      const SizedBox(height: 12),
                      _buildAmountSection(),
                      const SizedBox(height: 12),
                      _buildCashBoxSection(),
                      const SizedBox(height: 12),
                      _buildDateSection(),
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
      icon: Icons.article,
      child: TextFormField(
        controller: _titleController,
        decoration: const InputDecoration(
          labelText: 'العنوان *',
          prefixIcon: Icon(Icons.text_fields),
          hintText: 'مثال: إيجار المحل',
        ),
        validator: (v) => v == null || v.trim().isEmpty ? 'العنوان مطلوب' : null,
      ),
    );
  }

  Widget _buildAttachmentSection() {
    return _buildSectionCard(
      title: 'إرفاق صورة أو مرفق',
      icon: Icons.attach_file,
      child: Column(
        children: [
          if (_attachmentPath != null) ...[
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.dividerColor),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_attachmentPath!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 32, color: AppColors.textHint),
                            const SizedBox(height: 8),
                            Text(
                              p.basename(_attachmentPath!),
                              style: context.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _attachmentPath = null),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImageFromGallery,
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('رفع من المعرض'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImageFromCamera,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('تصوير بالكاميرا'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection() {
    return _buildSectionCard(
      title: 'المبلغ والعملة',
      icon: Icons.attach_money,
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
                    prefixIcon: Icon(Icons.attach_money),
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
                    prefixIcon: Icon(Icons.monetization_on),
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
              prefixIcon: Icon(Icons.swap_horiz),
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
              color: AppColors.primary.withOpacity(0.06),
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

  Widget _buildCashBoxSection() {
    return _buildSectionCard(
      title: 'الصندوق ونوع العملية',
      icon: Icons.account_balance_wallet,
      child: Column(
        children: [
          // Cash box dropdown
          DropdownButtonFormField<int>(
            value: _selectedCashBoxId,
            decoration: const InputDecoration(
              labelText: 'الصندوق',
              prefixIcon: Icon(Icons.account_balance_wallet),
              hintText: 'اختر الصندوق',
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
          const SizedBox(height: 12),
          // Operation type: قبض or صرف
          Text(
            'نوع العملية',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // صرف (disburse) - عليه (debit)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _operationType = 'صرف'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _operationType == 'صرف'
                          ? AppColors.error.withOpacity(0.08)
                          : context.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _operationType == 'صرف' ? AppColors.error : context.dividerColor,
                        width: _operationType == 'صرف' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.north_west,
                          size: 22,
                          color: _operationType == 'صرف' ? AppColors.error : AppColors.textHint,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'صرف',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _operationType == 'صرف' ? FontWeight.w700 : FontWeight.w500,
                            color: _operationType == 'صرف' ? AppColors.error : AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '(عليه)',
                          style: TextStyle(
                            fontSize: 10,
                            color: _operationType == 'صرف' ? AppColors.error : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // قبض (receive) - له (credit)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _operationType = 'قبض'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _operationType == 'قبض'
                          ? AppColors.success.withOpacity(0.08)
                          : context.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _operationType == 'قبض' ? AppColors.success : context.dividerColor,
                        width: _operationType == 'قبض' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.south_east,
                          size: 22,
                          color: _operationType == 'قبض' ? AppColors.success : AppColors.textHint,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'قبض',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _operationType == 'قبض' ? FontWeight.w700 : FontWeight.w500,
                            color: _operationType == 'قبض' ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '(له)',
                          style: TextStyle(
                            fontSize: 10,
                            color: _operationType == 'قبض' ? AppColors.success : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    return _buildSectionCard(
      title: 'تاريخ المصروف',
      icon: Icons.calendar_today,
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
              Icon(Icons.event, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(dateStr, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.arrow_back_ios, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return _buildSectionCard(
      title: 'تفاصيل إضافية',
      icon: Icons.edit_note,
      child: Column(
        children: [
          TextFormField(
            controller: _beneficiaryController,
            decoration: const InputDecoration(
              labelText: 'المستفيد',
              prefixIcon: Icon(Icons.person),
              hintText: 'من استلم الدفع',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _referenceNumberController,
            decoration: const InputDecoration(
              labelText: 'رقم المرجع',
              prefixIcon: Icon(Icons.tag),
              hintText: 'رقم الشيك أو الإيصال',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'ملاحظات',
              prefixIcon: Icon(Icons.edit_note),
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
      icon: Icons.repeat,
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
                prefixIcon: Icon(Icons.repeat),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('إلغاء'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _saveExpense,
                icon: const Icon(Icons.save),
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

    // Determine the expense account based on currency
    final codeOffset = _selectedCurrency == 'SAR' ? 1 : (_selectedCurrency == 'USD' ? 2 : 0);
    final db = DatabaseHelper();

    // Get the system expense account for this currency
    final expenseAccounts = await db.getAccountsByType('EXPENSE');
    int? systemExpenseAccountId;
    for (final acc in expenseAccounts) {
      if (acc['account_code'] == (5000 + codeOffset).toString() && acc['currency'] == _selectedCurrency) {
        systemExpenseAccountId = acc['id'] as int;
        break;
      }
    }

    // Use the provided expense account ID or fall back to the system one
    final effectiveExpenseAccountId = widget.expenseAccountId ?? systemExpenseAccountId;

    final expenseMap = {
      'title': _titleController.text.trim(),
      'amount': amount,
      'currency': _selectedCurrency,
      'exchange_rate': exchangeRate,
      'amount_base': amountBase,
      'expense_date': dateStr,
      'payment_method': 'cash',
      'cash_box_id': _selectedCashBoxId,
      'account_id': effectiveExpenseAccountId,
      'beneficiary': _beneficiaryController.text.trim().isEmpty ? null : _beneficiaryController.text.trim(),
      'reference_number': _referenceNumberController.text.trim().isEmpty ? null : _referenceNumberController.text.trim(),
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'is_recurring': _isRecurring ? 1 : 0,
      'recurring_period': _isRecurring ? _recurringPeriod : null,
      'attachment_path': _attachmentPath,
      'operation_type': _operationType,
      'expense_account_id': effectiveExpenseAccountId,
      'updated_at': now,
    };

    if (_isEditing && widget.expenseId != null) {
      await _editExpenseWithReversal(widget.expenseId!, expenseMap, effectiveExpenseAccountId);
    } else {
      expenseMap['created_at'] = now;
      // Save expense with journal entries, using the expense account for the transaction
      await _saveExpenseWithAccountTransaction(expenseMap, effectiveExpenseAccountId);
    }

    if (mounted) {
      context.showSuccessSnackBar(_isEditing ? 'تم تحديث المصروف بنجاح' : 'تم حفظ المصروف بنجاح');
      Navigator.pop(context, true);
    }
  }

  Future<void> _saveExpenseWithAccountTransaction(Map<String, dynamic> expenseMap, int? expenseAccountId) async {
    final db = await DatabaseHelper().database;
    final amountBase = (expenseMap['amount_base'] as num?)?.toDouble() ?? 0.0;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Insert expense
      await txn.insert('expenses', expenseMap);

      if (expenseAccountId == null || amountBase <= 0) return;

      final journalId = DateTime.now().millisecondsSinceEpoch;
      final title = expenseMap['title'] as String? ?? 'مصروف';
      final isSarf = expenseMap['operation_type'] == 'صرف';

      // Get cash/bank account (the other side of the double-entry)
      final codeOffset = _selectedCurrency == 'SAR' ? 1 : (_selectedCurrency == 'USD' ? 2 : 0);
      int? cashBankAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            cashBankAccountId = linkedAccountId;
          }
        }
      }
      if (cashBankAccountId == null) {
        final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), _selectedCurrency], limit: 1);
        cashBankAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      }

      if (isSarf) {
        // صرف (disburse): Debit expense account, Credit cash/bank
        await txn.insert('transactions', {
          'account_id': expenseAccountId,
          'journal_id': journalId,
          'debit': amountBase,
          'credit': 0.0,
          'description': 'مصروف: $title',
          'date': now,
          'created_at': now,
        });
        await _updateAccountBalanceWithJournal(txn, expenseAccountId, amountBase, 0.0, now, codeOffset);

        if (cashBankAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBankAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': amountBase,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cashBankAccountId, 0.0, amountBase, now, codeOffset);
        }
      } else {
        // قبض (receive): Debit cash/bank, Credit expense account
        if (cashBankAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBankAccountId,
            'journal_id': journalId,
            'debit': amountBase,
            'credit': 0.0,
            'description': 'قبض: $title',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cashBankAccountId, amountBase, 0.0, now, codeOffset);
        }
        await txn.insert('transactions', {
          'account_id': expenseAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': amountBase,
          'description': 'قبض: $title',
          'date': now,
          'created_at': now,
        });
        await _updateAccountBalanceWithJournal(txn, expenseAccountId, 0.0, amountBase, now, codeOffset);
      }

      // Update cash box balance
      if (cashBoxId != null && amountBase > 0) {
        if (isSarf) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [amountBase, now, cashBoxId]);
        }
      }
    });
  }

  /// Edit an expense: reverse old journal entries, update the record, create new entries.
  Future<void> _editExpenseWithReversal(
    int expenseId,
    Map<String, dynamic> newExpenseMap,
    int? newExpenseAccountId,
  ) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // ── 1. Reverse old journal entries ──
      if (_existingExpense != null) {
        final oldAmountBase = (_existingExpense!['amount_base'] as num?)?.toDouble() ?? 0.0;
        final oldOperationType = _existingExpense!['operation_type'] as String? ?? 'صرف';
        final oldCurrency = _existingExpense!['currency'] as String? ?? 'YER';
        final oldCodeOffset = oldCurrency == 'SAR' ? 1 : (oldCurrency == 'USD' ? 2 : 0);
        final oldExpenseAccountId = (_existingExpense!['expense_account_id'] as int?) ?? (_existingExpense!['account_id'] as int?);
        final oldCashBoxId = _existingExpense!['cash_box_id'] as int?;
        final oldTitle = _existingExpense!['title'] as String? ?? 'مصروف';
        final oldIsSarf = oldOperationType == 'صرف';

        if (oldAmountBase > 0 && oldExpenseAccountId != null) {
          // Get old cash/bank account
          int? oldCashBankAccountId;
          if (oldCashBoxId != null) {
            final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [oldCashBoxId], limit: 1);
            if (cashBox.isNotEmpty) {
              final linkedAccountId = cashBox.first['linked_account_id'] as int?;
              if (linkedAccountId != null) {
                oldCashBankAccountId = linkedAccountId;
              }
            }
          }
          if (oldCashBankAccountId == null) {
            final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + oldCodeOffset).toString(), oldCurrency], limit: 1);
            oldCashBankAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
          }

          final reverseJournalId = DateTime.now().millisecondsSinceEpoch;

          // Reverse: swap debit ↔ credit of the original entry
          if (oldIsSarf) {
            // Original was: Debit expense, Credit cash → Reverse: Credit expense, Debit cash
            await txn.insert('transactions', {
              'account_id': oldExpenseAccountId,
              'journal_id': reverseJournalId,
              'debit': 0.0,
              'credit': oldAmountBase,
              'description': 'تعديل/عكس مصروف: $oldTitle',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, oldExpenseAccountId, 0.0, oldAmountBase, now, oldCodeOffset);

            if (oldCashBankAccountId != null) {
              await txn.insert('transactions', {
                'account_id': oldCashBankAccountId,
                'journal_id': reverseJournalId,
                'debit': oldAmountBase,
                'credit': 0.0,
                'description': 'تعديل/عكس مصروف: $oldTitle',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, oldCashBankAccountId, oldAmountBase, 0.0, now, oldCodeOffset);
            }
          } else {
            // Original was: Debit cash, Credit expense → Reverse: Credit cash, Debit expense
            if (oldCashBankAccountId != null) {
              await txn.insert('transactions', {
                'account_id': oldCashBankAccountId,
                'journal_id': reverseJournalId,
                'debit': 0.0,
                'credit': oldAmountBase,
                'description': 'تعديل/عكس قبض: $oldTitle',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, oldCashBankAccountId, 0.0, oldAmountBase, now, oldCodeOffset);
            }
            await txn.insert('transactions', {
              'account_id': oldExpenseAccountId,
              'journal_id': reverseJournalId,
              'debit': oldAmountBase,
              'credit': 0.0,
              'description': 'تعديل/عكس قبض: $oldTitle',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, oldExpenseAccountId, oldAmountBase, 0.0, now, oldCodeOffset);
          }

          // Reverse old cash box balance change
          if (oldCashBoxId != null && oldAmountBase > 0) {
            if (oldIsSarf) {
              // Original decreased cash box → reverse: increase
              await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [oldAmountBase, now, oldCashBoxId]);
            } else {
              // Original increased cash box → reverse: decrease
              await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [oldAmountBase, now, oldCashBoxId]);
            }
          }
        }
      }

      // ── 2. Update expense record ──
      await txn.update('expenses', newExpenseMap, where: 'id = ?', whereArgs: [expenseId]);

      // ── 3. Create new journal entries ──
      final newAmountBase = (newExpenseMap['amount_base'] as num?)?.toDouble() ?? 0.0;
      if (newExpenseAccountId != null && newAmountBase > 0) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        final title = newExpenseMap['title'] as String? ?? 'مصروف';
        final isSarf = newExpenseMap['operation_type'] == 'صرف';
        final codeOffset = _selectedCurrency == 'SAR' ? 1 : (_selectedCurrency == 'USD' ? 2 : 0);

        // Get cash/bank account for the new entry
        int? cashBankAccountId;
        final cashBoxId = newExpenseMap['cash_box_id'] as int?;
        if (cashBoxId != null) {
          final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          if (cashBox.isNotEmpty) {
            final linkedAccountId = cashBox.first['linked_account_id'] as int?;
            if (linkedAccountId != null) {
              cashBankAccountId = linkedAccountId;
            }
          }
        }
        if (cashBankAccountId == null) {
          final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), _selectedCurrency], limit: 1);
          cashBankAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
        }

        if (isSarf) {
          // صرف (disburse): Debit expense account, Credit cash/bank
          await txn.insert('transactions', {
            'account_id': newExpenseAccountId,
            'journal_id': journalId,
            'debit': newAmountBase,
            'credit': 0.0,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, newExpenseAccountId, newAmountBase, 0.0, now, codeOffset);

          if (cashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': cashBankAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': newAmountBase,
              'description': 'مصروف: $title',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBankAccountId, 0.0, newAmountBase, now, codeOffset);
          }
        } else {
          // قبض (receive): Debit cash/bank, Credit expense account
          if (cashBankAccountId != null) {
            await txn.insert('transactions', {
              'account_id': cashBankAccountId,
              'journal_id': journalId,
              'debit': newAmountBase,
              'credit': 0.0,
              'description': 'قبض: $title',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBankAccountId, newAmountBase, 0.0, now, codeOffset);
          }
          await txn.insert('transactions', {
            'account_id': newExpenseAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': newAmountBase,
            'description': 'قبض: $title',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, newExpenseAccountId, 0.0, newAmountBase, now, codeOffset);
        }

        // Update cash box balance for the new entry
        if (cashBoxId != null && newAmountBase > 0) {
          if (isSarf) {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [newAmountBase, now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [newAmountBase, now, cashBoxId]);
          }
        }
      }
    });
  }

  /// Helper to update account balance with proper debit/credit nature handling
  Future<void> _updateAccountBalanceWithJournal(Transaction txn, int accountId, double debit, double credit, String now, int codeOffset) async {
    final accountRow = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (accountRow.isEmpty) return;
    final account = accountRow.first;
    final balanceType = (account['balance_type'] as String?) ?? 'debit';
    // Use effectiveBalanceType logic: ASSET/COST/EXPENSE → debit, LIABILITY/REVENUE → credit
    final accountType = account['account_type'] as String? ?? '';
    final effectiveType = (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE') ? 'debit' : 'credit';
    
    double currentBalance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    if (effectiveType == 'debit') {
      currentBalance = currentBalance + debit - credit;
    } else {
      currentBalance = currentBalance + credit - debit;
    }
    await txn.update('accounts', {'balance': currentBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
  }
}
