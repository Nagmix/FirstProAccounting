import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../data/datasources/repositories/product_repository.dart';
import '../../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/barcode_scanner_screen.dart';

class AddInvoiceItemSheet extends StatefulWidget {
  final int? warehouseId;
  final String invoiceType; // 'sale' or 'purchase'
  const AddInvoiceItemSheet({super.key, this.warehouseId, this.invoiceType = 'sale'});

  @override
  State<AddInvoiceItemSheet> createState() => _AddInvoiceItemSheetState();
}

class _AddInvoiceItemSheetState extends State<AddInvoiceItemSheet> {
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  Product? _selectedProduct;
  List<Product> _searchResults = [];
  bool _isSearching = false;

  // Unit selection
  List<Map<String, dynamic>> _availableUnits = [];
  Map<String, dynamic>? _selectedUnit;
  bool _loadingUnits = false;

  double get _quantity => double.tryParse(_quantityController.text) ?? 1;
  double get _unitPrice => double.tryParse(_priceController.text) ?? 0;
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _total => (_quantity * _unitPrice) - _discount;
  double get _conversionFactor => (_selectedUnit?['conversion_factor'] as num?)?.toDouble() ?? 1.0;
  double get _baseQuantity => _quantity * _conversionFactor;
  String get _unitName => (_selectedUnit?['unit_name'] as String?) ?? '';

  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _searchProducts('');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchProducts(String query) async {
    setState(() => _isSearching = true);
    List<Map<String, dynamic>> maps;
    if (query.isEmpty) {
      maps = await locator<ProductRepository>().getAllProducts(activeOnly: true);
    } else {
      maps = await locator<ProductRepository>().searchProducts(query, warehouseId: widget.warehouseId);
    }
    if (!mounted) return;
    setState(() {
      _searchResults = maps.map((m) => Product.fromMap(m)).toList();
      _isSearching = false;
    });
  }

