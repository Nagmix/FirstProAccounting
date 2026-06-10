import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/journal_service.dart';
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
  String _currency = 'YER'; // 'YER', 'SAR', 'USD' — only for opening balance
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  /// Maps each currency to the account_code for "حساب الصناديق والبنوك".
  static const Map<String, String> _cashBanksAccountCodes = {
    'YER': '1100',
    'SAR': '1101',
    'USD': '1102',
  };

  /// Currency display info.
  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _type = widget.existing!.type;
      _nameController.text = widget.existing!.name;
      _balanceType = widget.existing!.balanceType;
      _balanceController.text = widget.existing!.balance.toStringAsFixed(2);
      _bankAccountNumberController.text =
          widget.existing!.bankAccountNumber ?? '';
      _bankNameController.text = widget.existing!.bankName ?? '';
      _bankBranchController.text = widget.existing!.bankBranch ?? '';
      // Cash box is currency-agnostic; no need to derive currency from linked account
    }
    // Default currency for opening balance is YER
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

  /// Resolve the linked account for the opening balance journal entry based on currency.
  /// This is temporary — only used for the journal entry, NOT stored on the cash box.
  Future<int?> _resolveLinkedAccountForCurrency(String currency) async {
    final code = _cashBanksAccountCodes[currency]!;
    final account = await locator<JournalService>()
        .getAccountByCodeAndCurrency(code, currency);
    return account?['id'] as int?;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final cashBox = CashBox(
        id: widget.existing?.id,
        name: _nameController.text.trim(),
        type: _type,
        bankAccountNumber:
            _type == 'bank' ? _bankAccountNumberController.text.trim() : null,
        bankName: _type == 'bank' ? _bankNameController.text.trim() : null,
        bankBranch: _type == 'bank' ? _bankBranchController.text.trim() : null,
        balance: double.tryParse(_balanceController.text) ?? 0.0,
        balanceType: _balanceType,
        linkedAccountId:
            null, // Cash box is currency-agnostic — no permanent link
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = cashBox.toMap();
      // Cash box does NOT permanently bind to a currency, but the DB column
      // is NOT NULL, so we store the opening-balance currency as the default.
      // The currency selector is only meaningful for the opening balance entry.
      map['currency'] = _currency;
      // Remove null id for new inserts (sqflite auto-generates)
      if (!_isEdit) {
        map.remove('id');
      }

      if (_isEdit) {
        await locator<CashBoxService>().updateCashBox(cashBox.id!, map);
      } else {
        final cashBoxId = await locator<CashBoxService>().insertCashBox(map);

        // ── Opening Balance Journal Entry ──
        final openingBalance = double.tryParse(_balanceController.text) ?? 0.0;
        if (openingBalance > 0) {
          // Resolve the linked account for the selected currency (temporary, for journal only)
          final linkedAccountId =
              await _resolveLinkedAccountForCurrency(_currency);

          if (linkedAccountId == null) {
            if (!mounted) return;
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'لم يتم العثور على حساب الصناديق والبنوك للعملة المحددة. تأكد من وجود الحساب بدليل الحسابات.'),
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }

          final codeOffset =
              _currency == 'SAR' ? 1 : (_currency == 'USD' ? 2 : 0);
          final openingBalanceAccount =
              await locator<JournalService>().getAccountByCodeAndCurrency(
            (2901 + codeOffset).toString(),
            _currency,
          );
          final openingBalanceAccountId = openingBalanceAccount?['id'] as int?;

          if (openingBalanceAccountId != null) {
            final name = _nameController.text.trim();
            await locator<CashBoxService>().recordCashBoxOpeningBalance(
              linkedAccountId: linkedAccountId,
              openingBalanceAccountId: openingBalanceAccountId,
              openingBalance: openingBalance,
              balanceType: _balanceType,
              cashBoxName: name,
              cashBoxId: cashBoxId,
            );
          }
        }
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم ${_isEdit ? 'تعديل' : 'إضافة'} "${_nameController.text}" بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الحفظ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    final currencySymbol =
        _currencyInfo[_currency]?['symbol'] ?? AppConstants.currency;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + viewPaddingBottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Title ──
              Text(
                _isEdit ? 'تعديل صندوق/بنك' : 'إضافة صندوق أو بنك',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── Type selection ──
              Text('النوع',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'cash_box',
                    label: Text('صندوق'),
                    icon: Icon(Icons.account_balance_wallet, size: 18),
                  ),
                  ButtonSegment(
                    value: 'bank',
                    label: Text('بنك'),
                    icon: Icon(Icons.account_balance, size: 18),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 14),

              // ── Name ──
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _type == 'bank' ? 'اسم البنك' : 'اسم الصندوق',
                  prefixIcon: Icon(_type == 'bank'
                      ? Icons.account_balance
                      : Icons.account_balance_wallet),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // ── Bank-specific fields ──
              if (_type == 'bank') ...[
                TextFormField(
                  controller: _bankNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم البنك',
                    prefixIcon: Icon(Icons.business),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bankBranchController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'فرع البنك',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bankAccountNumberController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رقم الحساب البنكي',
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Opening balance section (only for new cash boxes) ──
              if (!_isEdit) ...[
                // ── Section header ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'الرصيد الافتتاحي',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Opening balance amount ──
                TextFormField(
                  controller: _balanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                  ],
                  decoration: InputDecoration(
                    labelText:
                        _type == 'cash_box' ? 'الرصيد الافتتاحي' : 'الرصيد',
                    prefixIcon: const Icon(Icons.calculate),
                    suffixText: currencySymbol,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Currency selection (inside opening balance section) ──
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'عملة القيد',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: _currencyInfo.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text('${entry.value['label']} (${entry.key})'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _currency = v);
                  },
                ),
                const SizedBox(height: 6),

                // ── Note about currency ──
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'العملة هنا خاصة بالقيد الافتتاحي فقط. يمكنك التعامل بأي عملة بعد إنشاء الصندوق.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Opening balance direction: له / عليه ──
                Text('اتجاه الرصيد الافتتاحي',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: AppColors.primary)),
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
                // Note: This only applies to the opening balance
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'هذا الخيار خاص بالرصيد الافتتاحي فقط وليس حالة دائمة للصندوق',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Edit mode: show existing balance info ──
              if (_isEdit && widget.existing != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الصندوق لا يرتبط بعملة محددة — يمكنك التعامل بأي عملة.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const SizedBox(height: 10),

              // ── Action buttons ──
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
