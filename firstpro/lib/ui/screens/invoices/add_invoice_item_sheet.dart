import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/invoice_item_model.dart';
import '../../../data/models/product_model.dart';

/// Bottom sheet for adding a single item to an invoice.
///
/// Provides product search/select, quantity, unit price (auto-filled),
/// per-item discount, notes, and auto-calculated total.
class AddInvoiceItemSheet extends StatefulWidget {
  const AddInvoiceItemSheet({super.key});

  @override
  State<AddInvoiceItemSheet> createState() => _AddInvoiceItemSheetState();
}

class _AddInvoiceItemSheetState extends State<AddInvoiceItemSheet> {
  // ── Form controllers ─────────────────────────────────────────────
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();

  Product? _selectedProduct;

  // ── Demo products ────────────────────────────────────────────────
  final List<Product> _demoProducts = [
    Product(id: 1, nameAr: 'قلم حبر أزرق', nameEn: 'Blue Pen', sellPrice: 5.0, currentStock: 200),
    Product(id: 2, nameAr: 'دفتر A4', nameEn: 'A4 Notebook', sellPrice: 15.0, currentStock: 150),
    Product(id: 3, nameAr: 'حبر طابعة HP', nameEn: 'HP Ink', sellPrice: 120.0, currentStock: 30),
    Product(id: 4, nameAr: 'ورق طباعة A4', nameEn: 'A4 Paper', sellPrice: 45.0, currentStock: 500),
    Product(id: 5, nameAr: 'مجلد بلاستيك', nameEn: 'Plastic Folder', sellPrice: 8.0, currentStock: 300),
    Product(id: 6, nameAr: 'مسامير 5سم', nameEn: '5cm Nails', sellPrice: 3.5, currentStock: 1000),
    Product(id: 7, nameAr: 'طلاء أبيض 4لتر', nameEn: 'White Paint 4L', sellPrice: 95.0, currentStock: 50),
    Product(id: 8, nameAr: 'فرشاة دهان', nameEn: 'Paint Brush', sellPrice: 25.0, currentStock: 80),
  ];

  double get _quantity => double.tryParse(_quantityController.text) ?? 1;
  double get _unitPrice => double.tryParse(_priceController.text) ?? 0;
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _total => (_quantity * _unitPrice) - _discount;

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('إضافة صنف', style: context.textTheme.titleLarge),
              const SizedBox(height: 16),

              // ── Product search / select ────────────────────────
              Text('المنتج', style: context.textTheme.titleSmall),
              const SizedBox(height: 6),
              _buildProductDropdown(),
              const SizedBox(height: 16),

              // ── Quantity & price row ───────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'الكمية',
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      label: 'سعر الوحدة',
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      suffixText: AppConstants.currency,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Discount ───────────────────────────────────────
              _buildTextField(
                label: 'خصم على الصنف',
                controller: _discountController,
                keyboardType: TextInputType.number,
                suffixText: AppConstants.currency,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // ── Notes ──────────────────────────────────────────
              _buildTextField(
                label: 'ملاحظات',
                controller: _notesController,
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // ── Total ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي', style: context.textTheme.titleSmall),
                    Text(
                      CurrencyFormatter.format(_total),
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Add button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _addItem,
                  child: const Text('إضافة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Product dropdown with search ─────────────────────────────────
  Widget _buildProductDropdown() {
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.nameAr,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return _demoProducts;
        final q = textEditingValue.text.toLowerCase();
        return _demoProducts.where((p) =>
            p.nameAr.contains(q) ||
            p.nameEn.toLowerCase().contains(q) ||
            (p.barcode ?? '').contains(q));
      },
      onSelected: (product) {
        setState(() {
          _selectedProduct = product;
          _priceController.text = product.sellPrice.toStringAsFixed(2);
        });
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'بحث أو اسم المنتج...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _selectedProduct != null
                ? Icon(Icons.check_circle, color: AppColors.success)
                : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final product = options.elementAt(index);
                return ListTile(
                  dense: true,
                  title: Text(product.nameAr),
                  subtitle: Text(CurrencyFormatter.format(product.sellPrice)),
                  trailing: Text(
                    'المخزون: ${product.currentStock.toStringAsFixed(0)}',
                    style: context.textTheme.bodySmall,
                  ),
                  onTap: () => onSelected(product),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ── Reusable text field builder ──────────────────────────────────
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
      ),
    );
  }

  // ── Add item action ──────────────────────────────────────────────
  void _addItem() {
    if (_selectedProduct == null) {
      context.showErrorSnackBar('الرجاء اختيار المنتج');
      return;
    }
    if (_quantity <= 0) {
      context.showErrorSnackBar('الرجاء إدخال كمية صحيحة');
      return;
    }
    if (_unitPrice <= 0) {
      context.showErrorSnackBar('الرجاء إدخال سعر صحيح');
      return;
    }

    final item = InvoiceItem(
      invoiceId: '',
      productId: _selectedProduct!.id!,
      productName: _selectedProduct!.nameAr,
      quantity: _quantity,
      unitPrice: _unitPrice,
      totalPrice: _total,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    Navigator.pop(context, item);
  }
}
