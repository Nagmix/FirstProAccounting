import 'dart:io';
import '../../../core/utils/money_helper.dart';

import 'package:flutter/material.dart';
import '../../../data/models/inventory_cost_layer_model.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/unit_model.dart';
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
  double costPrice;

  _UnitConversionRow({
    this.unitId,
    this.factor = 1.0,
    this.barcode = '',
    this.sellPrice = 0.0,
    this.costPrice = 0.0,
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
  List<_UnitConversionRow> _unitConversions = [];

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
    final db = DatabaseHelper();
    final results = await Future.wait([
      db.getAllCategories(),
      db.getAllUnits(),
      db.getAllSuppliers(),
      db.getAllWarehouses(),
      db.getAccountsByType('REVENUE'),
      db.getAccountsByType('COST'),
      db.getAccountsByType('ASSET'),
      db.getAccountsByType('LIABILITY'),
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
    final defaultCurrency = await db.getDefaultCurrency();
    if (defaultCurrency != null && !_isEditMode) {
      final currencyCode = defaultCurrency['code'] as String? ?? 'YER';
      _defaultCurrencyCode = currencyCode;
      final codeOffset = {'YER': 0, 'SAR': 1, 'USD': 2}[currencyCode] ?? 0;

      if (mounted) {
        setState(() {
          // Sales account (4100 + offset)
          _autoSelectAccount(_revenueAccounts, 4100 + codeOffset, (id) => _selectedSalesAccountId = id);
          // Purchases account (3100 + offset)
          _autoSelectAccount(_costAccounts, 3100 + codeOffset, (id) => _selectedPurchaseAccountId = id);
          // Inventory account (1300 + offset)
          _autoSelectAccount(_assetAccounts, 1300 + codeOffset, (id) => _selectedInventoryAccountId = id);
          // COGS account (3200 + offset)
          _autoSelectAccount(_costAccounts, 3200 + codeOffset, (id) => _selectedCogsAccountId = id);
          // VAT account (2300 + offset)
          _autoSelectAccount(_liabilityAccounts, 2300 + codeOffset, (id) => _selectedVatAccountId = id);
        });
      }
    }
  }

  /// Helper to auto-select an account by its code
  void _autoSelectAccount(List<Map<String, dynamic>> accounts, int targetCode, void Function(int) setter) {
    for (final a in accounts) {
      final code = a['account_code'] as String? ?? '';
      if (code == targetCode.toString()) {
        setter(a['id'] as int);
        break;
      }
    }
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
    if (p.saleUnitId != null && p.saleUnitId == p.purchaseUnitId && p.purchaseUnitId != p.effectiveBaseUnitId) {
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
    _specialWholesalePriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
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
        _specialWholesalePriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
            ? (p.specialWholesalePrice * _purchaseUnitFactor).toStringAsFixed(2)
            : p.specialWholesalePrice.toStringAsFixed(2);
        _minimumSalePriceController.text = (_hasMultiUnits && _saleUnitSource == 1)
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
    // Scroll step indicator to show current step
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_stepScrollController.hasClients) {
        final maxScroll = _stepScrollController.position.maxScrollExtent;
        final viewportWidth = _stepScrollController.position.viewportDimension;
        // Each step chip is roughly 120px wide + 30px for arrow
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

  // ── Save ─────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_validateCurrentStep()) return;

    // Check for duplicate item code
    final itemCode = _itemCodeController.text.trim();
    if (itemCode.isNotEmpty) {
      try {
        final exists = await DatabaseHelper().checkItemCodeExists(
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
        final exists = await DatabaseHelper().checkBarcodeExists(
          barcode,
          excludeId: _isEditMode ? widget.existing!.id : null,
        );
        if (exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الباركود موجود مسبقاً على صنف آخر، يرجى استخدام باركود مختلف'),
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
      specialWholesalePrice:
          _hasMultiUnits && _saleUnitSource == 1
              ? (double.tryParse(_specialWholesalePriceController.text) ?? 0.0) / (_purchaseUnitFactor > 0 ? _purchaseUnitFactor : 1.0)
              : (double.tryParse(_specialWholesalePriceController.text) ?? 0.0),
      minimumSalePrice:
          _hasMultiUnits && _saleUnitSource == 1
              ? (double.tryParse(_minimumSalePriceController.text) ?? 0.0) / (_purchaseUnitFactor > 0 ? _purchaseUnitFactor : 1.0)
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
      costingMethod: _costingMethod,
      imagePath: _imagePath,
      supplierCode: _supplierCodeController.text.trim().isNotEmpty
          ? _supplierCodeController.text.trim()
          : null,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      int? savedProductId;

      // Use a transaction to ensure atomicity
      await db.transaction((txn) async {
        if (_isEditMode) {
          final updateMap = product.toMap();
          // Lock system-managed fields (stock and warehouse), but allow account changes
          updateMap['current_stock'] = widget.existing!.currentStock;
          updateMap['warehouse_id'] = widget.existing!.warehouseId;
          updateMap['image_path'] = _imagePath;
          await txn.update('products', MoneyHelper.toCentsMap(updateMap, MoneyHelper.productMoneyFields), where: 'id = ?', whereArgs: [widget.existing!.id!]);

          // Replace unit conversions
          final productId = widget.existing!.id!;
          await txn.delete('unit_conversions', where: 'product_id = ?', whereArgs: [productId]);
          for (final uc in _unitConversions) {
            if (uc.unitId == null) continue;
            final unitName = _unitNameById(uc.unitId);
            final baseUnitName = _unitNameById(_selectedBaseUnitId);
            try {
              await txn.insert('unit_conversions', MoneyHelper.toCentsMap({
                'product_id': productId,
                'from_unit': unitName.isNotEmpty ? unitName : 'unknown',
                'to_unit': baseUnitName.isNotEmpty ? baseUnitName : 'unknown',
                'from_unit_id': uc.unitId,
                'to_unit_id': _selectedBaseUnitId,
                'conversion_factor': uc.factor,
                'barcode': uc.barcode,
                'sell_price': uc.sellPrice,
                'cost_price': uc.costPrice,
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              }, ['sell_price', 'cost_price']));
            } catch (e) {
              debugPrint('Unit conversion insert error (edit, non-critical): $e');
              try {
                await txn.insert('unit_conversions', MoneyHelper.toCentsMap({
                  'product_id': productId,
                  'from_unit': unitName.isNotEmpty ? unitName : 'unknown',
                  'to_unit': baseUnitName.isNotEmpty ? baseUnitName : 'unknown',
                  'conversion_factor': uc.factor,
                  'barcode': uc.barcode,
                  'sell_price': uc.sellPrice,
                  'cost_price': uc.costPrice,
                  'is_active': 1,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                }, ['sell_price', 'cost_price']));
              } catch (e2) {
                debugPrint('Unit conversion insert error (edit, fallback): $e2');
              }
            }
          }
        } else {
          final map = product.toMap();
          // Remove 'id' so SQLite auto-generates it
          map.remove('id');
          map['image_path'] = _imagePath;
          savedProductId = await txn.insert('products', MoneyHelper.toCentsMap(map, MoneyHelper.productMoneyFields));

          // Save unit conversions
          if (savedProductId != null && savedProductId! > 0) {
            for (final uc in _unitConversions) {
              if (uc.unitId == null) continue;
              final unitName = _unitNameById(uc.unitId);
              final baseUnitName = _unitNameById(_selectedBaseUnitId);
              try {
                await txn.insert('unit_conversions', MoneyHelper.toCentsMap({
                  'product_id': savedProductId,
                  'from_unit': unitName.isNotEmpty ? unitName : 'unknown',
                  'to_unit': baseUnitName.isNotEmpty ? baseUnitName : 'unknown',
                  'from_unit_id': uc.unitId,
                  'to_unit_id': _selectedBaseUnitId,
                  'conversion_factor': uc.factor,
                  'barcode': uc.barcode,
                  'sell_price': uc.sellPrice,
                  'cost_price': uc.costPrice,
                  'is_active': 1,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                }, ['sell_price', 'cost_price']));
              } catch (e) {
                debugPrint('Unit conversion insert error (non-critical): $e');
                // Try without from_unit_id / to_unit_id in case DB schema is outdated
                try {
                  await txn.insert('unit_conversions', MoneyHelper.toCentsMap({
                    'product_id': savedProductId,
                    'from_unit': unitName.isNotEmpty ? unitName : 'unknown',
                    'to_unit': baseUnitName.isNotEmpty ? baseUnitName : 'unknown',
                    'conversion_factor': uc.factor,
                    'barcode': uc.barcode,
                    'sell_price': uc.sellPrice,
                    'cost_price': uc.costPrice,
                    'is_active': 1,
                    'created_at': DateTime.now().toIso8601String(),
                    'updated_at': DateTime.now().toIso8601String(),
                  }, ['sell_price', 'cost_price']));
                } catch (e2) {
                  debugPrint('Unit conversion insert error (fallback): $e2');
                }
              }
            }
          }
        }
        // ── Opening balance: stock movement + journal entries INSIDE the transaction ──
        // This ensures atomicity — if journal entry fails, the product insert is rolled back too.
        if (!_isEditMode && savedProductId != null) {
          final openingQty = double.tryParse(_openingStockController.text) ?? 0.0;
          if (openingQty > 0 && _trackStock) {
            try {
              final now = DateTime.now().toIso8601String();
              // Log stock movement directly via txn
              await txn.insert('stock_movements', {
                'product_id': savedProductId!,
                'movement_type': 'opening',
                'quantity': openingQty,
                'reference_type': null,
                'reference_id': null,
                'notes': 'رصيد افتتاحي',
                'unit_cost': MoneyHelper.toCents(baseCostPrice),
                'created_at': now,
              });

              // Create journal entries for opening balance: Debit Inventory / Credit Opening Balance
              final totalValue = openingQty * baseCostPrice;
              if (totalValue > 0) {
                final codeOffset = _defaultCurrencyCode == 'SAR' ? 1 : (_defaultCurrencyCode == 'USD' ? 2 : 0);
                final currency = _defaultCurrencyCode ?? 'YER';

                // Find inventory account (1300 + offset)
                final inventoryAccount = await txn.query(
                  'accounts',
                  where: 'account_code = ? AND currency = ?',
                  whereArgs: [(1300 + codeOffset).toString(), currency],
                  limit: 1,
                );
                // Find opening balance equity account (2901 + offset)
                final openingBalanceAccount = await txn.query(
                  'accounts',
                  where: 'account_code = ? AND currency = ?',
                  whereArgs: [(2901 + codeOffset).toString(), currency],
                  limit: 1,
                );

                if (inventoryAccount.isNotEmpty && openingBalanceAccount.isNotEmpty) {
                  final inventoryAccountId = inventoryAccount.first['id'] as int;
                  final openingBalanceAccountId = openingBalanceAccount.first['id'] as int;

                  // Journal entry: Debit Inventory / Credit Opening Balance
                  await txn.insert('transactions', {
                    'account_id': inventoryAccountId,
                    'debit': MoneyHelper.toCents(totalValue),
                    'credit': 0,
                    'description': 'رصيد افتتاحي - منتج: ${_nameArController.text.trim()}',
                    'date': now,
                    'created_at': now,
                  });
                  await txn.insert('transactions', {
                    'account_id': openingBalanceAccountId,
                    'debit': 0,
                    'credit': MoneyHelper.toCents(totalValue),
                    'description': 'رصيد افتتاحي - منتج: ${_nameArController.text.trim()}',
                    'date': now,
                    'created_at': now,
                  });

                  // P-03: Use updateAccountBalanceWithJournal for correct balance calculation
                  // instead of manual balance calculation that doesn't handle EQUITY correctly
                  final dbHelper = DatabaseHelper();
                  await dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, totalValue, 0.0, now);
                  await dbHelper.journal.updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, totalValue, now);
                }
              }
            } catch (e) {
              debugPrint('Opening balance journal entry error (non-critical): $e');
            }
          }
        }
      });
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
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
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
                      color: Colors.black.withOpacity(0.06),
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

  // ── Modern arrow-based step indicator (ISSUE 2) ──────────────

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
                  color: isCompleted ? AppColors.success : AppColors.textTertiary.withOpacity(0.4),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : isCompleted
                          ? AppColors.success.withOpacity(0.1)
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
                      const Icon(Icons.check_circle, size: 16, color: AppColors.success)
                    else if (isActive)
                      Icon(_steps[i].icon, size: 14, color: Colors.white)
                    else
                      Icon(_steps[i].icon, size: 14, color: AppColors.textTertiary.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Text(
                      _steps[i].title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : isCompleted
                                ? AppColors.success
                                : isFuture
                                    ? AppColors.textTertiary.withOpacity(0.5)
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
  //  STEP 1 – البيانات الأساسية (ISSUE 3)
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
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
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
                          color: AppColors.primary.withOpacity(0.4),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 32,
                            color: AppColors.primary.withOpacity(0.5)),
                        const SizedBox(height: 6),
                        Text('صورة الصنف',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary.withOpacity(0.7))),
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

        // ── التصنيف (Searchable + "+" button) ────────────────
        _buildSearchableDropdownWithAdd(
          label: 'التصنيف',
          icon: Icons.folder,
          items: _categories,
          idKey: 'id',
          nameKey: 'name',
          selectedId: _selectedCategoryId,
          onChanged: (v) => setState(() => _selectedCategoryId = v),
          onAdd: () => _showAddCategoryDialog(),
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
  //  STEP 2 – الوحدات (ISSUE 4)
  // ═══════════════════════════════════════════════════════════════

  /// Whether the current setup has multi-unit (base ≠ purchase)
  bool get _hasMultiUnits =>
      _selectedBaseUnitId != null &&
      _selectedPurchaseUnitId != null &&
      _selectedPurchaseUnitId != _selectedBaseUnitId;

  /// Get the conversion factor for the purchase unit
  double get _purchaseUnitFactor {
    if (!_hasMultiUnits) return 1.0;
    final conv = _unitConversions.where((uc) => uc.unitId == _selectedPurchaseUnitId);
    if (conv.isNotEmpty) return conv.first.factor;
    return 1.0;
  }

  Widget _buildUnitsStep() {
    // Show ALL units in the base unit dropdown (not just is_base_unit)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[1].title, _steps[1].icon),

        // ── الوحدة الأساسية * (Searchable + "+") ────────────
        _buildSearchableDropdownWithAdd(
          label: 'الوحدة الأساسية *',
          icon: Icons.straighten,
          items: _units,
          idKey: 'id',
          nameKey: 'name_ar',
          selectedId: _selectedBaseUnitId,
          onChanged: (v) {
            setState(() {
              _selectedBaseUnitId = v;
              // If base unit same as purchase unit, clear conversions
              if (_selectedBaseUnitId == _selectedPurchaseUnitId) {
                _unitConversions.clear();
              }
            });
          },
          onAdd: () => _showAddUnitDialog(),
        ),
        const SizedBox(height: 14),

        // ── وحدة الشراء الافتراضية (Searchable + "+") ───────
        _buildSearchableDropdownWithAdd(
          label: 'وحدة الشراء الافتراضية',
          icon: Icons.shopping_cart,
          items: _units,
          idKey: 'id',
          nameKey: 'name_ar',
          selectedId: _selectedPurchaseUnitId,
          onChanged: (v) {
            setState(() {
              _selectedPurchaseUnitId = v;
              // If purchase unit same as base unit, clear conversions
              if (_selectedPurchaseUnitId == _selectedBaseUnitId) {
                _unitConversions.clear();
              } else {
                _autoPopulateConversions();
              }
            });
          },
          onAdd: () => _showAddUnitDialog(),
        ),
        const SizedBox(height: 14),

        // ── وحدة البيع الافتراضية (Checkbox approach) ───────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('وحدة البيع الافتراضية',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 8),
              // Checkbox for base unit
              _buildSaleUnitCheckbox(
                label: _selectedBaseUnitId != null
                    ? '${_unitNameById(_selectedBaseUnitId)} (الوحدة الأساسية)'
                    : 'الوحدة الأساسية',
                value: _saleUnitSource == 0,
                onChanged: (v) {
                  if (v == true) {
                    setState(() => _saleUnitSource = 0);
                  }
                },
              ),
              // Checkbox for purchase unit
              _buildSaleUnitCheckbox(
                label: _selectedPurchaseUnitId != null
                    ? '${_unitNameById(_selectedPurchaseUnitId)} (وحدة الشراء)'
                    : 'وحدة الشراء الافتراضية',
                value: _saleUnitSource == 1,
                onChanged: (v) {
                  if (v == true && _selectedPurchaseUnitId != null) {
                    setState(() => _saleUnitSource = 1);
                  } else if (_selectedPurchaseUnitId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يجب اختيار وحدة الشراء أولاً'),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
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
              color: AppColors.infoLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'كم ${_unitNameById(_selectedBaseUnitId)} تساوي الوحدة الأكبر؟',
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
                      size: 40, color: AppColors.textTertiary.withOpacity(0.4)),
                  const SizedBox(height: 8),
                  Text('لا توجد تحويلات',
                      style: TextStyle(
                          color: AppColors.textTertiary.withOpacity(0.6))),
                  const SizedBox(height: 4),
                  Text('اضغط "إضافة تحويل" لتحديد وحدة أكبر',
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
                const Expanded(flex: 3, child: Text('معامل التحويل', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                const Expanded(flex: 2, child: Text('سعر البيع', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                const Expanded(flex: 2, child: Text('سعر التكلفة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
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

  Widget _buildSaleUnitCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                    color: value ? AppColors.primary : AppColors.textSecondary,
                  )),
            ),
            if (value)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('وحدة بيع افتراضية',
                    style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }

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
          _UnitConversionRow(
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

          // Factor field
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
              onChanged: (v) {
                row.factor = double.tryParse(v) ?? 1.0;
                // Recalculate inventory if this is the purchase unit
                if (row.unitId == _selectedPurchaseUnitId) {
                  _autoCalculateOpeningStock();
                }
                setState(() {}); // Rebuild to update calculation displays
              },
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
          const SizedBox(width: 6),

          // Cost price — auto-calculated from Step3 purchase unit cost price
          Expanded(
            flex: 2,
            child: _buildAutoCostPriceField(row),
          ),

          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: AppColors.error.withOpacity(0.7)),
            onPressed: () =>
                setState(() => _unitConversions.removeAt(index)),
          ),
        ],
      ),
    );
  }

  /// Build auto-calculated cost price field for conversion row.
  /// The cost price is derived from Step3's cost price (purchase unit wholesale)
  /// divided by the conversion factor.
  /// For the purchase unit row: costPrice = costPriceController value (same as wholesale).
  /// For other units: costPrice = (purchaseUnitCostPrice / purchaseUnitFactor) * thisRowFactor.
  Widget _buildAutoCostPriceField(_UnitConversionRow row) {
    final purchaseUnitCost = double.tryParse(_costPriceController.text) ?? 0.0;
    final baseUnitName = _unitNameById(_selectedBaseUnitId);

    double autoCost = 0.0;
    if (_hasMultiUnits && purchaseUnitCost > 0 && row.factor > 0) {
      if (row.unitId == _selectedPurchaseUnitId) {
        // This IS the purchase unit — cost = what user entered in Step3
        autoCost = purchaseUnitCost;
      } else {
        // Other unit: cost per this unit = base unit cost * factor
        // base unit cost = purchaseUnitCost / purchaseUnitFactor
        final purchaseFactor = _purchaseUnitFactor;
        if (purchaseFactor > 0) {
          final baseUnitCost = purchaseUnitCost / purchaseFactor;
          autoCost = baseUnitCost * row.factor;
        }
      }
    }

    // Update the row's costPrice with auto-calculated value
    if (autoCost > 0) {
      row.costPrice = autoCost;
    }

    return TextFormField(
      initialValue: autoCost > 0 ? autoCost.toStringAsFixed(2) : (row.costPrice > 0 ? row.costPrice.toStringAsFixed(2) : ''),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: row.unitId == _selectedPurchaseUnitId && _hasMultiUnits
            ? 'تكلفة $baseUnitName'
            : 'سعر التكلفة',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        suffixIcon: autoCost > 0
            ? Tooltip(
                message: 'محسوب تلقائياً من سعر تكلفة وحدة الشراء',
                child: Icon(Icons.auto_fix_high, size: 16, color: AppColors.success.withOpacity(0.7)),
              )
            : null,
      ),
      onChanged: (v) => row.costPrice = double.tryParse(v) ?? 0.0,
    );
  }

  void _addConversionRow() {
    setState(() {
      _unitConversions.add(_UnitConversionRow());
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

  /// Display string for auto-calculated opening stock
  String _calculateOpeningStockDisplay() {
    final purchaseQty = double.tryParse(_purchaseUnitQtyController.text);
    if (purchaseQty == null || purchaseQty <= 0) return '...';
    final factor = _purchaseUnitFactor;
    if (factor <= 0) return '...';
    final totalBaseQty = purchaseQty * factor;
    return totalBaseQty.toStringAsFixed(0);
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 3 – الأسعار (ISSUE 5)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPricesStep() {
    // Check if we have multi-unit setup
    final hasMulti = _hasMultiUnits;
    final purchaseUnitName = _unitNameById(_selectedPurchaseUnitId);
    final baseUnitName = _unitNameById(_selectedBaseUnitId);

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
                label: hasMulti
                    ? 'سعر تكلفة الـ $purchaseUnitName *'
                    : 'سعر التكلفة *',
                onChanged: hasMulti ? (_) => setState(() {}) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _priceField(
                controller: _sellPriceController,
                label: hasMulti
                    ? 'سعر بيع الـ ${_unitNameById(_effectiveSaleUnitId)} *'
                    : 'سعر بيع الـ $baseUnitName *',
                onChanged: hasMulti ? (_) => setState(() {}) : null,
              ),
            ),
          ],
        ),

        // Auto-calculated base unit cost display
        if (hasMulti && _costPriceController.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '↪ سعر تكلفة الـ $baseUnitName = ${_calculateBaseCostFromCostField()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        // Auto-calculated base unit sell price display
        if (hasMulti && _saleUnitSource == 1 && _sellPriceController.text.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '↪ سعر بيع الـ $baseUnitName = ${_calculateBaseSellPrice()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // أقل سعر بيع (سعر الجملة الخاصة)
        _priceField(
          controller: _specialWholesalePriceController,
          label: hasMulti
              ? 'سعر الجملة الخاصة للـ ${_unitNameById(_effectiveSaleUnitId)}'
              : 'سعر الجملة الخاصة',
        ),
        const SizedBox(height: 14),

        // سعر البيع الأدنى
        _priceField(
          controller: _minimumSalePriceController,
          label: hasMulti
              ? 'سعر البيع الأدنى للـ ${_unitNameById(_effectiveSaleUnitId)}'
              : 'سعر البيع الأدنى',
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
                title: 'شامل الضريبة',
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

  /// Display string for auto-calculated base unit cost from the cost price field
  /// When multi-unit: costPrice field shows purchase unit cost, so we divide by factor
  String _calculateBaseCostFromCostField() {
    final costPrice = double.tryParse(_costPriceController.text);
    if (costPrice == null || costPrice <= 0) return '...';
    final factor = _purchaseUnitFactor;
    if (factor <= 1) return '${costPrice.toStringAsFixed(2)} ${AppConstants.currency}';
    final baseCost = costPrice / factor;
    return '${baseCost.toStringAsFixed(2)} ${AppConstants.currency}';
  }

  /// Display string for auto-calculated base unit sell price
  /// When sale unit is the purchase unit, convert to base unit
  String _calculateBaseSellPrice() {
    final sellPrice = double.tryParse(_sellPriceController.text);
    if (sellPrice == null || sellPrice <= 0) return '...';
    final factor = _purchaseUnitFactor;
    if (factor <= 1) return '${sellPrice.toStringAsFixed(2)} ${AppConstants.currency}';
    final baseSell = sellPrice / factor;
    return '${baseSell.toStringAsFixed(2)} ${AppConstants.currency}';
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4 – المخزون (ISSUE 6)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildInventoryStep() {
    final hasMulti = _hasMultiUnits;
    final purchaseUnitName = _unitNameById(_selectedPurchaseUnitId);
    final baseUnitName = _unitNameById(_selectedBaseUnitId);

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
          // ── Multi-unit: purchase unit quantity → auto-calculate base unit qty ──
          if (hasMulti) ...[
            TextFormField(
              controller: _purchaseUnitQtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: 'عدد $purchaseUnitName المشتراة',
                prefixIcon: const Icon(Icons.add_shopping_cart),
                suffixText: purchaseUnitName,
              ),
              onChanged: (v) {
                _autoCalculateOpeningStock();
                setState(() {}); // Rebuild to update calculation display
              },
            ),
            const SizedBox(height: 8),

            // Simple auto-calculation display
            if (_purchaseUnitQtyController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '↪ الكمية = ${_calculateOpeningStockDisplay()} $baseUnitName',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
          ],

          TextFormField(
            controller: _openingStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: hasMulti
                  ? 'إجمالي الكمية ($baseUnitName)'
                  : 'الكمية الافتتاحية',
              prefixIcon: const Icon(Icons.inventory),
              suffixText: baseUnitName,
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

        // مستودع افتراضي (Searchable + "+" with empty state)
        _buildSearchableDropdownWithAdd(
          label: 'مستودع افتراضي',
          icon: Icons.warehouse,
          items: _warehouses,
          idKey: 'id',
          nameKey: 'name',
          selectedId: _selectedWarehouseId,
          onChanged: _isEditMode ? null : (v) => setState(() => _selectedWarehouseId = v),
          onAdd: () => _showAddWarehouseDialog(),
          emptyMessage: 'أضف مستودع من الإعدادات أولاً',
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
  //  STEP 5 – الموردين (ISSUE 7)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSuppliersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[4].title, _steps[4].icon),

        // المورد الافتراضي (Searchable + "+" with empty state)
        _buildSearchableDropdownWithAdd(
          label: 'المورد الافتراضي',
          icon: Icons.local_shipping,
          items: _suppliers,
          idKey: 'id',
          nameKey: 'name',
          selectedId: _selectedSupplierId,
          onChanged: (v) => setState(() => _selectedSupplierId = v),
          onAdd: () => _showAddSupplierDialog(),
          emptyMessage: 'أضف مورد من الإعدادات أولاً',
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
  //  STEP 6 – الباركود (ISSUE 8)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBarcodesStep() {
    // Build barcode list from conversions + purchase unit (NOT base unit)
    final List<_BarcodeEntry> barcodes = [];

    // Add conversion units
    for (final uc in _unitConversions) {
      barcodes.add(_BarcodeEntry(
        unitName: _unitNameById(uc.unitId),
        barcode: uc.barcode,
        conversionRow: uc,
      ));
    }

    // Add purchase unit if not already in conversions
    if (_selectedPurchaseUnitId != null &&
        _selectedPurchaseUnitId != _selectedBaseUnitId &&
        !_unitConversions.any((uc) => uc.unitId == _selectedPurchaseUnitId)) {
      barcodes.add(_BarcodeEntry(
        unitName: _unitNameById(_selectedPurchaseUnitId),
        barcode: '',
        isPurchaseUnit: true,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[5].title, _steps[5].icon),

        // Info: base unit barcode is in step 1
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.infoLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'باركود ${_unitNameById(_selectedBaseUnitId)} أُدخل في الخطوة الأولى',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
              ),
            ],
          ),
        ),

        if (barcodes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.qr_code,
                      size: 40, color: AppColors.textTertiary.withOpacity(0.4)),
                  const SizedBox(height: 8),
                  Text('لا توجد وحدات أخرى',
                      style: TextStyle(
                          color: AppColors.textTertiary.withOpacity(0.6))),
                  const SizedBox(height: 4),
                  Text('أضف وحدات أكبر في خطوة الوحدات أولاً',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          )),
                ],
              ),
            ),
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

                  // Barcode field with scan button
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: entry.barcode,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'أدخل الباركود',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 16),
                          onPressed: () async {
                            final result = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                            );
                            if (result != null && result.isNotEmpty) {
                              setState(() {
                                if (entry.conversionRow != null) {
                                  entry.conversionRow!.barcode = result;
                                }
                              });
                            }
                          },
                        ),
                      ),
                      onChanged: (v) {
                        if (entry.conversionRow != null) {
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
  //  STEP 8 – المحاسبة (ISSUE 9)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAccountingStep() {
    final isLocked = false; // Allow editing accounts in edit mode - users need to fix incorrect assignments
    final taxRate = double.tryParse(_taxRateController.text) ?? 0.0;
    final showVatAccount = taxRate > 0;

    // Ensure selected IDs exist in their respective lists to avoid DropdownButton errors
    final validSalesAccountId = _revenueAccounts.any((a) => a['id'] == _selectedSalesAccountId)
        ? _selectedSalesAccountId : null;
    final validPurchaseAccountId = _costAccounts.any((a) => a['id'] == _selectedPurchaseAccountId)
        ? _selectedPurchaseAccountId : null;
    final validInventoryAccountId = _assetAccounts.any((a) => a['id'] == _selectedInventoryAccountId)
        ? _selectedInventoryAccountId : null;
    final validCogsAccountId = _costAccounts.any((a) => a['id'] == _selectedCogsAccountId)
        ? _selectedCogsAccountId : null;
    final validVatAccountId = _liabilityAccounts.any((a) => a['id'] == _selectedVatAccountId)
        ? _selectedVatAccountId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_steps[7].title, _steps[7].icon),

        if (_isEditMode)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يمكنك تعديل الحسابات المحاسبية إذا كانت غير صحيحة',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                        ),
                  ),
                ),
              ],
            ),
          ),

        // حساب المبيعات
        DropdownButtonFormField<int>(
          value: validSalesAccountId,
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
          value: validPurchaseAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب المشتريات',
            prefixIcon: Icon(Icons.trending_down),
          ),
          items: _costAccounts
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
          value: validInventoryAccountId,
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
        const SizedBox(height: 14),

        // حساب تكلفة البضاعة المباعة (COGS)
        DropdownButtonFormField<int>(
          value: validCogsAccountId,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'حساب تكلفة البضاعة المباعة',
            prefixIcon: Icon(Icons.account_balance_wallet),
          ),
          items: _costAccounts
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(
                      '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: isLocked ? null : (v) => setState(() => _selectedCogsAccountId = v),
        ),
        const SizedBox(height: 14),

        // طريقة احتساب التكلفة (W-07)
        DropdownButtonFormField<String>(
          value: _costingMethod.value,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'طريقة احتساب التكلفة',
            prefixIcon: Icon(Icons.calculate),
          ),
          items: CostingMethod.values
              .map((m) => DropdownMenuItem<String>(
                    value: m.value,
                    child: Text(m.nameAr),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            final method = CostingMethodExt.fromValue(v);
            if (method == CostingMethod.lifo) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.warning, color: AppColors.warning, size: 40),
                  title: const Text('تنبيه'),
                  content: const Text(
                    'تنبيه: طريقة LIFO محظورة بموجب معايير IFRS (IAS 2). هذه الطريقة مسموحة فقط ضمن US GAAP. استخدامها قد يؤدي لقوائم مالية غير متوافقة مع المعايير الدولية.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _costingMethod = method);
                      },
                      child: const Text('فهمت، استمر'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              );
            } else {
              setState(() => _costingMethod = method);
            }
          },
        ),
        const SizedBox(height: 14),

        // حساب ضريبة القيمة المضافة (only show if tax > 0)
        if (showVatAccount) ...[
          DropdownButtonFormField<int>(
            value: validVatAccountId,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'حساب ضريبة القيمة المضافة',
              prefixIcon: Icon(Icons.receipt_long),
            ),
            items: _liabilityAccounts
                .map((a) => DropdownMenuItem<int>(
                      value: a['id'] as int,
                      child: Text(
                        '${a['name_ar'] ?? ''} (${a['account_code'] ?? ''})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: isLocked ? null : (v) => setState(() => _selectedVatAccountId = v),
          ),
          const SizedBox(height: 14),

          // VAT accounting info card
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.infoLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'محاسبة الضريبة',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.info,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'البيع: مدين (العميل) ← دائن (المبيعات + الضريبة)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الشراء: مدين (المشتريات + الضريبة) ← دائن (المورد)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                ),
              ],
            ),
          ),
        ],

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
    ValueChanged<String>? onChanged,
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
      onChanged: onChanged,
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

  // ═══════════════════════════════════════════════════════════════
  //  Searchable dropdown with "+" add button (ISSUE 3, 4, 6, 7)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSearchableDropdownWithAdd({
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required String idKey,
    required String nameKey,
    required int? selectedId,
    required ValueChanged<int?>? onChanged,
    required VoidCallback? onAdd,
    String? emptyMessage,
  }) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(
        text: selectedId != null
            ? (items.where((i) => i[idKey] == selectedId).isNotEmpty
                ? items.firstWhere((i) => i[idKey] == selectedId)[nameKey] as String
                : '')
            : '',
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAdd != null)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: 'إضافة جديد',
                onPressed: onAdd,
              ),
            if (selectedId != null && onChanged != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
      onTap: () {
        if (items.isEmpty && emptyMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(emptyMessage),
              backgroundColor: AppColors.warning,
            ),
          );
          onAdd?.call();
          return;
        }
        _showSearchDialog(
          label: label,
          items: items,
          idKey: idKey,
          nameKey: nameKey,
          selectedId: selectedId,
          onSelected: onChanged ?? (_) {},
        );
      },
    );
  }

  void _showSearchDialog({
    required String label,
    required List<Map<String, dynamic>> items,
    required String idKey,
    required String nameKey,
    required int? selectedId,
    required ValueChanged<int?> onSelected,
  }) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredItems = List.from(items);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(label),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'بحث...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            filteredItems = items
                                .where((i) => (i[nameKey] as String)
                                    .toLowerCase()
                                    .contains(v.toLowerCase()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final id = item[idKey] as int;
                            final name = item[nameKey] as String;
                            final isSelected = id == selectedId;
                            return ListTile(
                              dense: true,
                              title: Text(name),
                              trailing: isSelected
                                  ? const Icon(Icons.check, color: AppColors.primary)
                                  : null,
                              selected: isSelected,
                              selectedTileColor: AppColors.primary.withOpacity(0.05),
                              onTap: () {
                                onSelected(id);
                                Navigator.of(dialogContext).pop();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      searchController.dispose();
    });
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
        final id = await DatabaseHelper().insertCategory({
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
                    const Text('إضافة وحدة جديدة', style: TextStyle(fontSize: 18)),
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
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الوحدة مطلوب' : null,
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
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setDialogState(() => selectedType = v ?? 'count'),
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
                              onSelected: (v) => setDialogState(() => isActive = v),
                              selectedColor: AppColors.successLight,
                            ),
                            FilterChip(
                              label: const Text('قابلة للبيع'),
                              selected: isSellable,
                              onSelected: (v) => setDialogState(() => isSellable = v),
                              selectedColor: AppColors.infoLight,
                            ),
                            FilterChip(
                              label: const Text('قابلة للشراء'),
                              selected: isPurchasable,
                              onSelected: (v) => setDialogState(() => isPurchasable = v),
                              selectedColor: AppColors.infoLight,
                            ),
                            FilterChip(
                              label: const Text('وحدة تغليف'),
                              selected: isPackaging,
                              onSelected: (v) => setDialogState(() => isPackaging = v),
                              selectedColor: AppColors.warningLight,
                            ),
                            FilterChip(
                              label: const Text('وحدة أساسية'),
                              selected: isBaseUnit,
                              onSelected: (v) => setDialogState(() => isBaseUnit = v),
                              selectedColor: AppColors.primaryLight.withOpacity(0.2),
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
      final id = await DatabaseHelper().insertUnit({
        'name_ar': nameArController.text.trim(),
        'name_en': nameEnController.text.trim(),
        'abbreviation': abbrController.text.trim(),
        'unit_type': selectedType,
        'description': descController.text.trim().isNotEmpty ? descController.text.trim() : null,
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
        final id = await DatabaseHelper().insertWarehouse({
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
                    Icon(Icons.local_shipping, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    const Text('إضافة مورد جديد', style: TextStyle(fontSize: 18)),
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
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
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
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}'))
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'الرصيد الافتتاحي',
                                  prefixIcon:
                                      const Icon(Icons.calculate),
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
                                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                                            onTap: () =>
                                                setDialogState(() => balanceType = 'credit'),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: balanceType == 'credit'
                                                    ? AppColors.success
                                                        .withOpacity(0.1)
                                                    : Colors.transparent,
                                                borderRadius: const BorderRadius.only(
                                                  topRight: Radius.circular(9),
                                                  bottomRight: Radius.circular(9),
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
                                            onTap: () =>
                                                setDialogState(() => balanceType = 'debit'),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: balanceType == 'debit'
                                                    ? AppColors.error
                                                        .withOpacity(0.1)
                                                    : Colors.transparent,
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(9),
                                                  bottomLeft: Radius.circular(9),
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
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
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                                  onTap: () =>
                                      setDialogState(() => contactMethod = 'whatsapp'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: contactMethod == 'whatsapp'
                                          ? const Color(0xFF25D366)
                                              .withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(9),
                                        bottomRight: Radius.circular(9),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
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
                                  onTap: () =>
                                      setDialogState(() => contactMethod = 'phone'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: contactMethod == 'phone'
                                          ? AppColors.primary.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(9),
                                        bottomLeft: Radius.circular(9),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
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
      final id = await DatabaseHelper().insertSupplier({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
        'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
        'address': addressController.text.trim().isEmpty ? null : addressController.text.trim(),
        'balance': balance,
        'balance_type': balanceType,
        'currency': 'YER',
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
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

// ═══════════════════════════════════════════════════════════════════
//  Barcode entry helper for step 6
// ═══════════════════════════════════════════════════════════════════

class _BarcodeEntry {
  final String unitName;
  String barcode;
  final _UnitConversionRow? conversionRow;
  final bool isPurchaseUnit;

  _BarcodeEntry({
    required this.unitName,
    required this.barcode,
    this.conversionRow,
    this.isPurchaseUnit = false,
  });
}
