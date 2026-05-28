import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/account_model.dart';

class AddAccountSheet extends StatefulWidget {
  final Account? existing;
  final List<Account> allAccounts;

  const AddAccountSheet({super.key, this.existing, this.allAccounts = const []});

  @override
  State<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<AddAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  AccountType _selectedType = AccountType.ASSET;
  int? _selectedCashBoxId;
  int? _selectedParentId;
  String _currency = 'YER';
  bool _isSaving = false;

  /// Currency display info.
  static const Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  List<Map<String, dynamic>> _cashBoxes = [];

  final _typeOptions = [
    (AccountType.ASSET, 'الأصول', Icons.business),
    (AccountType.LIABILITY, 'الخصوم', Icons.savings),
    (AccountType.EQUITY, 'حقوق الملكية', Icons.account_balance),
    (AccountType.COST, 'التكاليف', Icons.south_west),
    (AccountType.REVENUE, 'الإيرادات', Icons.arrow_outward),
    (AccountType.EXPENSE, 'المصاريف', Icons.arrow_downward),
  ];

  bool get _isEdit => widget.existing != null;

  /// Get accounts that can be parent accounts (excluding self and descendants to avoid cycles)
  List<Account> get _parentCandidates {
    if (_isEdit && widget.existing != null) {
      // Collect all descendant IDs to exclude
      final descendantIds = <int>{};
      void collectDescendants(int parentId) {
        for (final a in widget.allAccounts) {
          if (a.parentId == parentId && a.id != null) {
            descendantIds.add(a.id!);
            collectDescendants(a.id!);
          }
        }
      }
      if (widget.existing!.id != null) {
        descendantIds.add(widget.existing!.id!);
        collectDescendants(widget.existing!.id!);
      }
      return widget.allAccounts.where((a) => a.id != null && !descendantIds.contains(a.id)).toList();
    }
    return widget.allAccounts;
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedType = widget.existing!.accountType;
      _nameController.text = widget.existing!.nameAr;
      _codeController.text = widget.existing!.accountCode;
      _selectedCashBoxId = widget.existing!.linkedCashBoxId;
      _selectedParentId = widget.existing!.parentId;
      _currency = widget.existing!.currency;
    }
    _loadCashBoxes();
    _generateCode();
  }

  Future<void> _loadCashBoxes() async {
    final db = DatabaseHelper();
    final cashBoxes = await db.getAllCashBoxes();
    setState(() => _cashBoxes = cashBoxes);
  }

  Future<void> _generateCode() async {
    if (_isEdit) return;
    final db = DatabaseHelper();
    final code = await db.getNextAccountCode(_selectedType.name);
    if (mounted) {
      _codeController.text = code;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final account = Account(
      id: widget.existing?.id,
      nameAr: _nameController.text.trim(),
      nameEn: _nameController.text.trim(),
      parentId: _selectedParentId,
      accountCode: _codeController.text.trim(),
      accountType: _selectedType,
      currency: _currency,
      balance: widget.existing?.balance ?? 0.0,
      balanceType: widget.existing?.balanceType ?? (_selectedType == AccountType.ASSET || _selectedType == AccountType.COST || _selectedType == AccountType.EXPENSE ? 'debit' : 'credit'),
      linkedCashBoxId: _selectedCashBoxId,
      isSystem: widget.existing?.isSystem ?? false,
      isActive: widget.existing?.isActive ?? true,
      debtCeiling: widget.existing?.debtCeiling ?? 0.0,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final db = DatabaseHelper();
    if (_isEdit) {
      await db.updateAccount(account.id!, account.toMap());
    } else {
      await db.insertAccount(account.toMap());
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ${_isEdit ? 'تعديل' : 'إضافة'} الحساب بنجاح'), backgroundColor: AppColors.success),
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
              Text(_isEdit ? 'تعديل حساب' : 'إضافة حساب جديد',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),

              // Main account type
              Text('الحساب الرئيسي', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _typeOptions.map((opt) {
                  final selected = _selectedType == opt.$1;
                  return ChoiceChip(
                    avatar: Icon(opt.$3, size: 16),
                    label: Text(opt.$2),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedType = opt.$1);
                      _generateCode();
                    },
                    selectedColor: AppColors.primary.withOpacity(0.15),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Account name
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الحساب',
                  prefixIcon: Icon(Icons.text_fields),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الحساب مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // Account code
              TextFormField(
                controller: _codeController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'رقم الترتيب',
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'توليد رقم جديد',
                    onPressed: _generateCode,
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'رقم الترتيب مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // Parent account dropdown
              Builder(builder: (context) {
                // Ensure selected value exists in items to avoid assertion error
                final validParentIds = _parentCandidates.map((a) => a.id).toSet();
                final effectiveParentId = (_selectedParentId != null && validParentIds.contains(_selectedParentId))
                    ? _selectedParentId : null;
                return DropdownButtonFormField<int>(
                  value: effectiveParentId,
                  decoration: const InputDecoration(
                    labelText: 'الحساب الأب',
                    prefixIcon: Icon(Icons.account_tree),
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('حساب رئيسي (بدون أب)')),
                    ..._parentCandidates.map((account) => DropdownMenuItem<int>(
                      value: account.id,
                      child: Text(
                        '${account.accountCode} - ${account.nameAr}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                  onChanged: (v) => setState(() => _selectedParentId = v),
                );
              }),
              const SizedBox(height: 14),

              // Currency selection
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(
                  labelText: 'العملة',
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
              const SizedBox(height: 14),

              // Linked cash box
              DropdownButtonFormField<int>(
                value: _selectedCashBoxId,
                decoration: const InputDecoration(
                  labelText: 'حساب الصندوق المرتبط',
                  prefixIcon: Icon(Icons.link),
                ),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('بدون ربط')),
                  ..._cashBoxes.map((cb) => DropdownMenuItem<int>(
                    value: cb['id'] as int,
                    child: Text(cb['name'] as String, overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) => setState(() => _selectedCashBoxId = v),
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
