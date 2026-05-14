import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/customer_model.dart';

/// Modal bottom sheet for adding a new customer.
///
/// All fields are in Arabic and RTL. Includes form validation
/// and radio buttons for gender and notification method.
class AddCustomerSheet extends StatefulWidget {
  const AddCustomerSheet({super.key});

  @override
  State<AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends State<AddCustomerSheet> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ───────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _address2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _countryController = TextEditingController();
  final _notesController = TextEditingController();
  final _balanceController = TextEditingController();
  final _creditLimitController = TextEditingController();

  // ── State ─────────────────────────────────────────────────────
  String _gender = 'male'; // male | female
  String _notificationMethod = 'sms'; // sms | notification
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _address2Controller.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _notesController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  // ── Save handler ──────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final customer = Customer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      address2: _address2Controller.text.trim().isEmpty ? null : _address2Controller.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
      gender: _gender,
      notificationMethod: _notificationMethod,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      balance: double.tryParse(_balanceController.text) ?? 0.0,
      creditLimit: double.tryParse(_creditLimitController.text) ?? 0.0,
    );

    final db = DatabaseHelper();
    await db.insertCustomer(customer.toMap());

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم إضافة العميل "${_nameController.text}" بنجاح'),
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
              // ── Header ─────────────────────────────────────────
              Text(
                'إضافة عميل جديد',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── الاسم ─────────────────────────────────────────
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

              // ── رقم الهاتف ────────────────────────────────────
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

              // ── البريد الإلكتروني ─────────────────────────────
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
                    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!regex.hasMatch(v.trim())) {
                      return 'البريد الإلكتروني غير صالح';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── العنوان ───────────────────────────────────────
              TextFormField(
                controller: _addressController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  prefixIcon: Icon(PhosphorIconsRegular.mapPin),
                ),
              ),
              const SizedBox(height: 14),

              // ── العنوان 2 ─────────────────────────────────────
              TextFormField(
                controller: _address2Controller,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان - سطر ثاني',
                  prefixIcon: Icon(PhosphorIconsRegular.mapPinLine),
                ),
              ),
              const SizedBox(height: 14),

              // ── البلد ──────────────────────────────────────────
              TextFormField(
                controller: _countryController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'البلد',
                  prefixIcon: Icon(PhosphorIconsRegular.globe),
                ),
              ),
              const SizedBox(height: 14),

              // ── الرصيد الافتتاحي ──────────────────────────────
              TextFormField(
                controller: _balanceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'الرصيد الافتتاحي',
                  prefixIcon: const Icon(PhosphorIconsRegular.calculator),
                  suffixText: AppConstants.currency,
                ),
              ),
              const SizedBox(height: 14),

              // ── حد الائتمان ────────────────────────────────────
              TextFormField(
                controller: _creditLimitController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'حد الائتمان',
                  prefixIcon: const Icon(PhosphorIconsRegular.creditCard),
                  suffixText: AppConstants.currency,
                ),
              ),
              const SizedBox(height: 14),

              // ── الملاحظات ─────────────────────────────────────
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
              const SizedBox(height: 20),

              // ── الجنس (Radio) ─────────────────────────────────
              _SectionLabel(label: 'الجنس'),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'male',
                      groupValue: _gender,
                      title: const Text('ذكر'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _gender = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'female',
                      groupValue: _gender,
                      title: const Text('أنثى'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _gender = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── طريقة التواصل (Radio) ─────────────────────────
              _SectionLabel(label: 'طريقة التواصل'),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'sms',
                      groupValue: _notificationMethod,
                      title: const Text('رسائل نصية'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          setState(() => _notificationMethod = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'notification',
                      groupValue: _notificationMethod,
                      title: const Text('إشعارات'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          setState(() => _notificationMethod = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Action buttons ─────────────────────────────────
              Row(
                children: [
                  // حفظ
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
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
                  // إلغاء
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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

// ═══════════════════════════════════════════════════════════════════
//  SECTION LABEL
// ═══════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
