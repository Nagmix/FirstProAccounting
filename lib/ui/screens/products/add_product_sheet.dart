import 'dart:io';
import '../../../core/utils/money_helper.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/inventory_cost_layer_model.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/license/license_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/repositories/account_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/supplier_repository.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/unit_model.dart';
import '../../widgets/barcode_scanner_screen.dart';
import 'product_models.dart';
import 'widgets/product_basic_data_step.dart';
import 'widgets/product_units_step.dart';
import 'widgets/product_pricing_step.dart';
import 'widgets/product_inventory_step.dart';
import 'widgets/product_suppliers_step.dart';
import 'widgets/product_barcodes_step.dart';
import 'widgets/product_sales_settings_step.dart';
import 'widgets/product_accounting_step.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step definitions (uses StepDef from product_models.dart)
// ═══════════════════════════════════════════════════════════════════

const _steps = [
  StepDef('البيانات الأساسية', Icons.article),
  StepDef('الوحدات', Icons.straighten),
  StepDef('الأسعار', Icons.label),
  StepDef('المخزون', Icons.inventory),
  StepDef('الموردين', Icons.local_shipping),
  StepDef('الباركود', Icons.qr_code),
  StepDef('إعدادات البيع', Icons.storefront),
  StepDef('المحاسبة', Icons.account_balance),
];

