import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/supplier_repository.dart';
import 'package:firstpro/data/models/supplier_model.dart';

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
  final _debtCeilingController = TextEditingController();
  final _notesController = TextEditingController();

  String _balanceType = 'credit'; // 'credit' (له) or 'debit' (عليه)
  String _currency = 'YER'; // currency for opening balance only
  String _contactMethod = 'whatsapp'; // 'whatsapp' or 'phone'
  bool _isSaving = false;

  static const _currencyInfo = {
    'YER': {'symbol': 'ر.ي', 'label': 'ريال يمني'},
    'SAR': {'symbol': 'ر.س', 'label': 'ريال سعودي'},
    'USD': {'symbol': '\$', 'label': 'دولار أمريكي'},
  };
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
      _balanceController.text =
          s.balance > 0 ? s.balance.toStringAsFixed(2) : '';
      _balanceType = s.balanceType;
      // Currency is no longer tied to supplier permanently.
      // When editing, default to the supplier's stored currency since
      // that's likely the currency of the existing opening balance.
      // When adding new, default to YER.
      _currency = s.currency.isNotEmpty ? s.currency : 'YER';
      _debtCeilingController.text =
          s.debtCeiling > 0 ? s.debtCeiling.toStringAsFixed(2) : '';
      _contactMethod = s.contactMethod ?? 'whatsapp';
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
    _debtCeilingController.dispose();
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
      'phone': _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      'address': _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      'balance': balance,
      'balance_type': _balanceType,
      // Supplier is multi-currency — store the opening balance currency
      // as default (DB column is NOT NULL), but it does NOT permanently
      // bind the supplier to this currency.
      'currency': _currency,
      // Pass the opening balance currency separately for the journal entry
      'opening_balance_currency': _currency,
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      'debt_ceiling': double.tryParse(_debtCeilingController.text) ?? 0.0,
      'contact_method': _contactMethod,
      'updated_at': now,
    };

    final supplierRepo = locator<SupplierRepository>();

    if (_isEditing) {
      await supplierRepo.updateSupplier(widget.supplier!.id!, supplierMap);
    } else {
      supplierMap['created_at'] = now;
      await supplierRepo.insertSupplier(supplierMap);
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditing ? 'تعديل مورد' : 'إضافة مورد جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 20),
            label: Text(_isSaving
                ? 'جاري الحفظ...'
                : _isEditing
                    ? 'تعديل'
                    : 'حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding:
            EdgeInsets.fromLTRB(20, 8, 20, bottomInset + bottomPadding + 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Name ──────────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  prefixIcon: Icon(Icons.person),
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
                  prefixIcon: Icon(Icons.phone),
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
                  prefixIcon: Icon(Icons.email),
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

              // ── Address ───────────────────────────────────────────
              TextFormField(
                controller: _addressController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 14),

              // ══════════════════════════════════════════════════════
              // ── القيد الافتتاحي (Opening Balance Section) ─────────
              // ══════════════════════════════════════════════════════
              _SectionLabel(label: 'القيد الافتتاحي'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Amount field (full width) ─────────────────────
                    TextFormField(
                      controller: _balanceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      decoration: InputDecoration(
                        labelText: 'الرصيد الافتتاحي',
                        prefixIcon: const Icon(Icons.calculate),
                        suffixText: CurrencyConstants.currencySymbol(_currency),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Currency dropdown (full width) ────────────────
                    DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: InputDecoration(
                        labelText: 'عملة القيد',
                        prefixIcon: const Icon(Icons.currency_exchange),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _currencyInfo.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                    '${e.value['label']} (${e.value['symbol']})'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _currency = v!),
                    ),
                    const SizedBox(height: 12),

                    // ── Balance direction toggle (له/عليه) ─────────
                    Row(
                      children: [
                        Text(
                          'اتجاه الرصيد:',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _balanceType == 'credit'
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'credit'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'credit'
                                            ? AppColors.success
                                                .withValues(alpha: 0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(9),
                                          bottomRight: Radius.circular(9),
                                        ),
                                      ),
                                      child: Text(
                                        'له',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'credit'
                                              ? AppColors.success
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _balanceType = 'debit'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'debit'
                                            ? AppColors.error
                                                .withValues(alpha: 0.1)
                                            : Colors.transparent,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(9),
                                          bottomLeft: Radius.circular(9),
                                        ),
                                      ),
                                      child: Text(
                                        'عليه',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'debit'
                                              ? AppColors.error
                                              : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Info note about currency ────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppColors.info),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'العملة هنا خاصة بالقيد الافتتاحي فقط. يمكنك التعامل بأي عملة بعد إنشاء المورد.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.info,
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── سقف المدينية (Debt Ceiling) — no currency suffix ──
              TextFormField(
                controller: _debtCeilingController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                ],
                decoration: const InputDecoration(
                  labelText: 'سقف المدينية',
                  prefixIcon: Icon(Icons.credit_card),
                  // No suffixText — supplier is now multi-currency
                ),
              ),
              const SizedBox(height: 18),

              // ── طريقة التواصل ─────────────────────────────────────
              _SectionLabel(label: 'طريقة التواصل'),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _contactMethod == 'whatsapp'
                        ? const Color(0xFF25D366)
                        : AppColors.primary,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _contactMethod = 'whatsapp'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _contactMethod == 'whatsapp'
                                ? const Color(0xFF25D366).withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(9),
                              bottomRight: Radius.circular(9),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat,
                                size: 16,
                                color: _contactMethod == 'whatsapp'
                                    ? const Color(0xFF25D366)
                                    : AppColors.textHint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'واتساب',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _contactMethod == 'whatsapp'
                                      ? const Color(0xFF25D366)
                                      : AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _contactMethod = 'phone'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _contactMethod == 'phone'
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(9),
                              bottomLeft: Radius.circular(9),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phone_in_talk,
                                size: 16,
                                color: _contactMethod == 'phone'
                                    ? AppColors.primary
                                    : AppColors.textHint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'اتصال',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _contactMethod == 'phone'
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Notes ─────────────────────────────────────────────
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'الملاحظات',
                  prefixIcon: Icon(Icons.edit_note),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

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
                          : const Icon(Icons.check, size: 20),
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

              // Extra bottom safe area for gesture nav
              SizedBox(height: bottomPadding),
            ],
          ),
        ),
      ),
    );
  }
}

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
