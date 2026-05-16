import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/supplier_model.dart';

class AddSupplierSheet extends StatefulWidget {
  const AddSupplierSheet({super.key, this.supplier});

  /// If non-null, the sheet operates in *edit* mode.
  final Supplier? supplier;

  @override
  State<AddSupplierSheet> createState() => _AddSupplierSheetState();
}

class _AddSupplierSheetState extends State<AddSupplierSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _balanceController = TextEditingController();
  final _notesController = TextEditingController();

  String _balanceType = 'debit'; // 'credit' (له) or 'debit' (عليه)
  bool _isSaving = false;
  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final s = widget.supplier!;
      _nameController.text = s.name;
      _phoneController.text = s.phone ?? '';
      _emailController.text = s.email ?? '';
      _addressController.text = s.address ?? '';
      _balanceController.text = s.balance > 0 ? s.balance.toStringAsFixed(2) : '';
      _balanceType = s.balanceType;
      _notesController.text = s.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final now = DateTime.now().toIso8601String();
    final balance = double.tryParse(_balanceController.text) ?? 0.0;

    final supplierMap = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      'balance': balance,
      'balance_type': _balanceType,
      'currency': 'YER',
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'updated_at': now,
    };

    final db = DatabaseHelper();

    if (_isEditing) {
      await db.updateSupplier(widget.supplier!.id!, supplierMap);
    } else {
      supplierMap['created_at'] = now;
      await db.insertSupplier(supplierMap);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing
            ? 'تم تعديل المورد "${_nameController.text}" بنجاح'
            : 'تم إضافة المورد "${_nameController.text}" بنجاح'),
        backgroundColor: AppColors.success,
      ),
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
              Text(
                _isEditing ? 'تعديل مورد' : 'إضافة مورد جديد',
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── Name ──────────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  prefixIcon: Icon(PhosphorIconsRegular.user),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // ── Phone ─────────────────────────────────────────────
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(PhosphorIconsRegular.phone),
                ),
              ),
              const SizedBox(height: 14),

              // ── Email ─────────────────────────────────────────────
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(PhosphorIconsRegular.envelope),
                ),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final regex =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!regex.hasMatch(v.trim())) {
                      return 'البريد الإلكتروني غير صالح';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Address ───────────────────────────────────────────
              TextFormField(
                controller: _addressController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  prefixIcon: Icon(PhosphorIconsRegular.mapPin),
                ),
              ),
              const SizedBox(height: 14),

              // ── Opening balance + له/عليه ─────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      decoration: InputDecoration(
                        labelText: 'الرصيد الافتتاحي',
                        prefixIcon:
                            const Icon(PhosphorIconsRegular.calculator),
                        suffixText: AppConstants.currency,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'الحالة',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                value: 'credit',
                                groupValue: _balanceType,
                                title: const Text('له',
                                    style: TextStyle(fontSize: 13)),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: AppColors.success,
                                onChanged: (v) =>
                                    setState(() => _balanceType = v!),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                value: 'debit',
                                groupValue: _balanceType,
                                title: const Text('عليه',
                                    style: TextStyle(fontSize: 13)),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                activeColor: AppColors.error,
                                onChanged: (v) =>
                                    setState(() => _balanceType = v!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Notes ─────────────────────────────────────────────
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'الملاحظات',
                  prefixIcon: Icon(PhosphorIconsRegular.notepad),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // ── Action buttons ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(PhosphorIconsRegular.check, size: 20),
                      label: Text(_isSaving
                          ? 'جاري الحفظ...'
                          : _isEditing
                              ? 'تعديل'
                              : 'حفظ'),
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
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
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
