import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// Modal bottom sheet for adding a new product.
///
/// All fields are in Arabic and RTL. Includes dropdown selectors
/// for category and supplier, a date picker for expiry, and
/// a checkbox for report inclusion.
class AddProductSheet extends StatefulWidget {
  const AddProductSheet({super.key});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ───────────────────────────────────────────────
  final _serialController = TextEditingController();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _quantityController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();

  // ── State ─────────────────────────────────────────────────────
  String? _selectedCategory;
  String? _selectedSupplier;
  DateTime? _expiryDate;
  bool _includeInReports = true;
  bool _isSaving = false;

  // ── Demo dropdown options ─────────────────────────────────────
  static const _categories = [
    'إلكترونيات',
    'أجهزة منزلية',
    'ملابس',
    'مواد غذائية',
    'مستلزمات مكتبية',
  ];

  static const _suppliers = [
    'شركة الأمل للتجارة',
    'مؤسسة النور',
    'شركة التقنية المتقدمة',
    'مصنع الخليج',
  ];

  @override
  void initState() {
    super.initState();
    // Auto-generate a demo serial number
    _serialController.text = 'PRD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
  }

  @override
  void dispose() {
    _serialController.dispose();
    _nameController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _costPriceController.dispose();
    _sellPriceController.dispose();
    _wholesalePriceController.dispose();
    super.dispose();
  }

  // ── Date picker ───────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      locale: const Locale(AppConstants.defaultLanguage),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  // ── Save handler ──────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // TODO: Replace with actual data-source insertion
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم إضافة المنتج "${_nameController.text}" بنجاح'),
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
                'إضافة منتج جديد',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── الرقم التسلسلي (auto-generated) ───────────────
              TextFormField(
                controller: _serialController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'الرقم التسلسلي',
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'توليد رقم جديد',
                    onPressed: () {
                      _serialController.text =
                          'PRD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── اسم الصنف ─────────────────────────────────────
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'اسم الصنف مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // ── الوحدة ────────────────────────────────────────
              TextFormField(
                controller: _unitController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الوحدة',
                  prefixIcon: Icon(Icons.straighten),
                  hintText: 'مثال: قطعة، كيلو، لتر',
                ),
              ),
              const SizedBox(height: 14),

              // ── التصنيف (dropdown) ─────────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) => v == null ? 'التصنيف مطلوب' : null,
              ),
              const SizedBox(height: 14),

              // ── المورد (dropdown) ──────────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _selectedSupplier,
                decoration: const InputDecoration(
                  labelText: 'المورد',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                items: _suppliers
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedSupplier = v),
              ),
              const SizedBox(height: 14),

              // ── الكمية ────────────────────────────────────────
              TextFormField(
                controller: _quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'الكمية',
                  prefixIcon: Icon(Icons.calculate_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // ── تاريخ الصلاحية (date picker) ──────────────────
              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                  text: _expiryDate != null
                      ? '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
                      : '',
                ),
                decoration: InputDecoration(
                  labelText: 'تاريخ الصلاحية',
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  hintText: 'اختر التاريخ',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.event, size: 20),
                    onPressed: _pickDate,
                  ),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),

              // ── Prices row ─────────────────────────────────────
              Row(
                children: [
                  // سعر الشراء
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'سعر الشراء',
                        suffixText: AppConstants.currency,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // سعر البيع
                  Expanded(
                    child: TextFormField(
                      controller: _sellPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'سعر البيع',
                        suffixText: AppConstants.currency,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'سعر البيع مطلوب'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── سعر الجملة ────────────────────────────────────
              TextFormField(
                controller: _wholesalePriceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'سعر الجملة',
                  suffixText: AppConstants.currency,
                ),
              ),
              const SizedBox(height: 18),

              // ── Checkbox: تضمين في التقارير ───────────────────
              CheckboxListTile(
                value: _includeInReports,
                onChanged: (v) =>
                    setState(() => _includeInReports = v ?? true),
                title: const Text('تضمين الصنف في التقارير'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
                dense: true,
              ),
              const SizedBox(height: 20),

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