// ═══════════════════════════════════════════════════════════════════
//  AddProductSheet – multi-step wizard
//  (UnitConversionRow is in product_models.dart)
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
  final ScrollController _stepScrollController = ScrollController();

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
  final _specialWholesalePriceController = TextEditingController();
  final _minimumSalePriceController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _openingStockController = TextEditingController();
  final _purchaseUnitQtyController = TextEditingController();
  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();
  final _supplierCodeController = TextEditingController();

  // ── Dropdown / switch state ───────────────────────────────────
  int? _selectedCategoryId;
  int? _selectedBaseUnitId;
  int? _selectedPurchaseUnitId;
  int? _selectedWarehouseId;
  int? _selectedSupplierId;
  int? _selectedSalesAccountId;
  int? _selectedPurchaseAccountId;
  int? _selectedInventoryAccountId;
  int? _selectedCogsAccountId;
  int? _selectedVatAccountId;

  bool _isActive = true;
  bool _trackStock = true;
  bool _expiryTracking = false;
  bool _taxInclusive = false;
  bool _isSellable = true;
  bool _isPurchasable = true;
  bool _allowNegative = false;
  bool _sellRetail = true;
  bool _showInPos = true;
  CostingMethod _costingMethod = CostingMethod.weightedAverage;

  // Sale unit checkbox: 0 = base unit, 1 = purchase unit
  int _saleUnitSource = 0;

  DateTime? _expiryDate;
  String? _imagePath;
  bool _isSaving = false;

  bool get _isEditMode => widget.existing != null;

  // ── Unit conversions ──────────────────────────────────────────
  List<UnitConversionRow> _unitConversions = [];

  // ── Dropdown data from DB ─────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _revenueAccounts = [];
  List<Map<String, dynamic>> _costAccounts = [];
  List<Map<String, dynamic>> _assetAccounts = [];
  List<Map<String, dynamic>> _liabilityAccounts = [];

  // ── Default currency for account auto-selection ────────────────
  String? _defaultCurrencyCode;

  // ── Helper: get unit name by id ───────────────────────────────
  String _unitNameById(int? id) {
    if (id == null) return '';
    final match = _units.where((u) => u['id'] == id);
    if (match.isNotEmpty) return match.first['name_ar'] as String? ?? '';
    return '';
  }

  /// Effective sale unit based on checkbox selection
  int? get _effectiveSaleUnitId {
    if (_saleUnitSource == 1 && _selectedPurchaseUnitId != null) {
      return _selectedPurchaseUnitId;
    }
    return _selectedBaseUnitId;
  }

  /// Whether the current setup has multi-unit (base ≠ purchase)
  bool get _hasMultiUnits =>
      _selectedBaseUnitId != null &&
      _selectedPurchaseUnitId != null &&
      _selectedPurchaseUnitId != _selectedBaseUnitId;

  /// Get the conversion factor for the purchase unit
  double get _purchaseUnitFactor {
    if (!_hasMultiUnits) return 1.0;
    final conv =
        _unitConversions.where((uc) => uc.unitId == _selectedPurchaseUnitId);
    if (conv.isNotEmpty) return conv.first.factor;
    return 1.0;
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
    _specialWholesalePriceController.dispose();
    _minimumSalePriceController.dispose();
    _taxRateController.dispose();
    _openingStockController.dispose();
    _purchaseUnitQtyController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _supplierCodeController.dispose();
    _pageController.dispose();
    _stepScrollController.dispose();
    super.dispose();
  }

  // ── Load reference data ───────────────────────────────────────

  Future<void> _loadDropdownData() async {
    final results = await Future.wait([
      locator<ReferenceDataRepository>().getAllCategories(),
      locator<ReferenceDataRepository>().getAllUnits(),
      locator<SupplierRepository>().getAllSuppliers(),
      locator<ReferenceDataRepository>().getAllWarehouses(),
      locator<AccountRepository>().getAccountsByType('REVENUE'),
      locator<AccountRepository>().getAccountsByType('COST'),
      locator<AccountRepository>().getAccountsByType('ASSET'),
      locator<AccountRepository>().getAccountsByType('LIABILITY'),
    ]);

    if (!mounted) return;
    setState(() {
      _categories = results[0];
      _units = results[1];
      _suppliers = results[2];
      _warehouses = results[3];
      _revenueAccounts = results[4];
      _costAccounts = results[5];
      _assetAccounts = results[6];
      _liabilityAccounts = results[7];
    });

    // Auto-select default accounts based on default currency
    final defaultCurrency =
        await locator<ReferenceDataRepository>().getDefaultCurrency();
    if (defaultCurrency != null && !_isEditMode) {
      final currencyCode = defaultCurrency['code'] as String? ?? 'YER';
      _defaultCurrencyCode = currencyCode;
      final codeOffset = {'YER': 0, 'SAR': 1, 'USD': 2}[currencyCode] ?? 0;

      if (mounted) {
        setState(() {
          // Sales account (4100 + offset)
          _autoSelectAccount(_revenueAccounts, 4100 + codeOffset,
              (id) => _selectedSalesAccountId = id);
          // Purchases account (3100 + offset)
          _autoSelectAccount(_costAccounts, 3100 + codeOffset,
              (id) => _selectedPurchaseAccountId = id);
          // Inventory account (1300 + offset)
          _autoSelectAccount(_assetAccounts, 1300 + codeOffset,
              (id) => _selectedInventoryAccountId = id);
          // COGS account (3200 + offset)
          _autoSelectAccount(_costAccounts, 3200 + codeOffset,
              (id) => _selectedCogsAccountId = id);
          // VAT account (2300 + offset)
          _autoSelectAccount(_liabilityAccounts, 2300 + codeOffset,
              (id) => _selectedVatAccountId = id);
        });
      }
    }
  }

  /// Helper to auto-select an account by its code
  void _autoSelectAccount(List<Map<String, dynamic>> accounts, int targetCode,
      void Function(int) setter) {
    for (final a in accounts) {
      final code = a['account_code'] as String? ?? '';
      if (code == targetCode.toString()) {
        setter(a['id'] as int);
        break;
      }
    }
  }

  Future<void> _generateItemCode() async {
    final code = await locator<ProductRepository>().getNextItemCode();
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
    _taxRateController.text = p.taxRate.toStringAsFixed(2);
    _minStockController.text = p.minStock.toStringAsFixed(0);
    _supplierCodeController.text = p.supplierCode ?? '';
    _notesController.text = p.notes ?? '';

    // Set unit IDs FIRST (needed for _hasMultiUnits, _purchaseUnitFactor, _saleUnitSource)
    _selectedCategoryId = p.categoryId;
    _selectedBaseUnitId = p.effectiveBaseUnitId;
    _selectedPurchaseUnitId = p.purchaseUnitId;
    _selectedWarehouseId = p.warehouseId;
    _selectedSupplierId = p.supplierId;
    _selectedSalesAccountId = p.salesAccountId;
    _selectedPurchaseAccountId = p.purchaseAccountId;
    _selectedInventoryAccountId = p.inventoryAccountId;
    _selectedCogsAccountId = p.cogsAccountId;
    _selectedVatAccountId = p.vatAccountId;

    // Determine sale unit source (before price fields that depend on it)
    if (p.saleUnitId != null &&
        p.saleUnitId == p.purchaseUnitId &&
        p.purchaseUnitId != p.effectiveBaseUnitId) {
      _saleUnitSource = 1;
    } else {
      _saleUnitSource = 0;
    }

    // Now set price fields (they depend on _hasMultiUnits, _purchaseUnitFactor, _saleUnitSource)
    _costPriceController.text = (_hasMultiUnits && p.wholesalePrice > 0)
        ? p.wholesalePrice.toStringAsFixed(2)
        : p.costPrice.toStringAsFixed(2);
    _sellPriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
        ? (p.sellPrice * _purchaseUnitFactor).toStringAsFixed(2)
        : p.sellPrice.toStringAsFixed(2);
    _specialWholesalePriceController.text =
        (_hasMultiUnits && _saleUnitSource == 1)
            ? (p.specialWholesalePrice * _purchaseUnitFactor).toStringAsFixed(2)
            : p.specialWholesalePrice.toStringAsFixed(2);
    _minimumSalePriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
        ? (p.minimumSalePrice * _purchaseUnitFactor).toStringAsFixed(2)
        : p.minimumSalePrice.toStringAsFixed(2);

    _isActive = p.isActive;
    _trackStock = p.trackStock;
    _expiryTracking = p.expiryTracking;
    _taxInclusive = p.taxInclusive;
    _isSellable = p.isSellable;
    _isPurchasable = p.isPurchasable;
    _allowNegative = p.allowNegative;
    _sellRetail = p.sellRetail;
    _showInPos = p.showInPos;
    _costingMethod = p.costingMethod;

    _expiryDate = p.expiryDate;
    _imagePath = p.imagePath;
  }

  Future<void> _loadUnitConversions() async {
    if (widget.existing?.id == null) return;
    final conversions = await locator<ReferenceDataRepository>()
        .getUnitConversions(widget.existing!.id!);
    if (!mounted) return;
    setState(() {
      _unitConversions = conversions.map((c) {
        final fromUnitId = c['from_unit_id'] as int?;
        return UnitConversionRow(
          unitId: fromUnitId,
          factor: (c['conversion_factor'] as num?)?.toDouble() ?? 1.0,
          barcode: (c['barcode'] as String?) ?? '',
          sellPrice: MoneyHelper.readMoney(c['sell_price']),
          costPrice: MoneyHelper.readMoney(c['cost_price']),
        );
      }).toList();

      // Update price fields now that unit conversions are loaded (factor is available)
      if (_isEditMode) {
        final p = widget.existing!;
        _costPriceController.text = (_hasMultiUnits && p.wholesalePrice > 0)
            ? p.wholesalePrice.toStringAsFixed(2)
            : p.costPrice.toStringAsFixed(2);
        _sellPriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
            ? (p.sellPrice * _purchaseUnitFactor).toStringAsFixed(2)
            : p.sellPrice.toStringAsFixed(2);
        _specialWholesalePriceController.text = (_hasMultiUnits &&
                _saleUnitSource == 1)
            ? (p.specialWholesalePrice * _purchaseUnitFactor).toStringAsFixed(2)
            : p.specialWholesalePrice.toStringAsFixed(2);
        _minimumSalePriceController.text =
            (_hasMultiUnits && _saleUnitSource == 1)
                ? (p.minimumSalePrice * _purchaseUnitFactor).toStringAsFixed(2)
                : p.minimumSalePrice.toStringAsFixed(2);
      }
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
      final fileName =
          'product_${DateTime.now().millisecondsSinceEpoch}.${picked.name.split('.').last}';
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
    if (!mounted) return;
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
    // Scroll step indicator to show current step
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_stepScrollController.hasClients) {
        final maxScroll = _stepScrollController.position.maxScrollExtent;
        final targetOffset = (step * 100.0).clamp(0.0, maxScroll);
        _stepScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
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

  // ── Unit helpers ──────────────────────────────────────────────

  void _autoPopulateConversions() {
    if (_selectedPurchaseUnitId != null &&
        _selectedPurchaseUnitId != _selectedBaseUnitId) {
      // Check if purchase unit already in conversions
      final existingIdx = _unitConversions.indexWhere(
        (uc) => uc.unitId == _selectedPurchaseUnitId,
      );
      if (existingIdx == -1) {
        // Add purchase unit as first conversion row
        _unitConversions.insert(
          0,
          UnitConversionRow(
            unitId: _selectedPurchaseUnitId,
            factor: 1.0, // User must fill
          ),
        );
      } else if (existingIdx > 0) {
        // Move to first position
        final row = _unitConversions.removeAt(existingIdx);
        _unitConversions.insert(0, row);
      }
    }
  }

  void _addConversionRow() {
    setState(() {
      _unitConversions.add(UnitConversionRow());
    });
  }

  /// Auto-calculate opening stock from purchase unit quantity
  void _autoCalculateOpeningStock() {
    if (!_hasMultiUnits) return;
    final purchaseQty = double.tryParse(_purchaseUnitQtyController.text);
    if (purchaseQty == null || purchaseQty <= 0) return;
    final factor = _purchaseUnitFactor;
    if (factor <= 0) return;
    final totalBaseQty = purchaseQty * factor;
    _openingStockController.text = totalBaseQty.toStringAsFixed(0);
  }

  // ── Record limit check ──────────────────────────────────────────

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

  // ── Save ─────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_validateCurrentStep()) return;

    // Check record limit for new products
    if (!_isEditMode) {
      final canAdd = await _checkRecordLimit();
      if (!canAdd) return;
    }

    // Check for duplicate item code
    final itemCode = _itemCodeController.text.trim();
    if (itemCode.isNotEmpty) {
      try {
        final exists = await locator<ProductRepository>().checkItemCodeExists(
          itemCode,
          excludeId: _isEditMode ? widget.existing!.id : null,
        );
        if (exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('رمز الصنف موجود مسبقاً، يرجى استخدام رمز مختلف'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('Duplicate check error (non-critical): $e');
        // Continue - duplicate check is not critical
      }
    }

    // P-07: Check for duplicate barcode
    final barcode = _barcodeController.text.trim();
    if (barcode.isNotEmpty) {
      try {
        final exists = await locator<ProductRepository>().checkBarcodeExists(
          barcode,
          excludeId: _isEditMode ? widget.existing!.id : null,
        );
        if (exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'الباركود موجود مسبقاً على صنف آخر، يرجى استخدام باركود مختلف'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('Barcode duplicate check error (non-critical): $e');
      }
    }

    setState(() => _isSaving = true);

    final now = DateTime.now();
    // When multi-unit: costPrice field contains the purchase unit cost,
    // we need to calculate the base unit cost for storage.
    final enteredCostPrice = double.tryParse(_costPriceController.text) ?? 0.0;
    final enteredSellPrice = double.tryParse(_sellPriceController.text) ?? 0.0;
    final double baseCostPrice;
    final double purchaseUnitCostPrice;
    final double baseSellPrice;
    if (_hasMultiUnits) {
      final factor = _purchaseUnitFactor;
      purchaseUnitCostPrice = enteredCostPrice;
      baseCostPrice = factor > 0 ? enteredCostPrice / factor : enteredCostPrice;
      // Convert sell price to base unit if sale unit is the purchase unit
      if (_saleUnitSource == 1 && factor > 0) {
        baseSellPrice = enteredSellPrice / factor;
      } else {
        baseSellPrice = enteredSellPrice; // Already in base unit
      }
    } else {
      baseCostPrice = enteredCostPrice;
      purchaseUnitCostPrice = enteredCostPrice;
      baseSellPrice = enteredSellPrice;
    }
    final product = Product(
      itemCode: itemCode.isNotEmpty ? itemCode : null,
      nameAr: _nameArController.text.trim(),
      nameEn: _nameEnController.text.trim(),
      barcode: _barcodeController.text.trim().isNotEmpty
          ? _barcodeController.text.trim()
          : null,
      categoryId: _selectedCategoryId,
      unitId: _selectedBaseUnitId,
      baseUnitId: _selectedBaseUnitId,
      purchaseUnitId: _selectedPurchaseUnitId,
      saleUnitId: _effectiveSaleUnitId,
      supplierId: _selectedSupplierId,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      costPrice: baseCostPrice,
      averageCost: _isEditMode ? widget.existing!.averageCost : baseCostPrice,
      sellPrice: baseSellPrice,
      wholesalePrice: purchaseUnitCostPrice,
      specialWholesalePrice: _hasMultiUnits && _saleUnitSource == 1
          ? (double.tryParse(_specialWholesalePriceController.text) ?? 0.0) /
              (_purchaseUnitFactor > 0 ? _purchaseUnitFactor : 1.0)
          : (double.tryParse(_specialWholesalePriceController.text) ?? 0.0),
      minimumSalePrice: _hasMultiUnits && _saleUnitSource == 1
          ? (double.tryParse(_minimumSalePriceController.text) ?? 0.0) /
              (_purchaseUnitFactor > 0 ? _purchaseUnitFactor : 1.0)
          : (double.tryParse(_minimumSalePriceController.text) ?? 0.0),
      taxRate: double.tryParse(_taxRateController.text) ?? 0.0,
      taxInclusive: _taxInclusive,
      salesAccountId: _selectedSalesAccountId,
      purchaseAccountId: _selectedPurchaseAccountId,
      inventoryAccountId: _selectedInventoryAccountId,
      cogsAccountId: _selectedCogsAccountId,
      vatAccountId: _selectedVatAccountId,
      currentStock: _isEditMode
          ? widget.existing!.currentStock
          : (double.tryParse(_openingStockController.text) ?? 0.0),
      minStock: double.tryParse(_minStockController.text) ?? 0.0,
      warehouseId:
          _isEditMode ? widget.existing!.warehouseId : _selectedWarehouseId,
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
      costingMethod: _costingMethod,
      imagePath: _imagePath,
      supplierCode: _supplierCodeController.text.trim().isNotEmpty
          ? _supplierCodeController.text.trim()
          : null,
      createdAt: now,
      updatedAt: now,
    );

    try {
      // Build unit conversions list for repository
      final unitConversionMaps =
          _unitConversions.where((uc) => uc.unitId != null).map((uc) {
        final unitName = _unitNameById(uc.unitId);
        final baseUnitName = _unitNameById(_selectedBaseUnitId);
        return {
          'from_unit': unitName.isNotEmpty ? unitName : 'unknown',
          'to_unit': baseUnitName.isNotEmpty ? baseUnitName : 'unknown',
          'from_unit_id': uc.unitId,
          'to_unit_id': _selectedBaseUnitId,
          'conversion_factor': uc.factor,
          'barcode': uc.barcode,
          'sell_price': uc.sellPrice,
          'cost_price': uc.costPrice,
        };
      }).toList();

      if (_isEditMode) {
        final updateMap = product.toMap();
        // Lock system-managed fields (stock and warehouse), but allow account changes
        updateMap['current_stock'] = widget.existing!.currentStock;
        updateMap['warehouse_id'] = widget.existing!.warehouseId;
        updateMap['image_path'] = _imagePath;
        await locator<ProductRepository>().updateProductWithConversions(
          productId: widget.existing!.id!,
          updateMap: updateMap,
          unitConversions: unitConversionMaps,
        );
      } else {
        final map = product.toMap();
        map['image_path'] = _imagePath;
        final openingQty = double.tryParse(_openingStockController.text) ?? 0.0;
        await locator<ProductRepository>().saveProductWithConversions(
          productMap: map,
          unitConversions: unitConversionMaps,
          openingStock: openingQty > 0 && _trackStock ? openingQty : null,
          warehouseId: _selectedWarehouseId,
          baseCostPrice: baseCostPrice,
          currency: _defaultCurrencyCode ?? 'YER',
          productName: _nameArController.text.trim(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      debugPrint('Save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الحفظ: $e'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
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
            onPressed:
                _isSaving ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Step indicator ──────────────────────────────────
              _buildArrowStepIndicator(),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: _nextStep,
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('التالي'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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

  // ── Modern arrow-based step indicator ─────────────────────────

  Widget _buildArrowStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: SingleChildScrollView(
        controller: _stepScrollController,
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: List.generate(_steps.length * 2 - 1, (index) {
            if (index.isOdd) {
              // Arrow separator
              final stepIdx = index ~/ 2;
              final isCompleted = stepIdx < _currentStep;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.arrow_back_ios,
                  size: 14,
                  color: isCompleted
                      ? AppColors.success
                      : AppColors.textTertiary.withValues(alpha: 0.4),
                ),
              );
            }
            final i = index ~/ 2;
            final isActive = i == _currentStep;
            final isCompleted = i < _currentStep;
            final isFuture = i > _currentStep;

            return GestureDetector(
              onTap: () {
                if (i <= _currentStep || isCompleted) {
                  _goToStep(i);
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : isCompleted
                          ? AppColors.success.withValues(alpha: 0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary
                        : isCompleted
                            ? AppColors.success
                            : AppColors.border,
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCompleted)
                      const Icon(Icons.check_circle,
                          size: 16, color: AppColors.success)
                    else if (isActive)
                      Icon(_steps[i].icon, size: 14, color: Colors.white)
                    else
                      Icon(_steps[i].icon,
                          size: 14,
                          color: AppColors.textTertiary.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      _steps[i].title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : isCompleted
                                ? AppColors.success
                                : isFuture
                                    ? AppColors.textTertiary
                                        .withValues(alpha: 0.5)
                                    : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
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
  //  Step builders — delegate to extracted widgets
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBasicDataStep() {
    return ProductBasicDataStep(
      nameArController: _nameArController,
      nameEnController: _nameEnController,
      itemCodeController: _itemCodeController,
      barcodeController: _barcodeController,
      descriptionController: _descriptionController,
      notesController: _notesController,
      selectedCategoryId: _selectedCategoryId,
      imagePath: _imagePath,
      isActive: _isActive,
      categories: _categories,
      onPickImage: _pickImage,
      onImageRemoved: () => setState(() => _imagePath = null),
      onGenerateItemCode: _generateItemCode,
      onScanBarcode: _scanBarcode,
      onBarcodeCleared: () {
        _barcodeController.clear();
        setState(() {});
      },
      onCategoryChanged: (v) => setState(() => _selectedCategoryId = v),
      onShowAddCategoryDialog: _showAddCategoryDialog,
      onActiveChanged: (v) => setState(() => _isActive = v),
      onBarcodeChanged: () => setState(() {}),
    );
  }

  Widget _buildUnitsStep() {
    return ProductUnitsStep(
      costPriceController: _costPriceController,
      selectedBaseUnitId: _selectedBaseUnitId,
      selectedPurchaseUnitId: _selectedPurchaseUnitId,
      saleUnitSource: _saleUnitSource,
      hasMultiUnits: _hasMultiUnits,
      purchaseUnitFactor: _purchaseUnitFactor,
      unitConversions: _unitConversions,
      units: _units,
      unitNameById: _unitNameById,
      onBaseUnitChanged: (v) {
        setState(() {
          _selectedBaseUnitId = v;
          if (_selectedBaseUnitId == _selectedPurchaseUnitId) {
            _unitConversions.clear();
          }
        });
      },
      onPurchaseUnitChanged: (v) {
        setState(() {
          _selectedPurchaseUnitId = v;
          if (_selectedPurchaseUnitId == _selectedBaseUnitId) {
            _unitConversions.clear();
          } else {
            _autoPopulateConversions();
          }
        });
      },
      onShowAddUnitDialog: _showAddUnitDialog,
      onSaleUnitSourceChanged: (v) => setState(() => _saleUnitSource = v),
      onAddConversionRow: _addConversionRow,
      onRemoveConversionRow: (index) =>
          setState(() => _unitConversions.removeAt(index)),
      onConversionChanged: (row, index) {
        // Recalculate inventory if this is the purchase unit
        if (row.unitId == _selectedPurchaseUnitId) {
          _autoCalculateOpeningStock();
        }
      },
      onStateChanged: () => setState(() {}),
    );
  }

  Widget _buildPricesStep() {
    return ProductPricingStep(
      costPriceController: _costPriceController,
      sellPriceController: _sellPriceController,
      specialWholesalePriceController: _specialWholesalePriceController,
      minimumSalePriceController: _minimumSalePriceController,
      taxRateController: _taxRateController,
      hasMultiUnits: _hasMultiUnits,
      saleUnitSource: _saleUnitSource,
      purchaseUnitFactor: _purchaseUnitFactor,
      selectedPurchaseUnitId: _selectedPurchaseUnitId,
      selectedBaseUnitId: _selectedBaseUnitId,
      effectiveSaleUnitId: _effectiveSaleUnitId,
      taxInclusive: _taxInclusive,
      unitNameById: _unitNameById,
      onStateChanged: () => setState(() {}),
      onTaxInclusiveChanged: (v) => setState(() => _taxInclusive = v),
    );
  }

  Widget _buildInventoryStep() {
    return ProductInventoryStep(
      openingStockController: _openingStockController,
      purchaseUnitQtyController: _purchaseUnitQtyController,
      minStockController: _minStockController,
      maxStockController: _maxStockController,
      hasMultiUnits: _hasMultiUnits,
      purchaseUnitFactor: _purchaseUnitFactor,
      trackStock: _trackStock,
      expiryTracking: _expiryTracking,
      expiryDate: _expiryDate,
      selectedWarehouseId: _selectedWarehouseId,
      selectedBaseUnitId: _selectedBaseUnitId,
      selectedPurchaseUnitId: _selectedPurchaseUnitId,
      isEditMode: _isEditMode,
      existingProduct: widget.existing,
      warehouses: _warehouses,
      unitNameById: _unitNameById,
      onTrackStockChanged: (v) => setState(() => _trackStock = v),
      onExpiryTrackingChanged: (v) => setState(() => _expiryTracking = v),
      onPickExpiryDate: _pickExpiryDate,
      onWarehouseChanged: (v) => setState(() => _selectedWarehouseId = v),
      onShowAddWarehouseDialog: _showAddWarehouseDialog,
      onAutoCalculateOpeningStock: _autoCalculateOpeningStock,
      onStateChanged: () => setState(() {}),
    );
  }

  Widget _buildSuppliersStep() {
    return ProductSuppliersStep(
      supplierCodeController: _supplierCodeController,
      selectedSupplierId: _selectedSupplierId,
      suppliers: _suppliers,
      onSupplierChanged: (v) => setState(() => _selectedSupplierId = v),
      onShowAddSupplierDialog: _showAddSupplierDialog,
    );
  }

  Widget _buildBarcodesStep() {
    return ProductBarcodesStep(
      selectedBaseUnitId: _selectedBaseUnitId,
      selectedPurchaseUnitId: _selectedPurchaseUnitId,
      unitConversions: _unitConversions,
      unitNameById: _unitNameById,
      onStateChanged: () => setState(() {}),
    );
  }

  Widget _buildSalesSettingsStep() {
    return ProductSalesSettingsStep(
      isSellable: _isSellable,
      isPurchasable: _isPurchasable,
      allowNegative: _allowNegative,
      sellRetail: _sellRetail,
      showInPos: _showInPos,
      onSellableChanged: (v) => setState(() => _isSellable = v),
      onPurchasableChanged: (v) => setState(() => _isPurchasable = v),
      onAllowNegativeChanged: (v) => setState(() => _allowNegative = v),
      onSellRetailChanged: (v) => setState(() => _sellRetail = v),
      onShowInPosChanged: (v) => setState(() => _showInPos = v),
    );
  }

  Widget _buildAccountingStep() {
    return ProductAccountingStep(
      taxRateController: _taxRateController,
      selectedSalesAccountId: _selectedSalesAccountId,
      selectedPurchaseAccountId: _selectedPurchaseAccountId,
      selectedInventoryAccountId: _selectedInventoryAccountId,
      selectedCogsAccountId: _selectedCogsAccountId,
      selectedVatAccountId: _selectedVatAccountId,
      costingMethod: _costingMethod,
      isEditMode: _isEditMode,
      revenueAccounts: _revenueAccounts,
      costAccounts: _costAccounts,
      assetAccounts: _assetAccounts,
      liabilityAccounts: _liabilityAccounts,
      onSalesAccountChanged: (v) => setState(() => _selectedSalesAccountId = v),
      onPurchaseAccountChanged: (v) =>
          setState(() => _selectedPurchaseAccountId = v),
      onInventoryAccountChanged: (v) =>
          setState(() => _selectedInventoryAccountId = v),
      onCogsAccountChanged: (v) => setState(() => _selectedCogsAccountId = v),
      onVatAccountChanged: (v) => setState(() => _selectedVatAccountId = v),
      onCostingMethodChanged: (v) => setState(() => _costingMethod = v),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Inline Add dialogs
  // ═══════════════════════════════════════════════════════════════

  Future<void> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة تصنيف جديد'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'اسم التصنيف',
              prefixIcon: Icon(Icons.folder),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();

    if (result == true) {
      final name = nameController.text.trim();
      if (name.isNotEmpty) {
        final now = DateTime.now().toIso8601String();
        final id = await locator<ReferenceDataRepository>().insertCategory({
          'name': name,
          'is_active': 1,
          'created_at': now,
        });
        await _loadDropdownData();
        if (mounted) {
          setState(() => _selectedCategoryId = id);
        }
      }
    }
  }

  Future<void> _showAddUnitDialog() async {
    final nameArController = TextEditingController();
    final nameEnController = TextEditingController();
    final abbrController = TextEditingController();
    final descController = TextEditingController();
    final orderController = TextEditingController(text: '0');

    String selectedType = 'count';
    bool isActive = true;
    bool isSellable = true;
    bool isPurchasable = true;
    bool isPackaging = false;
    bool isBaseUnit = false;

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.straighten, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    const Text('إضافة وحدة جديدة',
                        style: TextStyle(fontSize: 18)),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name Arabic
                        TextFormField(
                          controller: nameArController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'اسم الوحدة بالعربي *',
                            prefixIcon: Icon(Icons.text_fields),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'اسم الوحدة مطلوب'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Name English
                        TextFormField(
                          controller: nameEnController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'اسم الوحدة بالإنجليزي',
                            prefixIcon: Icon(Icons.text_fields),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Abbreviation
                        TextFormField(
                          controller: abbrController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'الاختصار',
                            hintText: 'مثال: كجم، حبة، ل',
                            prefixIcon: Icon(Icons.short_text),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Unit Type
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'نوع الوحدة *',
                            prefixIcon: Icon(Icons.category),
                          ),
                          items: Unit.unitTypeLabels.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedType = v ?? 'count'),
                        ),
                        const SizedBox(height: 12),

                        // Description
                        TextFormField(
                          controller: descController,
                          textInputAction: TextInputAction.next,
                          maxLines: 2,
                          minLines: 1,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'وصف (اختياري)',
                            prefixIcon: Icon(Icons.edit_note),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Display Order
                        TextFormField(
                          controller: orderController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'ترتيب العرض',
                            prefixIcon: Icon(Icons.sort),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Flags
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilterChip(
                              label: const Text('مفعلة'),
                              selected: isActive,
                              onSelected: (v) =>
                                  setDialogState(() => isActive = v),
                              selectedColor: AppColors.successLight,
                            ),
                            FilterChip(
                              label: const Text('قابلة للبيع'),
                              selected: isSellable,
                              onSelected: (v) =>
                                  setDialogState(() => isSellable = v),
                              selectedColor: AppColors.infoLight,
                            ),
                            FilterChip(
                              label: const Text('قابلة للشراء'),
                              selected: isPurchasable,
                              onSelected: (v) =>
                                  setDialogState(() => isPurchasable = v),
                              selectedColor: AppColors.infoLight,
                            ),
                            FilterChip(
                              label: const Text('وحدة تغليف'),
                              selected: isPackaging,
                              onSelected: (v) =>
                                  setDialogState(() => isPackaging = v),
                              selectedColor: AppColors.warningLight,
                            ),
                            FilterChip(
                              label: const Text('وحدة أساسية'),
                              selected: isBaseUnit,
                              onSelected: (v) =>
                                  setDialogState(() => isBaseUnit = v),
                              selectedColor:
                                  AppColors.primaryLight.withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.of(context).pop(true);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('إضافة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      final now = DateTime.now().toIso8601String();
      final _ = await locator<ReferenceDataRepository>().insertUnit({
        'name_ar': nameArController.text.trim(),
        'name_en': nameEnController.text.trim(),
        'abbreviation': abbrController.text.trim(),
        'unit_type': selectedType,
        'description': descController.text.trim().isNotEmpty
            ? descController.text.trim()
            : null,
        'is_active': isActive ? 1 : 0,
        'is_sellable': isSellable ? 1 : 0,
        'is_purchasable': isPurchasable ? 1 : 0,
        'is_packaging': isPackaging ? 1 : 0,
        'is_base_unit': isBaseUnit ? 1 : 0,
        'display_order': int.tryParse(orderController.text) ?? 0,
        'created_at': now,
        'updated_at': now,
      });
      await _loadDropdownData();
      if (mounted) {
        setState(() {});
      }
    }
    nameArController.dispose();
    nameEnController.dispose();
    abbrController.dispose();
    descController.dispose();
    orderController.dispose();
  }

  Future<void> _showAddWarehouseDialog() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة مستودع جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'اسم المستودع',
                  prefixIcon: Icon(Icons.warehouse),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'الموقع',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      if (name.isNotEmpty) {
        final now = DateTime.now().toIso8601String();
        final id = await locator<ReferenceDataRepository>().insertWarehouse({
          'name': name,
          'location': locationController.text.trim().isNotEmpty
              ? locationController.text.trim()
              : null,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        await _loadDropdownData();
        if (mounted) {
          setState(() => _selectedWarehouseId = id);
        }
      }
    }
    nameController.dispose();
    locationController.dispose();
  }

  Future<void> _showAddSupplierDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final balanceController = TextEditingController();
    final debtCeilingController = TextEditingController();
    final notesController = TextEditingController();

    String balanceType = 'credit'; // 'credit' (له) or 'debit' (عليه)
    String contactMethod = 'whatsapp'; // 'whatsapp' or 'phone'

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.local_shipping,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    const Text('إضافة مورد جديد',
                        style: TextStyle(fontSize: 18)),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name
                        TextFormField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'الاسم *',
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'الاسم مطلوب'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Phone
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'رقم الهاتف',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Email
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'البريد الإلكتروني',
                            prefixIcon: Icon(Icons.email),
                          ),
                          validator: (v) {
                            if (v != null && v.trim().isNotEmpty) {
                              final regex =
                                  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                              if (!regex.hasMatch(v.trim())) {
                                return 'البريد الإلكتروني غير صالح';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Address
                        TextFormField(
                          controller: addressController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'العنوان',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Opening balance + له/عليه toggle
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: balanceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}'))
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'الرصيد الافتتاحي',
                                  prefixIcon: const Icon(Icons.calculate),
                                  suffixText: AppConstants.currency,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'اتجاه الرصيد',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: balanceType == 'credit'
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setDialogState(
                                                () => balanceType = 'credit'),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: balanceType == 'credit'
                                                    ? AppColors.success
                                                        .withValues(alpha: 0.1)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    const BorderRadius.only(
                                                  topRight: Radius.circular(9),
                                                  bottomRight:
                                                      Radius.circular(9),
                                                ),
                                              ),
                                              child: Text(
                                                'له',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: balanceType == 'credit'
                                                      ? AppColors.success
                                                      : AppColors.textHint,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setDialogState(
                                                () => balanceType = 'debit'),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: balanceType == 'debit'
                                                    ? AppColors.error
                                                        .withValues(alpha: 0.1)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    const BorderRadius.only(
                                                  topLeft: Radius.circular(9),
                                                  bottomLeft:
                                                      Radius.circular(9),
                                                ),
                                              ),
                                              child: Text(
                                                'عليه',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: balanceType == 'debit'
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
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Debt Ceiling
                        TextFormField(
                          controller: debtCeilingController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'))
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'سقف المدينية',
                            prefixIcon: const Icon(Icons.credit_card),
                            suffixText: AppConstants.currency,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Contact Method toggle
                        Text(
                          'طريقة التواصل',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: contactMethod == 'whatsapp'
                                  ? const Color(0xFF25D366)
                                  : AppColors.primary,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setDialogState(
                                      () => contactMethod = 'whatsapp'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: contactMethod == 'whatsapp'
                                          ? const Color(0xFF25D366)
                                              .withValues(alpha: 0.1)
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(9),
                                        bottomRight: Radius.circular(9),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.chat,
                                          size: 16,
                                          color: contactMethod == 'whatsapp'
                                              ? const Color(0xFF25D366)
                                              : AppColors.textHint,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'واتساب',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: contactMethod == 'whatsapp'
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
                                  onTap: () => setDialogState(
                                      () => contactMethod = 'phone'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: contactMethod == 'phone'
                                          ? AppColors.primary
                                              .withValues(alpha: 0.1)
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(9),
                                        bottomLeft: Radius.circular(9),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.phone_in_talk,
                                          size: 16,
                                          color: contactMethod == 'phone'
                                              ? AppColors.primary
                                              : AppColors.textHint,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'اتصال',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: contactMethod == 'phone'
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
                        const SizedBox(height: 12),

                        // Notes
                        TextFormField(
                          controller: notesController,
                          maxLines: 2,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'الملاحظات',
                            prefixIcon: Icon(Icons.edit_note),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.of(context).pop(true);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('إضافة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      final now = DateTime.now().toIso8601String();
      final balance = double.tryParse(balanceController.text) ?? 0.0;
      final id = await locator<SupplierRepository>().insertSupplier({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim().isEmpty
            ? null
            : phoneController.text.trim(),
        'email': emailController.text.trim().isEmpty
            ? null
            : emailController.text.trim(),
        'address': addressController.text.trim().isEmpty
            ? null
            : addressController.text.trim(),
        'balance': balance,
        'balance_type': balanceType,
        'currency': 'YER',
        'notes': notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        'debt_ceiling': double.tryParse(debtCeilingController.text) ?? 0.0,
        'contact_method': contactMethod,
        'created_at': now,
        'updated_at': now,
      });
      await _loadDropdownData();
      if (mounted) {
        setState(() => _selectedSupplierId = id);
      }
    }
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    balanceController.dispose();
    debtCeilingController.dispose();
    notesController.dispose();
  }
}