  Future<void> _loadUnitsForProduct(int productId) async {
    setState(() => _loadingUnits = true);
    final units = await locator<ReferenceDataRepository>().getAvailableUnitsForProduct(productId);
    if (!mounted) return;
    setState(() {
      _availableUnits = units;
      _loadingUnits = false;
      // Auto-select default unit based on invoice type
      if (units.isNotEmpty) {
        if (widget.invoiceType == 'purchase' && units.length > 1) {
          // For purchase, prefer non-base unit (e.g., carton) if available
          final nonBase = units.where((u) => u['is_base'] == 0).toList();
          _selectedUnit = nonBase.isNotEmpty ? nonBase.first : units.first;
        } else {
          _selectedUnit = units.first;
        }
        // Use cost_price for purchase invoices, sell_price for sale invoices
        // Note: getAvailableUnitsForProduct already converts cents to doubles
        if (widget.invoiceType == 'purchase') {
          _priceController.text = ((_selectedUnit?['cost_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
        } else {
          _priceController.text = ((_selectedUnit?['sell_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : const Color(0xFFF8F9FE),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              offset: const Offset(0, -4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle + Header ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkDivider : AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header row
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accentBlue, _accentPurple],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(11)),
                        ),
                        child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('إضافة صنف',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.close_rounded, size: 16, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search / barcode field
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو الباركود...',
                      prefixIcon: Icon(Icons.search_rounded, color: _accentBlue, size: 20),
                      suffixIcon: Container(
                        margin: const EdgeInsets.only(left: 4, right: 4),
                        child: IconButton(
                          icon: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: _accentBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.qr_code_scanner_rounded, size: 16, color: _accentBlue),
                          ),
                          tooltip: 'مسح باركود',
                          onPressed: () async {
                            final result = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                            );
                            if (result != null && result.isNotEmpty) {
                              _searchController.text = result;
                              _searchProducts(result);
                            }
                          },
                        ),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
                    ),
                    onChanged: (value) => _searchProducts(value),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ───────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product search results
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            offset: const Offset(0, 2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: _isSearching
                          ? Center(child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _accentBlue),
                              ),
                            ))
                          : _searchResults.isEmpty
                              ? Center(child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                          color: _accentBlue.withOpacity(0.06),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.search_off_rounded, size: 24, color: _accentBlue.withOpacity(0.4)),
                                      ),
                                      const SizedBox(height: 8),
                                      Text('لا توجد نتائج', style: context.textTheme.bodyMedium?.copyWith(color: AppColors.textHint)),
                                    ],
                                  ),
                                ))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final product = _searchResults[index];
                                    final isSelected = _selectedProduct?.id == product.id;
                                    return _buildProductTile(product, isSelected, isDark);
                                  },
                                ),
                    ),
                    const SizedBox(height: 12),

                    // Unit selection (if multiple units available)
                    if (_selectedProduct != null && _availableUnits.length > 1) ...[
                      _buildUnitSelector(isDark),
                      const SizedBox(height: 12),
                    ],

                    // Loading units indicator
                    if (_loadingUnits)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Center(child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _accentBlue),
                        )),
                      ),

                    // Quantity & price row
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'الكمية${_unitName.isNotEmpty ? ' ($_unitName)' : ''}',
                            controller: _quantityController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            label: widget.invoiceType == 'purchase' ? 'سعر التكلفة${_unitName.isNotEmpty ? ' ($_unitName)' : ''}' : 'سعر البيع${_unitName.isNotEmpty ? ' ($_unitName)' : ''}',
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            suffixText: AppConstants.currency,
                            onChanged: (_) => setState(() {}),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Show base quantity info
                    if (_selectedUnit != null && _conversionFactor != 1.0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(isDark ? 0.12 : 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.info.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.info.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.info_outline_rounded, size: 12, color: AppColors.info),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'الكمية بالوحدة الأساسية: ${_baseQuantity.toStringAsFixed(2)}',
                              style: context.textTheme.bodySmall?.copyWith(color: AppColors.info, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    _buildTextField(
                      label: 'خصم على الصنف',
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      suffixText: AppConstants.currency,
                      onChanged: (_) => setState(() {}),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    _buildTextField(label: 'ملاحظات', controller: _notesController, maxLines: 2, isDark: isDark),
                    const SizedBox(height: 16),

                    // Total
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _accentBlue.withOpacity(isDark ? 0.15 : 0.08),
                            _accentPurple.withOpacity(isDark ? 0.08 : 0.03),
                          ],
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _accentBlue.withOpacity(0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calculate_rounded, size: 16, color: _accentBlue),
                              const SizedBox(width: 6),
                              Text('الإجمالي', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          Text(CurrencyFormatter.format(_total),
                              style: context.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: _accentBlue,
                                fontSize: 20,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Add button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accentBlue, _accentPurple],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _accentBlue.withOpacity(0.25),
                              offset: const Offset(0, 4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _addItem,
                            borderRadius: BorderRadius.circular(14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_circle_rounded, size: 20, color: Colors.white),
                                const SizedBox(width: 8),
                                const Text('إضافة',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Bottom safe area
                    SizedBox(height: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Product tile with avatar ──────────────────────────────────────
  Widget _buildProductTile(Product product, bool isSelected, bool isDark) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedProduct = product;
          _searchController.text = product.nameAr;
          _availableUnits = [];
          _selectedUnit = null;
        });
        _loadUnitsForProduct(product.id!);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentBlue.withOpacity(0.06) : null,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: _accentBlue.withOpacity(0.2)) : null,
        ),
        child: Row(
          children: [
            // Product avatar
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(colors: [_accentBlue, _accentPurple], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: isSelected ? null : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                    : Icon(Icons.inventory_2_rounded, size: 16, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.nameAr,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${CurrencyFormatter.format(product.sellPrice)} | المخزون: ${product.currentStock.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Unit selector ─────────────────────────────────────────────────
  Widget _buildUnitSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accentBlue.withOpacity(isDark ? 0.1 : 0.04),
            _accentPurple.withOpacity(isDark ? 0.05 : 0.02),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentBlue.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: _accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.straighten_rounded, size: 14, color: _accentBlue),
              ),
              const SizedBox(width: 8),
              Text('اختر الوحدة',
                style: context.textTheme.titleSmall?.copyWith(
                  color: _accentBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableUnits.map((unit) {
              final isSelected = _selectedUnit?['unit_name'] == unit['unit_name'];
              // Show cost_price for purchase invoices, sell_price for sale invoices
              final price = widget.invoiceType == 'purchase'
                  ? MoneyHelper.readMoney(unit['cost_price'])
                  : MoneyHelper.readMoney(unit['sell_price']);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedUnit = unit;
                    _priceController.text = price.toStringAsFixed(2);
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.fastOutSlowIn,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accentBlue.withOpacity(isDark ? 0.2 : 0.1)
                        : (isDark ? AppColors.darkSurface : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? _accentBlue : (isDark ? AppColors.darkBorder : AppColors.border),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: _accentBlue.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected)
                        Container(
                          width: 16, height: 16,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [_accentBlue, _accentPurple]),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                          ),
                          child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                        ),
                      Text('${unit['unit_name']} (${CurrencyFormatter.format(price)})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? _accentBlue : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    bool isDark = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentBlue, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withOpacity(0.3),
      ),
    );
  }

  void _addItem() {
    if (_selectedProduct == null) {
      context.showErrorSnackBar('الرجاء اختيار المنتج');
      return;
    }
    if (_quantity <= 0) {
      context.showErrorSnackBar('يرجى إدخال كمية صحيحة أكبر من صفر');
      return;
    }
    if (_unitPrice <= 0) {
      context.showErrorSnackBar('يرجى إدخال سعر صحيح أكبر من صفر');
      return;
    }
    if (_discount < 0) {
      context.showErrorSnackBar('الخصم لا يمكن أن يكون سالباً');
      return;
    }
    if (_discount > _quantity * _unitPrice) {
      context.showErrorSnackBar('الخصم لا يمكن أن يتجاوز إجمالي الصنف');
      return;
    }

    // التحقق من المخزون المتاح للبيع (وليس المرتجع)
    if (widget.invoiceType == 'sale' && _selectedProduct!.currentStock > 0) {
      if (_baseQuantity > _selectedProduct!.currentStock && !_selectedProduct!.allowNegative) {
        context.showErrorSnackBar(
          'الكمية المطلوبة ($_baseQuantity) تتجاوز المخزون المتاح (${_selectedProduct!.currentStock.toStringAsFixed(1)})',
        );
        return;
      }
    }

    final item = InvoiceItem(
      invoiceId: '',
      productId: _selectedProduct!.id!,
      productName: _selectedProduct!.nameAr,
      quantity: _quantity,
      unitPrice: _unitPrice,
      totalPrice: _total,
      unitName: _unitName.isNotEmpty ? _unitName : null,
      conversionFactor: _conversionFactor,
      baseQuantity: _baseQuantity,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    Navigator.pop(context, item);
  }
}
