import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/cash_box_model.dart';

class AddCashBoxSheet extends StatefulWidget {
  final CashBox? existing;
  const AddCashBoxSheet({super.key, this.existing});

  @override
  State<AddCashBoxSheet> createState() => _AddCashBoxSheetState();
}

class _AddCashBoxSheetState extends State<AddCashBoxSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankBranchController = TextEditingController();
  final _balanceController = TextEditingController();

  String _type = 'cash_box'; // 'cash_box' or 'bank'
  String _balanceType = 'credit'; // 'debit' or 'credit'
  int? _selectedAccountId;
  bool _isSaving = false;

  List<Map<String, dynamic>> _accounts = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _type = widget.existing!.type;
      _nameController.text = widget.existing!.name;
      _balanceType = widget.existing!.balanceType;
      _balanceController.text = widget.existing!.balance.toStringAsFixed(2);
      _bankAccountNumberController.text = widget.existing!.bankAccountNumber ?? '';
      _bankNameController.text = widget.existing!.bankName ?? '';
      _bankBranchController.text = widget.existing!.bankBranch ?? '';
      _selectedAccountId = widget.existing!.linkedAccountId;
    }
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final db = DatabaseHelper();
    final accounts = await db.getAccountsByType('ASSET');
    setState(() => _accounts = accounts);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bankAccountNumberController.dispose();
    _bankNameController.dispose();
    _bankBranchController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final now = DateTime.now().toIso8601String();
    final cashBox = CashBox(
      id: widget.existing?.id,
      name: _nameController.text.trim(),
      type: _type,
      bankAccountNumber: _type == 'bank' ? _bankAccountNumberController.text.trim() : null,
      bankName: _type == 'bank' ? _bankNameController.text.trim() : null,
      bankBranch: _type == 'bank' ? _bankBranchController.text.trim() : null,
      balance: double.tryParse(_balanceController.text) ?? 0.0,
      balanceType: _balanceType,
      linkedAccountId: _selectedAccountId,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final db = DatabaseHelper();
    if (_isEdit) {
      await db.updateCashBox(cashBox.id!, cashBox.toMap());
    } else {
      await db.insertCashBox(cashBox.toMap());
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ${_isEdit ? 'تعديل' : 'إضافة'} "${_nameController.text}" بنجاح'), backgroundColor: AppColors.success),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'تعديل صندوق/بنك' : 'إضافة صندوق أو بنك',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),

              // Type selection
              Text('النوع', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash_box', label: Text('صندوق'), icon: Icon(PhosphorIconsRegular.vault, size: 18)),
                  ButtonSegment(value: 'bank', label: Text('بنك'), icon: Icon(PhosphorIconsRegular.bank, size: 18)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 14),

              // Name
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _type == 'bank' ? 'اسم البنك' : 'اسم الصندوق',
                  prefixIcon: Icon(_type == 'bank' ? PhosphorIconsRegular.bank : PhosphorIconsRegular.vault),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // Bank-specific fields
              if (_type == 'bank') ...[
                TextFormField(
                  controller: _bankNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم البنك',
                    prefixIcon: Icon(PhosphorIconsRegular.buildings),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bankBranchController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'فرع البنك',
                    prefixIcon: Icon(PhosphorIconsRegular.mapPin),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bankAccountNumberController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رقم الحساب البنكي',
                    prefixIcon: Icon(PhosphorIconsRegular.identificationCard),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Initial balance (only for new cash boxes)
              if (!_isEdit || _type == 'cash_box') ...[
                TextFormField(
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: InputDecoration(
                    labelText: _type == 'cash_box' ? 'الرصيد الأولي' : 'الرصيد',
                    prefixIcon: const Icon(PhosphorIconsRegular.calculator),
                    suffixText: AppConstants.currency,
                  ),
                ),
                const SizedBox(height: 10),

                // Balance type: له / عليه
                Text('حالة الرصيد', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'credit',
                        groupValue: _balanceType,
                        title: const Text('له'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.success,
                        onChanged: (v) => setState(() => _balanceType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'debit',
                        groupValue: _balanceType,
                        title: const Text('عليه'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.error,
                        onChanged: (v) => setState(() => _balanceType = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Linked account
              DropdownButtonFormField<int>(
                value: _selectedAccountId,
                decoration: const InputDecoration(
                  labelText: 'الحساب المرتبط',
                  prefixIcon: Icon(PhosphorIconsRegular.link),
                ),
                items: _accounts.map((a) => DropdownMenuItem<int>(
                  value: a['id'] as int,
                  child: Text('${a['account_code']} - ${a['name_ar']}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _selectedAccountId = v),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(PhosphorIconsRegular.check, size: 20),
                      label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
