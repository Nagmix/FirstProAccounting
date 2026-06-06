import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/expense_sub_account_repository.dart';

/// Bottom sheet for adding or editing an expense sub-account.
///
/// Follows the same design pattern as [AddCustomerSheet]:
/// - Full Scaffold with AppBar inside bottom sheet
/// - Standard InputDecoration with prefixIcon
/// - Save button in AppBar + bottom save/cancel buttons
/// - له/عليه balance type selector matching customer sheet
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
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _debtCeilingController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  String _contactMethod = 'whatsapp';
  bool _isSaving = false;
  bool get _isEditing => widget.existingSubAccount != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSubAccount;
    _nameController.text = existing?['name'] as String? ?? '';
    _descriptionController.text = existing?['description'] as String? ?? '';
    _debtCeilingController.text = existing?['debt_ceiling'] != null
        ? _formatDebtCeiling(existing!['debt_ceiling'])
        : '';
    _phoneController.text = existing?['phone'] as String? ?? '';
    _notesController.text = existing?['notes'] as String? ?? '';
    _contactMethod = existing?['contact_method'] as String? ?? 'whatsapp';
  }

  String _formatDebtCeiling(dynamic value) {
    if (value == null) return '';
    if (value is int) return (value / 100).toStringAsFixed(2);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final repo = locator<ExpenseSubAccountRepository>();
      final debtCeiling =
          double.tryParse(_debtCeilingController.text.trim()) ?? 0.0;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'تم تحديث الحساب بنجاح'
                : 'تم إنشاء حساب المصروف بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'تعديل حساب المصروف' : 'إضافة حساب مصروف جديد'),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 20),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + bottomPadding + 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم الحساب *',
                    prefixIcon: Icon(Icons.text_fields),
                    hintText: 'مثال: مصاريف إيجار',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'اسم الحساب مطلوب' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _descriptionController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الوصف',
                    prefixIcon: Icon(Icons.description),
                    hintText: 'وصف مختصر للحساب',
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _debtCeilingController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'سقف المديونية',
                    prefixIcon: Icon(Icons.credit_card),
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 14),

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

                _SectionLabel(label: 'طريقة التواصل'),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'whatsapp',
                        groupValue: _contactMethod,
                        title: const Text('واتساب'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.primary,
                        onChanged: (v) =>
                            setState(() => _contactMethod = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'sms',
                        groupValue: _contactMethod,
                        title: const Text('رسالة SMS'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.primary,
                        onChanged: (v) =>
                            setState(() => _contactMethod = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

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
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 20),
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
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('إلغاء'),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: bottomPadding),
              ],
            ),
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
