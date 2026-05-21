import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/product_model.dart';

/// Full-screen form for adding a new product with complete accounting fields.
class AddProductSheet extends StatefulWidget {
  const AddProductSheet({super.key});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // ── Controllers ───────────────────────────────────────────────
  final _itemCodeController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _nameArController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _groupIdController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _specialWholesalePriceController = TextEditingController();
  final _minimumSalePriceController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _currentStockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  // ── Dropdown state ────────────────────────────────────────────
  int? _selectedCategoryId;
  int? _selectedUnitId;
  int? _selectedSupplierId;
  int? _selectedWarehouseId;
  int? _selectedSalesAccountId;
  int? _selectedPurchaseAccountId;
  int? _selectedInventoryAccountId;

  // ── Checkbox / date state ─────────────────────────────────────
  DateTime? _expiryDate;
  bool _expiryTracking = false;
  bool _includeInReports = true;
  bool _isActive = true;
  bool _isSaving = false;

  // ── Dropdown data from DB ─────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _salesAccounts = [];
  List<Map<String, dynamic>> _purchaseAccounts = [];
  List<Map<String, dynamic>> _inventoryAccounts = [];

  // ── Units (static) ────────────────────────────────────────────
  static const _units = [
    {'id': 1, 'name': 'قطعة'},
    {'id': 2, 'name': 'كيلو'},
    {'id': 3, 'name': 'لتر'},
    {'id': 4, 'name': 'متر'},
    {'id': 5, 'name': 'علبة'},
    {'id': 6, 'name': 'كرتون'},
    {'id': 7, 'name': 'طن'},
    {'id': 8, 'name': 'جرام'},
  ];

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
    _generateItemCode();
    _taxRateController.text = AppConstants.defaultVatRate.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _itemCodeController.dispose();
    _barcodeController.dispose();
    _nameArController.dispose();
    _nameEnController.dispose();
    _groupIdController.dispose();
    _descriptionController.dispose();
    _costPriceController.dispose();
    _sellPriceController.dispose();
    _wholesalePriceController.dispose();
    _specialWholesalePriceController.dispose();
    _minimumSalePriceController.dispose();
    _taxRateController.dispose();
    _currentStockController.dispose();
    _minStockController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdownData() async {
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCategories(),
      db.getAllSuppliers(),
      db.getAllWarehouses(),
      db.getAccountsByType('REVENUE'),
      db.getAccountsByType('EXPENSE'),
      db.getAccountsByType('ASSET'),
    ]);

    if (!mounted) return;
    setState(() {
      _categories = results[0];
      _suppliers = results[1];
      _warehouses = results[2];
      _salesAccounts = results[3];
      _purchaseAccounts = results[4];
      _inventoryAccounts = results[5];
    });
  }

  Future<void> _generateItemCode() async {
    final code = await DatabaseHelper().getNextItemCode();
    if (mounted) {
      _itemCodeController.text = code;
    }
  }

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final product = Product(
      itemCode: _itemCodeController.text.trim().isNotEmpty
          ? _itemCodeController.text.trim()
          : null,
      nameAr: _nameArController.text.trim(),
      nameEn: _nameEnController.text.trim(),
      barcode: _barcodeController.text.trim().isNotEmpty
          ? _barcodeController.text.trim()
          : null,
      categoryId: _selectedCategoryId,
      unitId: _selectedUnitId,
      supplierId: _selectedSupplierId,
      groupId: _groupIdController.text.trim().isNotEmpty
          ? _groupIdController.text.trim()
          : null,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      costPrice: double.tryParse(_costPriceController.text) ?? 0.0,
      sellPrice: double.tryParse(_sellPriceController.text) ?? 0.0,
      wholesalePrice: double.tryParse(_wholesalePriceController.text) ?? 0.0,
      specialWholesalePrice:
          double.tryParse(_specialWholesalePriceController.text) ?? 0.0,
      minimumSalePrice:
          double.tryParse(_minimumSalePriceController.text) ?? 0.0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0.0,
      salesAccountId: _selectedSalesAccountId,
      purchaseAccountId: _selectedPurchaseAccountId,
      inventoryAccountId: _selectedInventoryAccountId,
      currentStock: double.tryParse(_currentStockController.text) ?? 0.0,
      minStock: double.tryParse(_minStockController.text) ?? 0.0,
      warehouseId: _selectedWarehouseId,
      expiryDate: _expiryDate,
      expiryTracking: _expiryTracking,
      weight: double.tryParse(_weightController.text) ?? 0.0,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      includeInReports: _includeInReports,
      isActive: _isActive,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await DatabaseHelper().insertProduct(product.toMap());
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الحفظ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم إضافة الصنف "${_nameArController.text}" بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );

    Navigator.of(context).pop(true);
  }

  Widget _sectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceField({
    required TextEditingController controller,
    required String label,
    bool required_ = false,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: AppConstants.currency,
      ),
      validator: required_
          ? (v) =>
              (v == null || v.trim().isEmpty) ? '$label مطلوب' : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة صنف جديد'),
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.arrowRight),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        ),
        actions: [
          TextButton.icon(
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
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ══════════════════════════════════════════════════════
              //  Section 1: بيانات أساسية
              // ══════════════════════════════════════════════════════
              _sectionHeader('بيانات أساسية', PhosphorIconsRegular.article),

              // رمز الصنف
              TextFormField(
                controller: _itemCodeController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'رمز الصنف',
                  prefixIcon: const Icon(PhosphorIconsRegular.barcode),
                  suffixIcon: IconButton(
                    icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
                    tooltip: 'توليد رمز جديد',
                    onPressed: _generateItemCode,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // باركود
              TextFormField(
                controller: _barcodeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'باركود',
                  prefixIcon: Icon(PhosphorIconsRegular.barcode),
                ),
              ),
              const SizedBox(height: 14),

              // اسم الصنف بالعربي
              TextFormField(
                controller: _nameArController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف بالعربي *',
                  prefixIcon: Icon(PhosphorIconsRegular.textAa),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'اسم الصنف بالعربي مطلوب'
                    : null,
              ),
              const SizedBox(height: 14),

              // اسم الصنف بالإنجليزي
              TextFormField(
                controller: _nameEnController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف بالإنجليزي',
                  prefixIcon: Icon(PhosphorIconsRegular.textAa),
                ),
              ),
              const SizedBox(height: 14),

              // الوحدة + التصنيف
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedUnitId,
                      decoration: const InputDecoration(
                        labelText: 'الوحدة',
                        prefixIcon: Icon(PhosphorIconsRegular.ruler),
                      ),
                      items: _units
                          .map((u) => DropdownMenuItem<int>(
                                value: u['id'] as int,
                                child: Text(u['name'] as String, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedUnitId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        prefixIcon: Icon(PhosphorIconsRegular.folder),
                      ),
                      items: _categories
                          .map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int,
                                child: Text(c['name'] as String, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedCategoryId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // المجموعة + المورد الافتراضي
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _groupIdController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'المجموعة',
                        prefixIcon: Icon(PhosphorIconsRegular.package),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'المورد',
                        prefixIcon: Icon(PhosphorIconsRegular.truck),
                      ),
                      items: _suppliers
                          .map((s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text(s['name'] as String, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedSupplierId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // وصف الصنف
              TextFormField(
                controller: _descriptionController,
                textInputAction: TextInputAction.next,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'وصف الصنف',
                  prefixIcon: Icon(PhosphorIconsRegular.notepad),
                  alignLabelWithHint: true,
                ),
              ),

              // ══════════════════════════════════════════════════════
              //  Section 2: الأسعار
              // ══════════════════════════════════════════════════════
              _sectionHeader('الأسعار', PhosphorIconsRegular.tag),

              // سعر التكلفة + سعر البيع
              Row(
                children: [
                  Expanded(
                    child: _priceField(
                      controller: _costPriceController,
                      label: 'سعر التكلفة *',
                      required_: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _priceField(
                      controller: _sellPriceController,
                      label: 'سعر البيع *',
                      required_: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // الحد الأدنى للبيع + نسبة الضريبة
              Row(
                children: [
                  Expanded(
                    child: _priceField(
                      controller: _minimumSalePriceController,
                      label: 'الحد الأدنى للبيع',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _taxRateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'نسبة الضريبة %',
                        suffixText: '%',
                        prefixIcon: Icon(PhosphorIconsRegular.receipt),
                      ),
                    ),
                  ),
                ],
              ),

              // ══════════════════════════════════════════════════════
              //  Section 3: المخزون
              // ══════════════════════════════════════════════════════
              _sectionHeader('المخزون', PhosphorIconsRegular.warehouse),

              // الكمية الحالية + الحد الأدنى
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _currentStockController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'الكمية الحالية',
                        prefixIcon: Icon(PhosphorIconsRegular.stack),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStockController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'الحد الأدنى',
                        prefixIcon: Icon(PhosphorIconsRegular.warning),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // المخزن
              DropdownButtonFormField<int>(
                value: _selectedWarehouseId,
                decoration: const InputDecoration(
                  labelText: 'المخزن',
                  prefixIcon: Icon(PhosphorIconsRegular.warehouse),
                ),
                items: _warehouses
                    .map((w) => DropdownMenuItem<int>(
                          value: w['id'] as int,
                          child: Text(w['name'] as String, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedWarehouseId = v),
              ),
              const SizedBox(height: 14),

              // تاريخ الصلاحية
              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                  text: _expiryDate != null
                      ? '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
                      : '',
                ),
                decoration: InputDecoration(
                  labelText: 'تاريخ الصلاحية',
                  prefixIcon: const Icon(PhosphorIconsRegular.calendar),
                  hintText: 'اختر التاريخ',
                  suffixIcon: IconButton(
                    icon: const Icon(PhosphorIconsRegular.calendarDots, size: 20),
                    onPressed: _pickDate,
                  ),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 10),

              // تتبع الصلاحية + الوزن
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _expiryTracking,
                      onChanged: (v) =>
                          setState(() => _expiryTracking = v ?? false),
                      title: const Text('تتبع الصلاحية'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'الوزن',
                        suffixText: 'كجم',
                        prefixIcon: Icon(PhosphorIconsRegular.scales),
                      ),
                    ),
                  ),
                ],
              ),

              // ══════════════════════════════════════════════════════
              //  Section 4: الحسابات
              // ══════════════════════════════════════════════════════
              _sectionHeader('الحسابات', PhosphorIconsRegular.chartPie),

              // حساب المبيعات
              DropdownButtonFormField<int>(
                value: _selectedSalesAccountId,
                decoration: const InputDecoration(
                  labelText: 'حساب المبيعات',
                  prefixIcon: Icon(PhosphorIconsRegular.arrowUpRight),
                ),
                items: _salesAccounts
                    .map((a) => DropdownMenuItem<int>(
                          value: a['id'] as int,
                          child: Text(
                            '${a['account_code']} - ${a['name_ar']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedSalesAccountId = v),
              ),
              const SizedBox(height: 14),

              // حساب المشتريات
              DropdownButtonFormField<int>(
                value: _selectedPurchaseAccountId,
                decoration: const InputDecoration(
                  labelText: 'حساب المشتريات',
                  prefixIcon: Icon(PhosphorIconsRegular.arrowDownLeft),
                ),
                items: _purchaseAccounts
                    .map((a) => DropdownMenuItem<int>(
                          value: a['id'] as int,
                          child: Text(
                            '${a['account_code']} - ${a['name_ar']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(
                    () => _selectedPurchaseAccountId = v),
              ),
              const SizedBox(height: 14),

              // حساب المخزون
              DropdownButtonFormField<int>(
                value: _selectedInventoryAccountId,
                decoration: const InputDecoration(
                  labelText: 'حساب المخزون',
                  prefixIcon: Icon(PhosphorIconsRegular.archive),
                ),
                items: _inventoryAccounts
                    .map((a) => DropdownMenuItem<int>(
                          value: a['id'] as int,
                          child: Text(
                            '${a['account_code']} - ${a['name_ar']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedInventoryAccountId = v),
              ),

              // ══════════════════════════════════════════════════════
              //  Section 5: إعدادات أخرى
              // ══════════════════════════════════════════════════════
              _sectionHeader('إعدادات أخرى', PhosphorIconsRegular.gearSix),

              TextFormField(
                controller: _notesController,
                textInputAction: TextInputAction.newline,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  prefixIcon: Icon(PhosphorIconsRegular.notepad),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _includeInReports,
                      onChanged: (v) =>
                          setState(() => _includeInReports = v ?? true),
                      title: const Text('تضمين في التقارير'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      value: _isActive,
                      onChanged: (v) =>
                          setState(() => _isActive = v ?? true),
                      title: const Text('الصنف نشط'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      dense: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Action buttons ─────────────────────────────────
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
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(PhosphorIconsRegular.check, size: 20),
                      label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الصنف'),
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
                          : () => Navigator.of(context).pop(false),
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
