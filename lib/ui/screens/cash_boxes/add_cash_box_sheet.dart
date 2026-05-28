import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _currency = 'YER'; // 'YER', 'SAR', 'USD'
  int? _linkedAccountId;
  bool _isSaving = false;
  bool _accountLinkError = false;

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
      _bankAccountNumberController.text = widget.existing!.bankAccountNumber ?? '';
      _bankNameController.text = widget.existing!.bankName ?? '';
      _bankBranchController.text = widget.existing!.bankBranch ?? '';
      _linkedAccountId = widget.existing!.linkedAccountId;

      // Derive currency from the linked account if editing
      if (_linkedAccountId != null) {
        _deriveCurrencyFromLinkedAccount();
      }
    } else {
      // For new cash boxes, auto-link to default currency (YER) account
      _onCurrencyChanged(_currency);
    }
  }

  /// When editing, try to figure out which currency the existing linked account belongs to.
  Future<void> _deriveCurrencyFromLinkedAccount() async {
    final db = DatabaseHelper();
    for (final entry in _cashBanksAccountCodes.entries) {
      final account = await db.getAccountByCodeAndCurrency(entry.value, entry.key);
      if (account != null && account['id'] == _linkedAccountId) {
        if (mounted) {
          setState(() => _currency = entry.key);
        }
        break;
      }
    }
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

  /// Auto-link to the Cash & Banks account for the selected currency.
  Future<void> _onCurrencyChanged(String newCurrency) async {
    setState(() {
      _currency = newCurrency;
      _accountLinkError = false;
    });

    final code = _cashBanksAccountCodes[newCurrency]!;
    final db = DatabaseHelper();
    final account = await db.getAccountByCodeAndCurrency(code, newCurrency);

    if (!mounted) return;

    if (account != null) {
      setState(() => _linkedAccountId = account['id'] as int);
    } else {
      // No matching account found — show warning but still allow the user to proceed
      setState(() {
        _linkedAccountId = null;
        _accountLinkError = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Ensure we have a linked account before saving
    if (_linkedAccountId == null) {
      // Try one more time to resolve the account
      final code = _cashBanksAccountCodes[_currency]!;
      final db = DatabaseHelper();
      try {
        final account = await db.getAccountByCodeAndCurrency(code, _currency);
        if (account != null) {
          _linkedAccountId = account['id'] as int;
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على حساب الصناديق والبنوك للعملة المحددة'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في البحث عن الحساب: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final cashBox = CashBox(
        id: widget.existing?.id,
        name: _nameController.text.trim(),
        type: _type,
        bankAccountNumber: _type == 'bank' ? _bankAccountNumberController.text.trim() : null,
        bankName: _type == 'bank' ? _bankNameController.text.trim() : null,
        bankBranch: _type == 'bank' ? _bankBranchController.text.trim() : null,
        balance: double.tryParse(_balanceController.text) ?? 0.0,
        balanceType: _balanceType,
        linkedAccountId: _linkedAccountId,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = cashBox.toMap();
      // Include currency in the map so it gets persisted
      map['currency'] = _currency;
      // Remove null id for new inserts (sqflite auto-generates)
      if (!_isEdit) {
        map.remove('id');
      }

      final db = DatabaseHelper();
      if (_isEdit) {
        await db.updateCashBox(cashBox.id!, map);
      } else {
        await db.insertCashBox(map);

        // ── Opening Balance Journal Entry ──
        final openingBalance = double.tryParse(_balanceController.text) ?? 0.0;
        if (openingBalance > 0 && _linkedAccountId != null) {
          final codeOffset = _currency == 'SAR' ? 1 : (_currency == 'USD' ? 2 : 0);
          final openingBalanceAccount = await db.getAccountByCodeAndCurrency(
            (2200 + codeOffset).toString(), _currency,
          );
          final openingBalanceAccountId = openingBalanceAccount?['id'] as int?;

          if (openingBalanceAccountId != null) {
            final now = DateTime.now().toIso8601String();
            final journalId = DateTime.now().millisecondsSinceEpoch;
            final database = await db.database;
            final name = _nameController.text.trim();

            if (_balanceType == 'debit') {
              // Debit Cash & Banks, Credit Opening Balance Equity
              await database.insert('transactions', {
                'account_id': _linkedAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(openingBalance),
                'credit': 0,
                'description': 'رصيد افتتاحي صندوق - $name',
                'date': now,
                'created_at': now,
              });
              await database.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(openingBalance),
                'description': 'رصيد افتتاحي صندوق - $name',
                'date': now,
                'created_at': now,
              });
              await db.updateAccountBalance(_linkedAccountId!, openingBalance, isDebit: true);
              await db.updateAccountBalance(openingBalanceAccountId, openingBalance, isDebit: false);
            } else {
              // Credit Cash & Banks, Debit Opening Balance Equity
              await database.insert('transactions', {
                'account_id': _linkedAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(openingBalance),
                'description': 'رصيد افتتاحي صندوق - $name',
                'date': now,
                'created_at': now,
              });
              await database.insert('transactions', {
                'account_id': openingBalanceAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(openingBalance),
                'credit': 0,
                'description': 'رصيد افتتاحي صندوق - $name',
                'date': now,
                'created_at': now,
              });
              await db.updateAccountBalance(_linkedAccountId!, openingBalance, isDebit: false);
              await db.updateAccountBalance(openingBalanceAccountId, openingBalance, isDebit: true);
            }
          }
        }
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم ${_isEdit ? 'تعديل' : 'إضافة'} "${_nameController.text}" بنجاح'),
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
    final currencySymbol = _currencyInfo[_currency]?['symbol'] ?? AppConstants.currency;

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
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── Type selection ──
              Text('النوع', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                  prefixIcon: Icon(_type == 'bank' ? Icons.account_balance : Icons.account_balance_wallet),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // ── Currency selection ──
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                  labelText: 'العملة',
                  prefixIcon: const Icon(Icons.attach_money),
                  suffixIcon: _linkedAccountId != null
                      ? const Icon(Icons.link, size: 18, color: AppColors.success)
                      : null,
                ),
                items: _currencyInfo.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text('${entry.value['label']} (${entry.key})'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) _onCurrencyChanged(v);
                },
              ),
              if (_accountLinkError) ...[
                const SizedBox(height: 6),
                Text(
                  'لم يتم العثور على حساب الصناديق والبنوك للعملة المحددة. تأكد من وجود الحساب بدليل الحسابات.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
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

              // ── Opening balance (only for new cash boxes) ──
              if (!_isEdit || _type == 'cash_box') ...[
                TextFormField(
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: InputDecoration(
                    labelText: _type == 'cash_box' ? 'الرصيد الافتتاحي' : 'الرصيد',
                    prefixIcon: const Icon(Icons.calculate),
                    suffixText: currencySymbol,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Opening balance direction: له / عليه ──
                Text('اتجاه الرصيد الافتتاحي', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppColors.warning),
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

              // ── Auto-linked account info (read-only) ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _linkedAccountId != null
                      ? AppColors.success.withOpacity(0.08)
                      : AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _linkedAccountId != null
                        ? AppColors.success.withOpacity(0.3)
                        : AppColors.error.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _linkedAccountId != null ? Icons.link : Icons.warning,
                      size: 18,
                      color: _linkedAccountId != null ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _linkedAccountId != null
                            ? 'مرتبط تلقائيًا بحساب الصناديق والبنوك (${_cashBanksAccountCodes[_currency]} - $_currency)'
                            : 'لم يتم ربط الحساب — اختر عملة أخرى أو تأكد من دليل الحسابات',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _linkedAccountId != null ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
