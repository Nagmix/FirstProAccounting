import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/expense_sub_account_repository.dart';

/// Bottom sheet for adding or editing an expense sub-account.
///
/// Fields:
/// - **name** (required)
/// - **description**
/// - **debt_ceiling**
/// - **phone**
/// - **contact_method** (WhatsApp / SMS selector)
/// - **notes**
///
/// Intentionally **no** currency or opening-balance fields:
/// currency is determined at the transaction level, and balance is
/// calculated from transactions.
class AddExpenseSubAccountSheet extends StatefulWidget {
  /// Pass an existing sub-account map to edit; `null` to create new.
  final Map<String, dynamic>? existingSubAccount;

  const AddExpenseSubAccountSheet({super.key, this.existingSubAccount});

  @override
  State<AddExpenseSubAccountSheet> createState() =>
      _AddExpenseSubAccountSheetState();
}

class _AddExpenseSubAccountSheetState extends State<AddExpenseSubAccountSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _debtCeilingController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;

  String _contactMethod = 'whatsapp'; // 'whatsapp' | 'sms'
  bool _isSaving = false;
  bool get _isEditing => widget.existingSubAccount != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSubAccount;
    _nameController = TextEditingController(text: existing?['name'] as String? ?? '');
    _descriptionController =
        TextEditingController(text: existing?['description'] as String? ?? '');
    _debtCeilingController = TextEditingController(
      text: existing?['debt_ceiling'] != null
          ? _formatDebtCeiling(existing!['debt_ceiling'])
          : '',
    );
    _phoneController =
        TextEditingController(text: existing?['phone'] as String? ?? '');
    _notesController =
        TextEditingController(text: existing?['notes'] as String? ?? '');
    _contactMethod =
        existing?['contact_method'] as String? ?? 'whatsapp';
  }

  String _formatDebtCeiling(dynamic value) {
    if (value == null) return '';
    if (value is int) {
      // Stored as cents in DB — convert back to human-readable
      return (value / 100).toStringAsFixed(2);
    }
    if (value is double) return value.toStringAsFixed(2);
    return value.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _debtCeilingController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  //  SAVE
  // ══════════════════════════════════════════════════════════════

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final repo = locator<ExpenseSubAccountRepository>();
      final debtCeiling = double.tryParse(_debtCeilingController.text.trim()) ?? 0.0;

      final data = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'debt_ceiling': debtCeiling,
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'contact_method': _contactMethod,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'is_active': 1,
      };

      if (_isEditing) {
        final id = widget.existingSubAccount!['id'] as int;
        await repo.updateSubAccount(id, data);
      } else {
        await repo.insertSubAccount(data);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'تم تحديث الحساب بنجاح' : 'تم إنشاء حساب المصروف بنجاح',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: viewPaddingBottom,
            left: 16,
            right: 16,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // ── Handle bar ────────────────────────────────
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Title row ──────────────────────────────────
                  Row(
                    children: [
                      Icon(
                        _isEditing ? Icons.edit : Icons.create_new_folder,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isEditing
                            ? 'تعديل حساب المصروف'
                            : 'إضافة حساب مصروف جديد',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Name (required) ────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'اسم الحساب مطلوب' : null,
                    decoration: const InputDecoration(
                      labelText: 'اسم الحساب *',
                      prefixIcon: Icon(Icons.text_fields),
                      hintText: 'مثال: مصاريف إيجار',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Description ────────────────────────────────
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                      prefixIcon: Icon(Icons.description),
                      hintText: 'وصف مختصر للحساب',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),

                  // ── Debt ceiling ───────────────────────────────
                  TextFormField(
                    controller: _debtCeilingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سقف المديونية',
                      prefixIcon: Icon(Icons.shield),
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Phone ──────────────────────────────────────
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone),
                      hintText: '7XXXXXXXX',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Contact method selector ────────────────────
                  Text(
                    'طريقة التواصل',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // WhatsApp
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _contactMethod = 'whatsapp'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _contactMethod == 'whatsapp'
                                  ? AppColors.accentGreen.withOpacity(0.08)
                                  : (isDark
                                      ? AppColors.darkSurfaceVariant
                                      : AppColors.surfaceVariant),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _contactMethod == 'whatsapp'
                                    ? AppColors.accentGreen
                                    : AppColors.divider,
                                width: _contactMethod == 'whatsapp' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.chat,
                                  size: 20,
                                  color: _contactMethod == 'whatsapp'
                                      ? AppColors.accentGreen
                                      : AppColors.textHint,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'واتساب',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _contactMethod == 'whatsapp'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _contactMethod == 'whatsapp'
                                        ? AppColors.accentGreen
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // SMS
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _contactMethod = 'sms'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _contactMethod == 'sms'
                                  ? AppColors.info.withOpacity(0.08)
                                  : (isDark
                                      ? AppColors.darkSurfaceVariant
                                      : AppColors.surfaceVariant),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _contactMethod == 'sms'
                                    ? AppColors.info
                                    : AppColors.divider,
                                width: _contactMethod == 'sms' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.sms,
                                  size: 20,
                                  color: _contactMethod == 'sms'
                                      ? AppColors.info
                                      : AppColors.textHint,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'رسالة SMS',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _contactMethod == 'sms'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _contactMethod == 'sms'
                                        ? AppColors.info
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
                  const SizedBox(height: 14),

                  // ── Notes ──────────────────────────────────────
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // ── Save button ────────────────────────────────
                  SizedBox(
                    width: double.infinity,
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
                          : const Icon(Icons.save),
                      label: Text(
                        _isEditing ? 'تحديث الحساب' : 'حفظ الحساب',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
