import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/license/license_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/models/customer_model.dart';

class AddCustomerSheet extends StatefulWidget {
  const AddCustomerSheet({super.key});

  @override
  State<AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends State<AddCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _address2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  final _balanceController = TextEditingController();
  final _debtCeilingController = TextEditingController();

  String _contactMethod = 'whatsapp';
  String _balanceType = 'credit'; // 'credit' (له) or 'debit' (عليه)
  String _currency = 'YER';
  bool _isSaving = false;

  static const _currencyInfo = {
    'YER': {'symbol': 'ر.ي', 'label': 'ريال يمني'},
    'SAR': {'symbol': 'ر.س', 'label': 'ريال سعودي'},
    'USD': {'symbol': '\$', 'label': 'دولار أمريكي'},
  };

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _address2Controller.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _balanceController.dispose();
    _debtCeilingController.dispose();
    super.dispose();
  }

  Future<bool> _checkRecordLimit() async {
    final canAdd = await context.read<LicenseProvider>().canAddRecord();
    if (!canAdd && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تم تجاوز الحد الأقصى'),
          content: const Text(
            'لقد وصلت إلى الحد الأقصى للسجلات في النسخة المجانية (500 سجل). '
            'قم بتفعيل الترخيص لإضافة سجلات غير محدودة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/license-activation');
              },
              child: const Text('تفعيل الترخيص'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Check record limit
    final canAdd = await _checkRecordLimit();
    if (!canAdd) return;

    setState(() => _isSaving = true);

    final customer = Customer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      address2: _address2Controller.text.trim().isEmpty ? null : _address2Controller.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      contactMethod: _contactMethod,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      balance: double.tryParse(_balanceController.text) ?? 0.0,
      balanceType: _balanceType,
      currency: null, // Customer is multi-currency — no permanent currency
      debtCeiling: double.tryParse(_debtCeilingController.text) ?? 0.0,
    );

    // Build the map and attach the opening balance currency separately
    // so the repository can create the correct journal entry while
    // the customer record itself stores no permanent currency.
    final map = customer.toMap();
    final openingBalance = double.tryParse(_balanceController.text) ?? 0.0;
    if (openingBalance > 0) {
      map['opening_balance_currency'] = _currency;
    }

    await locator<CustomerRepository>().insertCustomer(map);

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إضافة العميل "${_nameController.text}" بنجاح'), backgroundColor: AppColors.success),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة عميل جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                  decoration: const InputDecoration(labelText: 'الاسم *', prefixIcon: Icon(Icons.person)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(15)],
                  decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email)),
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!regex.hasMatch(v.trim())) return 'البريد الإلكتروني غير صالح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _addressController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.location_on)),
                ),
                const SizedBox(height: 14),

                // ════════════════════════════════════════════════════════
                //  القيد الافتتاحي — Opening Balance Section
                //  Currency & balance_type are ONLY for the opening
                //  balance journal entry, not the customer account.
                // ════════════════════════════════════════════════════════
                _SectionLabel(label: 'القيد الافتتاحي'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.04),
                    border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Amount + Currency row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _balanceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: TextInputAction.next,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                              decoration: InputDecoration(
                                labelText: 'الرصيد الافتتاحي',
                                prefixIcon: const Icon(Icons.calculate),
                                suffixText: _currencyInfo[_currency]!['symbol'],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _currency,
                              decoration: const InputDecoration(
                                labelText: 'عملة القيد الافتتاحي',
                                prefixIcon: Icon(Icons.currency_exchange),
                              ),
                              items: _currencyInfo.entries.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text('${e.value['label']} (${e.value['symbol']})', style: const TextStyle(fontSize: 13)),
                              )).toList(),
                              onChanged: (v) => setState(() => _currency = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Balance direction toggle (له / عليه)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('اتجاه الرصيد الافتتاحي', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: _balanceType == 'credit' ? AppColors.success : AppColors.error),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _balanceType = 'credit'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'credit' ? AppColors.success.withOpacity(0.1) : Colors.transparent,
                                        borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'له',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'credit' ? AppColors.success : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _balanceType = 'debit'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _balanceType == 'debit' ? AppColors.error.withOpacity(0.1) : Colors.transparent,
                                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(9), bottomLeft: Radius.circular(9)),
                                      ),
                                      child: Text(
                                        'عليه',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _balanceType == 'debit' ? AppColors.error : AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Note about currency scope
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'العملة هنا خاصة بالقيد الافتتاحي فقط. يمكنك التعامل بأي عملة بعد إنشاء العميل.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.amber.shade900,
                                  height: 1.4,
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

                // Debt ceiling — no currency suffix because customer is multi-currency
                TextFormField(
                  controller: _debtCeilingController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: const InputDecoration(
                    labelText: 'سقف المدينية',
                    prefixIcon: Icon(Icons.credit_card),
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

                _SectionLabel(label: 'واتساب'),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'whatsapp', groupValue: _contactMethod, title: const Text('واتساب'),
                        contentPadding: EdgeInsets.zero, dense: true, activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _contactMethod = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'phone', groupValue: _contactMethod, title: const Text('اتصال'),
                        contentPadding: EdgeInsets.zero, dense: true, activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _contactMethod = v!),
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
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 20),
                        label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
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

                // Extra bottom safe area for gesture nav
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
      child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
    );
  }
}
