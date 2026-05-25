import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/barcode_scanner_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step definitions
// ═══════════════════════════════════════════════════════════════════

class _StepDef {
  final String title;
  final IconData icon;
  const _StepDef(this.title, this.icon);
}

const _steps = [
  _StepDef('البيانات الأساسية', Icons.article),
  _StepDef('الوحدات', Icons.straighten),
  _StepDef('الأسعار', Icons.label),
  _StepDef('المخزون', Icons.inventory),
  _StepDef('الموردين', Icons.local_shipping),
  _StepDef('الباركود', Icons.qr_code),
  _StepDef('إعدادات البيع', Icons.storefront),
  _StepDef('المحاسبة', Icons.account_balance),
];

// ═══════════════════════════════════════════════════════════════════
//  Unit conversion row model
// ═══════════════════════════════════════════════════════════════════

class _UnitConversionRow {
  int? unitId;
  double factor;
  String barcode;
  double sellPrice;

  _UnitConversionRow({
    this.unitId,
    this.factor = 1.0,
    this.barcode = '',
    this.sellPrice = 0.0,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  AddProductSheet – multi-step wizard
// ═══════════════════════════════════════════════════════════════════

class AddProductSheet extends StatefulWidget {
  final Product? existing;
  const AddProductSheet({super.key, this.existing});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  // ── Step state ────────────────────────────────────────────────
  int _currentStep = 0;
  final PageController _pageController = PageController();

  // ── Form key ──────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ───────────────────────────────────────────────
  final _nameArController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _itemCodeController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _specialWholesalePriceController = TextEditingController();
  final _minimumSalePriceController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _openingStockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();
  final _supplierCodeController = TextEditingController();

  // ── Dropdown / switch state ───────────────────────────────────
  int? _selectedCategoryId;
  int? _selectedBaseUnitId;
  int? _selectedPurchaseUnitId;
  int? _selectedSaleUnitId;
  int? _selectedWarehouseId;
  int? _selectedSupplierId;
  int? _selectedSalesAccountId;
  int? _selectedPurchaseAccountId;
  int? _selectedInventoryAccountId;

  bool _isActive = true;
  bool _trackStock = true;
  bool _expiryTracking = false;
  bool _taxInclusive = false;
  bool _isSellable = true;
  bool _isPurchasable = true;
  bool _allowNegative = false;
  bool _sellRetail = true;
  bool _showInPos = true;

  DateTime? _expiryDate;
  String? _imagePath;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  // ── Unit conversions ──────────────────────────────────────────
  List<_UnitConversionRow> _unitConversions = [];

  // ── Dropdown data from DB ─────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _revenueAccounts = [];
  List<Map<String, dynamic>> _expenseAccounts = [];
  List<Map<String, dynamic>> _assetAccounts = [];

  // ── Helper: get unit name by id ───────────────────────────────
  String _unitNameById(int? id) {
    if (id == null) return '';
    final match = _units.where((u) => u['id'] == id);
    if (match.isNotEmpty) return match.first['name_ar'] as String? ?? '';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
    if (_isEditMode) {
      _populateFromExisting();
      _loadUnitConversions();
    } else {
      _generateItemCode();
      _taxRateController.text = AppConstants.defaultVatRate.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _nameArController.dispose();
    _nameEnController.dispose();
    _itemCodeController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _costPriceController.dispose();
    _sellPriceController.dispose();
    _wholesalePriceController.dispose();
    _specialWholesalePriceController.dispose();
    _minimumSalePriceController.dispose();
    _taxRateController.dispose();
    _openingStockController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _supplierCodeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Load reference data ───────────────────────────────────────

  Future<void> _loadDropdownData() async {
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCategories(),
      db.getAllUnits(),
      db.getAllSuppliers(),
      db.getAllWarehouses(),
      db.getAccountsByType('REVENUE'),
      db.getAccountsByType('EXPENSE'),
      db.getAccountsByType('ASSET'),
    ]);

    if (!mounted) return;
    setState(() {
      _categories = results[0];
      _units = results[1];
      _suppliers = results[2];
      _warehouses = results[3];
      _revenueAccounts = results[4];
      _expenseAccounts = results[5];
      _assetAccounts = results[6];
    });
  }

  Future<void> _generateItemCode() async {
    final code = await DatabaseHelper().getNextItemCode();
    if (mounted) {
      _itemCodeController.text = code;
    }
  }

  void _populateFromExisting() {
    final p = widget.existing!;
    _itemCodeController.text = p.itemCode ?? '';
    _barcodeController.text = p.barcode ?? '';
    _nameArController.text = p.nameAr;
    _nameEnController.text = p.nameEn;
    _descriptionController.text = p.description ?? '';
    _costPriceController.text = p.costPrice.toStringAsFixed(2);
    _sellPriceController.text = p.sellPrice.toStringAsFixed(2);
    _wholesalePriceController.text = p.wholesalePrice.toStringAsFixed(2);
    _specialWholesalePriceController.text = p.specialWholesalePrice.toStringAsFixed(2);
    _minimumSalePriceController.text = p.minimumSalePrice.toStringAsFixed(2);
    _taxRateController.text = p.taxRate.toStringAsFixed(2);
    _minStockController.text = p.minStock.toStringAsFixed(0);
    _supplierCodeController.text = p.supplierCode ?? '';
    _notesController.text = p.notes ?? '';

    _selectedCategoryId = p.categoryId;
    _selectedBaseUnitId = p.effectiveBaseUnitId;
    _selectedPurchaseUnitId = p.purchaseUnitId;
    _selectedSaleUnitId = p.saleUnitId;
    _selectedWarehouseId = p.warehouseId;
    _selectedSupplierId = p.supplierId;
    _selectedSalesAccountId = p.salesAccountId;
    _selectedPurchaseAccountId = p.purchaseAccountId;
    _selectedInventoryAccountId = p.inventoryAccountId;

    _isActive = p.isActive;
    _trackStock = p.trackStock;
    _expiryTracking = p.expiryTracking;
    _taxInclusive = p.taxInclusive;
    _isSellable = p.isSellable;
    _isPurchasable = p.isPurchasable;
    _allowNegative = p.allowNegative;
    _sellRetail = p.sellRetail;
    _showInPos = p.showInPos;

    _expiryDate = p.expiryDate;
    _imagePath = p.imagePath;
  }

  Future<void> _loadUnitConversions() async {
    if (widget.existing?.id == null) return;
    final db = DatabaseHelper();
    final conversions = await db.getUnitConversions(widget.existing!.id!);
    if (!mounted) return;
    setState(() {
      _unitConversions = conversions.map((c) {
        final fromUnitId = c['from_unit_id'] as int?;
        return _UnitConversionRow(
          unitId: fromUnitId,
          factor: (c['conversion_factor'] as num?)?.toDouble() ?? 1.0,
          barcode: (c['barcode'] as String?) ?? '',
          sellPrice: (c['sell_price'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    });
  }

  // ── Image picker ──────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}.${picked.name.split('.').last}';
      final savedPath = '${dir.path}/$fileName';
      await File(picked.path).copy(savedPath);
      setState(() => _imagePath = savedPath);
    }
  }

  // ── Barcode scanner ──────────────────────────────────────────

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null && result.isNotEmpty) {
      _barcodeController.text = result;
    }
  }

  // ── Date picker ──────────────────────────────────────────────

  Future<void> _pickExpiryDate() async {
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

  // ── Navigation ───────────────────────────────────────────────

  void _goToStep(int step) {
    if (step < 0 || step >= _steps.length) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0: // البيانات الأساسية
        if (_nameArController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اسم الصنف بالعربي مطلوب'),
              backgroundColor: AppColors.error,
            ),
          );
          return false;
        }
        return true;
      case 1: // الوحدات
        if (_selectedBaseUnitId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الوحدة الأساسية مطلوبة'),
              backgroundColor: AppColors.error,
            ),
          );
          return false;
        }
        return true;
      case 2: // الأسعار
        if (_costPriceController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('سعر التكلفة مطلوب'),
              backgroundColor: AppColors.error,
            ),
          );
          return false;
        }
        if (_sellPriceController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('سعر البيع مطلوب'),
              backgroundColor: AppColors.error,
            ),
          );
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_currentStep < _steps.length - 1) {
      _goToStep(_currentStep + 1);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  // ── Save ─────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_validateCurrentStep()) return;

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final costPrice = double.tryParse(_costPriceController.text) ?? 0.0;
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
      unitId: _selectedBaseUnitId,
      baseUnitId: _selectedBaseUnitId,
      purchaseUnitId: _selectedPurchaseUnitId,
      saleUnitId: _selectedSaleUnitId,
      supplierId: _selectedSupplierId,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      costPrice: costPrice,
      averageCost: costPrice,
      sellPrice: double.tryParse(_sellPriceController.text) ?? 0.0,
      wholesalePrice: double.tryParse(_wholesalePriceController.text) ?? 0.0,
      specialWholesalePrice:
          double.tryParse(_specialWholesalePriceController.text) ?? 0.0,
      minimumSalePrice:
          double.tryParse(_minimumSalePriceController.text) ?? 0.0,
      taxRate: double.tryParse(_taxRateController.text) ?? 0.0,
      taxInclusive: _taxInclusive,
      salesAccountId: _selectedSalesAccountId,
      purchaseAccountId: _selectedPurchaseAccountId,
      inventoryAccountId: _selectedInventoryAccountId,
      currentStock: _isEditMode
          ? widget.existing!.currentStock
          : (double.tryParse(_openingStockController.text) ?? 0.0),
      minStock: double.tryParse(_minStockController.text) ?? 0.0,
      warehouseId: _isEditMode ? widget.existing!.warehouseId : _selectedWarehouseId,
      expiryDate: _expiryDate,
      expiryTracking: _expiryTracking,
      trackStock: _trackStock,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      isActive: _isActive,
      isSellable: _isSellable,
      isPurchasable: _isPurchasable,
      allowNegative: _allowNegative,
      sellRetail: _sellRetail,
      showInPos: _showInPos,
      imagePath: _imagePath,
      supplierCode: _supplierCodeController.text.trim().isNotEmpty
          ? _supplierCodeController.text.trim()
          : null,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final db = DatabaseHelper();

      if (_isEditMode) {
        final updateMap = product.toMap();
        // Lock system-managed fields
        updateMap['current_stock'] = widget.existing!.currentStock;
        updateMap['warehouse_id'] = widget.existing!.warehouseId;
        updateMap['sales_account_id'] = widget.existing!.salesAccountId;
        updateMap['purchase_account_id'] = widget.existing!.purchaseAccountId;
        updateMap['inventory_account_id'] = widget.existing!.inventoryAccountId;
        updateMap['image_path'] = _imagePath;
        await db.updateProduct(widget.existing!.id!, updateMap);

        // Replace unit conversions
        final productId = widget.existing!.id!;
        final existingConvs = await db.getUnitConversions(productId);
        for (final ec in existingConvs) {
          await db.deleteUnitConversion(ec['id'] as int);
        }
        for (final uc in _unitConversions) {
          if (uc.unitId == null) continue;
          final unitName = _unitNameById(uc.unitId);
          await db.insertUnitConversion({
            'product_id': productId,
            'from_unit': unitName,
            'to_unit': _unitNameById(_selectedBaseUnitId),
            'from_unit_id': uc.unitId,
            'to_unit_id': _selectedBaseUnitId,
            'conversion_factor': uc.factor,
            'barcode': uc.barcode,
            'sell_price': uc.sellPrice,
            'is_active': 1,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } else {
        final map = product.toMap();
        map['image_path'] = _imagePath;
        final savedId = await db.insertProduct(map);

        // Save unit conversions
        if (savedId > 0) {
          for (final uc in _unitConversions) {
            if (uc.unitId == null) continue;
            final unitName = _unitNameById(uc.unitId);
            await db.insertUnitConversion({
              'product_id': savedId,
              'from_unit': unitName,
              'to_unit': _unitNameById(_selectedBaseUnitId),
              'from_unit_id': uc.unitId,
              'to_unit_id': _selectedBaseUnitId,
              'conversion_factor': uc.factor,
              'barcode': uc.barcode,
              'sell_price': uc.sellPrice,
              'is_active': 1,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
          }

          // Opening stock movement
          final openingQty = double.tryParse(_openingStockController.text) ?? 0.0;
          if (openingQty > 0 && _trackStock) {
            await db.logStockMovement(
              productId: savedId,
              movementType: 'opening',
              quantity: openingQty,
              notes: 'رصيد افتتاحي',
              unitCost: costPrice,
            );
          }
        }
      }
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
        content: Text(
          _isEditMode
              ? 'تم تعديل الصنف "${_nameArController.text}" بنجاح'
              : 'تم إضافة الصنف "${_nameArController.text}" بنجاح',
        ),
        backgroundColor: AppColors.success,
      ),
    );

    Navigator.of(context).pop(true);
  }

  // ═══════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'تعديل صنف' : 'إضافة صنف جديد'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Step indicator ──────────────────────────────────
              _buildStepIndicator(),
              const Divider(height: 1),

              // ── Page content ───────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) => _buildStepContent(index),
                ),
              ),

              // ── Navigation bar ─────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPadding),
                child: Row(
                  children: [
                    // السابق
                    if (_currentStep > 0)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _prevStep,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('السابق'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 12),

                    // التالي / حفظ
                    Expanded(
                      child: _currentStep == _steps.length - 1
                          ? ElevatedButton.icon(
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
                            )
                          : ElevatedButton.icon(
                              onPressed: _nextStep,
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('التالي'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step indicator ────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: List.generate(_steps.length, (i) {
          final isActive = i == _currentStep;
          final isCompleted = i < _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (i <= _currentStep || isCompleted) {
                  _goToStep(i);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot / circle
                  Container(
                    width: isActive ? 32 : 24,
                    height: isActive ? 32 : 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted
                          ? AppColors.success
                          : isActive
                              ? AppColors.primary
                              : AppColors.border,
                      border: isActive
                          ? Border.all(color: AppColors.primary, width: 2.5)
                          : null,
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: isActive ? 13 : 11,
                                fontWeight: FontWeight.w700,
                                color: isActive ? Colors.white : AppColors.textTertiary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Label (only show for active/completed or on wider screens)
                  if (isActive || isCompleted)
                    Text(
                      _steps[i].title,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? AppColors.primary
                            : isCompleted
                                ? AppColors.success
                                : AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Step content router ───────────────────────────────────────

  Widget _buildStepContent(int step) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: switch (step) {
        0 => _buildBasicDataStep(),
        1 => _buildUnitsStep(),
        2 => _buildPricesStep(),
        3 => _buildInventoryStep(),
        4 => _buildSuppliersStep(),
        5 => _buildBarcodesStep(),
        6 => _buildSalesSettingsStep(),
        7 => _buildAccountingStep(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 1 – البيانات الأساسية
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBasicDataStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[0].title, _steps[0].icon),

        // ── Image ─────────────────────────────────────────────
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  style: BorderStyle.solid,
                ),
              ),
              child: _imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(_imagePath!),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image,
                          size: 40,
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 32,
                            color: AppColors.primary.withValues(alpha: 0.5)),
                        const SizedBox(height: 6),
                        Text('صورة الصنف',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary.withValues(alpha: 0.7))),
                      ],
                    ),
            ),
          ),
        ),
        if (_imagePath != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _imagePath = null),
              icon: const Icon(Icons.delete, size: 16, color: AppColors.error),
              label: const Text('إزالة الصورة',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // ── اسم الصنف بالعربي * ─────────────────────────────
        TextFormField(
          controller: _nameArController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'اسم الصنف بالعربي *',
            prefixIcon: Icon(Icons.text_fields),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'اسم الصنف بالعربي مطلوب' : null,
        ),
        const SizedBox(height: 14),

        // ── اسم الصنف بالإنجليزي ────────────────────────────
        TextFormField(
          controller: _nameEnController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'اسم الصنف بالإنجليزي',
            prefixIcon: Icon(Icons.text_fields),
          ),
        ),
        const SizedBox(height: 14),

        // ── SKU / رمز الصنف ─────────────────────────────────
        TextFormField(
          controller: _itemCodeController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'SKU / رمز الصنف',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'توليد رمز جديد',
              onPressed: _generateItemCode,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── باركود ──────────────────────────────────────────
        TextFormField(
          controller: _barcodeController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'باركود',
            prefixIcon: const Icon(Icons.qr_code),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_barcodeController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _barcodeController.clear();
                      setState(() {});
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, size: 20),
                  tooltip: 'مسح الباركود بالكاميرا',
                  onPressed: _scanBarcode,
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        // ── التصنيف ─────────────────────────────────────────
        DropdownButtonFormField<int>(
          value: _selectedCategoryId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'التصنيف',
            prefixIcon: Icon(Icons.folder),
          ),
          items: _categories
              .map((c) => DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedCategoryId = v),
        ),
        const SizedBox(height: 14),

        // ── وصف الصنف ───────────────────────────────────────
        TextFormField(
          controller: _descriptionController,
          textInputAction: TextInputAction.next,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'وصف الصنف',
            prefixIcon: Icon(Icons.edit_note),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),

        // ── حالة الصنف ─────────────────────────────────────
        _switchTile(
          title: 'حالة الصنف',
          subtitle: _isActive ? 'نشط' : 'غير نشط',
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: 14),

        // ── ملاحظات ─────────────────────────────────────────
        TextFormField(
          controller: _notesController,
          textInputAction: TextInputAction.done,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'ملاحظات',
            prefixIcon: Icon(Icons.note),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2 – الوحدات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildUnitsStep() {
    final baseUnits = _units.where((u) => (u['is_base_unit'] as int? ?? 0) == 1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[1].title, _steps[1].icon),

        // ── الوحدة الأساسية * ────────────────────────────────
        DropdownButtonFormField<int>(
          value: _selectedBaseUnitId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'الوحدة الأساسية *',
            prefixIcon: Icon(Icons.straighten),
          ),
          items: baseUnits
              .map((u) => DropdownMenuItem<int>(
                    value: u['id'] as int,
                    child: Text(u['name_ar'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedBaseUnitId = v),
          validator: (v) => v == null ? 'الوحدة الأساسية مطلوبة' : null,
        ),
        const SizedBox(height: 14),

        // ── وحدة الشراء الافتراضية ──────────────────────────
        DropdownButtonFormField<int>(
          value: _selectedPurchaseUnitId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'وحدة الشراء الافتراضية',
            prefixIcon: Icon(Icons.shopping_cart),
          ),
          items: _units
              .map((u) => DropdownMenuItem<int>(
                    value: u['id'] as int,
                    child: Text(u['name_ar'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedPurchaseUnitId = v),
        ),
        const SizedBox(height: 14),

        // ── وحدة البيع الافتراضية ────────────────────────────
        DropdownButtonFormField<int>(
          value: _selectedSaleUnitId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'وحدة البيع الافتراضية',
            prefixIcon: Icon(Icons.sell),
          ),
          items: _units
              .map((u) => DropdownMenuItem<int>(
                    value: u['id'] as int,
                    child: Text(u['name_ar'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedSaleUnitId = v),
        ),
        const SizedBox(height: 20),

        // ── جدول التحويلات ──────────────────────────────────
        Row(
          children: [
            Icon(Icons.swap_horiz, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'جدول التحويلات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addConversionRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة تحويل'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Info card
        if (_selectedBaseUnitId != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الوحدة الأساسية: ${_unitNameById(_selectedBaseUnitId)}. حدد كم تساوي الوحدة الأكبر بالوحدة الأساسية.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                        ),
                  ),
                ),
              ],
            ),
          ),

        // Conversion rows
        if (_unitConversions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 40, color: AppColors.textTertiary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('لا توجد تحويلات',
                      style: TextStyle(
                          color: AppColors.textTertiary.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text('اضغط "إضافة تحويل" لإضافة وحدة أكبر',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          )),
                ],
              ),
            ),
          )
        else ...[
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Expanded(flex: 3, child: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                Expanded(flex: 3, child: Text('كم تساوي بالوحدة الأساسية؟', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                const Expanded(flex: 2, child: Text('سعر البيع', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...List.generate(_unitConversions.length, (i) {
            final row = _unitConversions[i];
            return _buildConversionRow(row, i);
          }),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildConversionRow(_UnitConversionRow row, int index) {
    final baseUnitName = _unitNameById(_selectedBaseUnitId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Unit dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              value: row.unitId,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'الوحدة',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              items: _units
                  .where((u) => u['id'] != _selectedBaseUnitId)
                  .map((u) => DropdownMenuItem<int>(
                        value: u['id'] as int,
                        child: Text(u['name_ar'] as String,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => row.unitId = v),
            ),
          ),
          const SizedBox(width: 6),

          // Factor field – smart label
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: row.factor == 1.0 ? '' : row.factor.toStringAsFixed(0),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: row.unitId != null
                    ? '${_unitNameById(row.unitId)} كم $baseUnitName؟'
                    : 'الكمية',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (v) => row.factor = double.tryParse(v) ?? 1.0,
            ),
          ),
          const SizedBox(width: 6),

          // Sell price
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: row.sellPrice > 0 ? row.sellPrice.toStringAsFixed(2) : '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: 'سعر البيع',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (v) => row.sellPrice = double.tryParse(v) ?? 0.0,
            ),
          ),

          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: AppColors.error.withValues(alpha: 0.7)),
            onPressed: () =>
                setState(() => _unitConversions.removeAt(index)),
          ),
        ],
      ),
    );
  }

  void _addConversionRow() {
    setState(() {
      _unitConversions.add(_UnitConversionRow());
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 3 – الأسعار
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPricesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[2].title, _steps[2].icon),

        // سعر التكلفة + سعر البيع
        Row(
          children: [
            Expanded(
              child: _priceField(
                controller: _costPriceController,
                label: 'سعر التكلفة *',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _priceField(
                controller: _sellPriceController,
                label: 'سعر البيع *',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // سعر الجملة + سعر الجملة الخاصة
        Row(
          children: [
            Expanded(
              child: _priceField(
                controller: _wholesalePriceController,
                label: 'سعر الجملة',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _priceField(
                controller: _specialWholesalePriceController,
                label: 'سعر الجملة الخاصة',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // أقل سعر بيع
        _priceField(
          controller: _minimumSalePriceController,
          label: 'أقل سعر بيع',
        ),
        const SizedBox(height: 14),

        // الضريبة
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _taxRateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'الضريبة %',
                  suffixText: '%',
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _switchTile(
                title: 'السعر شامل الضريبة',
                subtitle: _taxInclusive ? 'نعم' : 'لا',
                value: _taxInclusive,
                onChanged: (v) => setState(() => _taxInclusive = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4 – المخزون
  // ═══════════════════════════════════════════════════════════════

  Widget _buildInventoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[3].title, _steps[3].icon),

        // تتبع المخزون
        _switchTile(
          title: 'تتبع المخزون',
          subtitle: _trackStock ? 'مفعّل' : 'معطّل',
          value: _trackStock,
          onChanged: (v) => setState(() => _trackStock = v),
        ),
        const SizedBox(height: 14),

        // كمية افتتاحية (new products only)
        if (!_isEditMode) ...[
          TextFormField(
            controller: _openingStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: 'كمية افتتاحية',
              prefixIcon: const Icon(Icons.inventory),
              suffixText: _unitNameById(_selectedBaseUnitId),
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          // Show current stock (locked)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock, size: 18, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  'الرصيد الحالي: ${widget.existing?.currentStock.toStringAsFixed(0) ?? '0'} ${_unitNameById(_selectedBaseUnitId)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],

        // مستودع افتراضي
        DropdownButtonFormField<int>(
          value: _selectedWarehouseId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'مستودع افتراضي',
            prefixIcon: Icon(Icons.warehouse),
          ),
          items: _warehouses
              .map((w) => DropdownMenuItem<int>(
                    value: w['id'] as int,
                    child: Text(w['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _isEditMode
              ? null // locked in edit mode
              : (v) => setState(() => _selectedWarehouseId = v),
        ),
        const SizedBox(height: 14),

        // الحد الأدنى + الحد الأعلى
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minStockController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'الحد الأدنى',
                  prefixIcon: const Icon(Icons.vertical_align_bottom),
                  suffixText: _unitNameById(_selectedBaseUnitId),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _maxStockController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'الحد الأعلى',
                  prefixIcon: const Icon(Icons.vertical_align_top),
                  suffixText: _unitNameById(_selectedBaseUnitId),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // تتبع الصلاحية
        _switchTile(
          title: 'تتبع الصلاحية',
          subtitle: _expiryTracking ? 'مفعّل' : 'معطّل',
          value: _expiryTracking,
          onChanged: (v) => setState(() => _expiryTracking = v),
        ),
        if (_expiryTracking) ...[
          const SizedBox(height: 10),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.calendar_today, size: 20),
            title: Text(
              _expiryDate != null
                  ? 'تاريخ الانتهاء: ${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                  : 'تحديد تاريخ الانتهاء',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: _pickExpiryDate,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 5 – الموردين
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSuppliersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[4].title, _steps[4].icon),

        // المورد الافتراضي
        DropdownButtonFormField<int>(
          value: _selectedSupplierId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'المورد الافتراضي',
            prefixIcon: Icon(Icons.local_shipping),
          ),
          items: _suppliers
              .map((s) => DropdownMenuItem<int>(
                    value: s['id'] as int,
                    child: Text(s['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedSupplierId = v),
        ),
        const SizedBox(height: 14),

        // كود المورد للصنف
        TextFormField(
          controller: _supplierCodeController,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'كود المورد للصنف',
            prefixIcon: Icon(Icons.code),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 6 – الباركود
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBarcodesStep() {
    // Build barcode list: base unit + conversion units
    final List<_BarcodeEntry> barcodes = [];

    // Base unit barcode
    barcodes.add(_BarcodeEntry(
      unitName: _unitNameById(_selectedBaseUnitId) ?? 'الوحدة الأساسية',
      barcode: _barcodeController.text,
    ));

    // Conversion unit barcodes
    for (final uc in _unitConversions) {
      barcodes.add(_BarcodeEntry(
        unitName: _unitNameById(uc.unitId),
        barcode: uc.barcode,
        conversionRow: uc,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[5].title, _steps[5].icon),

        if (barcodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('حدد الوحدة الأساسية أولاً في خطوة الوحدات')),
          )
        else ...[
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Expanded(flex: 3, child: Text('باركود', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              ],
            ),
          ),
          const SizedBox(height: 6),

          ...List.generate(barcodes.length, (i) {
            final entry = barcodes[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Unit name
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.unitName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Barcode field
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: entry.barcode,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'أدخل الباركود',
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onChanged: (v) {
                        if (i == 0) {
                          // Base unit barcode
                          _barcodeController.text = v;
                        } else if (entry.conversionRow != null) {
                          entry.conversionRow!.barcode = v;
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 7 – إعدادات البيع
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSalesSettingsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[6].title, _steps[6].icon),

        _switchTile(
          title: 'يباع؟',
          subtitle: _isSellable ? 'نعم' : 'لا',
          value: _isSellable,
          onChanged: (v) => setState(() => _isSellable = v),
        ),
        const Divider(height: 1),

        _switchTile(
          title: 'يشترى؟',
          subtitle: _isPurchasable ? 'نعم' : 'لا',
          value: _isPurchasable,
          onChanged: (v) => setState(() => _isPurchasable = v),
        ),
        const Divider(height: 1),

        _switchTile(
          title: 'يسمح بالسالب؟',
          subtitle: _allowNegative ? 'نعم' : 'لا',
          value: _allowNegative,
          onChanged: (v) => setState(() => _allowNegative = v),
        ),
        const Divider(height: 1),

        _switchTile(
          title: 'يباع بالتجزئة؟',
          subtitle: _sellRetail ? 'نعم' : 'لا',
          value: _sellRetail,
          onChanged: (v) => setState(() => _sellRetail = v),
        ),
        const Divider(height: 1),

        _switchTile(
          title: 'يظهر في الكاشير؟',
          subtitle: _showInPos ? 'نعم' : 'لا',
          value: _showInPos,
          onChanged: (v) => setState(() => _showInPos = v),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 8 – المحاسبة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAccountingStep() {
    final isLocked = _isEditMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[7].title, _steps[7].icon),

        if (isLocked)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.warningLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الحسابات المحاسبية مقفلة في وضع التعديل - يديرها النظام',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                  ),
                ),
              ],
            ),
          ),

        // حساب المبيعات
        DropdownButtonFormField<int>(
          value: _selectedSalesAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المبيعات',
            prefixIcon: Icon(Icons.trending_up),
          ),
          items: _revenueAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => setState(() => _selectedSalesAccountId = v),
        ),
        const SizedBox(height: 14),

        // حساب المشتريات
        DropdownButtonFormField<int>(
          value: _selectedPurchaseAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المشتريات',
            prefixIcon: Icon(Icons.trending_down),
          ),
          items: _expenseAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => setState(() => _selectedPurchaseAccountId = v),
        ),
        const SizedBox(height: 14),

        // حساب المخزون
        DropdownButtonFormField<int>(
          value: _selectedInventoryAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المخزون',
            prefixIcon: Icon(Icons.warehouse),
          ),
          items: _assetAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => setState(() => _selectedInventoryAccountId = v),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Shared widgets
  // ═══════════════════════════════════════════════════════════════

  Widget _stepTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
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
        isDense: true,
        labelText: label,
        suffixText: AppConstants.currency,
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Barcode entry helper for step 6
// ═══════════════════════════════════════════════════════════════════

class _BarcodeEntry {
  final String unitName;
  String barcode;
  final _UnitConversionRow? conversionRow;

  _BarcodeEntry({
    required this.unitName,
    required this.barcode,
    this.conversionRow,
  });
}
