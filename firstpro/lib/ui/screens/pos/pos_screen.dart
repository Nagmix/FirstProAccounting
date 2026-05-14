import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/cart_item_tile.dart';

/// Point of Sale (POS) screen – optimized for speed with large touch targets.
///
/// Layout: product grid (left 60%) + cart summary (right 40%).
/// All text is Arabic and the layout is fully RTL.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  // ── Search ───────────────────────────────────────────────────────
  final _searchController = TextEditingController();

  // ── Cart state ───────────────────────────────────────────────────
  final List<_CartItem> _cart = [];
  String _paymentMethod = 'cash'; // cash, credit, card
  int? _selectedCategoryId;
  double _orderDiscount = 0;

  // ── Held orders ──────────────────────────────────────────────────
  final List<_HeldOrder> _heldOrders = [];

  // ── Demo categories ──────────────────────────────────────────────
  final List<Map<String, dynamic>> _categories = const [
    {'id': null, 'name': 'الكل', 'icon': Icons.apps},
    {'id': 1, 'name': 'أدوات مكتبية', 'icon': Icons.edit},
    {'id': 2, 'name': 'دهانات', 'icon': Icons.format_paint},
    {'id': 3, 'name': 'أدوات بناء', 'icon': Icons.construction},
    {'id': 4, 'name': 'كهربائيات', 'icon': Icons.electrical_services},
    {'id': 5, 'name': 'سباكة', 'icon': Icons.plumbing},
  ];

  // ── Demo products ────────────────────────────────────────────────
  final List<Product> _products = [
    Product(id: 1, nameAr: 'قلم حبر أزرق', nameEn: 'Blue Pen', categoryId: 1, sellPrice: 5.0, currentStock: 200),
    Product(id: 2, nameAr: 'دفتر A4', nameEn: 'A4 Notebook', categoryId: 1, sellPrice: 15.0, currentStock: 150),
    Product(id: 3, nameAr: 'حبر طابعة HP', nameEn: 'HP Ink', categoryId: 1, sellPrice: 120.0, currentStock: 30),
    Product(id: 4, nameAr: 'ورق طباعة A4', nameEn: 'A4 Paper', categoryId: 1, sellPrice: 45.0, currentStock: 500),
    Product(id: 5, nameAr: 'مجلد بلاستيك', nameEn: 'Plastic Folder', categoryId: 1, sellPrice: 8.0, currentStock: 300),
    Product(id: 6, nameAr: 'طلاء أبيض 4لتر', nameEn: 'White Paint 4L', categoryId: 2, sellPrice: 95.0, currentStock: 50),
    Product(id: 7, nameAr: 'طلاء أزرق 4لتر', nameEn: 'Blue Paint 4L', categoryId: 2, sellPrice: 95.0, currentStock: 35),
    Product(id: 8, nameAr: 'فرشاة دهان', nameEn: 'Paint Brush', categoryId: 2, sellPrice: 25.0, currentStock: 80),
    Product(id: 9, nameAr: 'مسامير 5سم', nameEn: '5cm Nails', categoryId: 3, sellPrice: 3.5, currentStock: 1000),
    Product(id: 10, nameAr: 'مطرقة 500غ', nameEn: 'Hammer 500g', categoryId: 3, sellPrice: 45.0, currentStock: 60),
    Product(id: 11, nameAr: 'كابل كهربائي 10م', nameEn: 'Electric Cable 10m', categoryId: 4, sellPrice: 55.0, currentStock: 120),
    Product(id: 12, nameAr: 'مقبس كهربائي', nameEn: 'Electric Socket', categoryId: 4, sellPrice: 12.0, currentStock: 200),
    Product(id: 13, nameAr: 'أنبوب PVC 4م', nameEn: 'PVC Pipe 4m', categoryId: 5, sellPrice: 30.0, currentStock: 90),
    Product(id: 14, nameAr: 'صنبور مياه', nameEn: 'Water Tap', categoryId: 5, sellPrice: 65.0, currentStock: 45),
    Product(id: 15, nameAr: 'صمام تحكم', nameEn: 'Control Valve', categoryId: 5, sellPrice: 38.0, currentStock: 70),
  ];

  List<Product> get _filteredProducts {
    var result = _products;
    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      result = result.where((p) =>
          p.nameAr.contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          (p.barcode ?? '').contains(q)).toList();
    }
    return result;
  }

  double get _subtotal => _cart.fold(0, (sum, i) => sum + i.total);
  double get _tax => (_subtotal - _orderDiscount) * (AppConstants.defaultVatRate / 100);
  double get _total => _subtotal - _orderDiscount + _tax;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: context.isMobile
            ? _buildMobileLayout()
            : _buildTabletLayout(),
        floatingActionButton: FloatingActionButton(
          onPressed: _scanBarcode,
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.white,
          tooltip: 'مسح باركود',
          child: const Icon(Icons.qr_code_scanner),
        ),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('نقطة البيع'),
      actions: [
        // Held orders
        Badge(
          isLabelVisible: _heldOrders.isNotEmpty,
          label: Text('${_heldOrders.length}'),
          child: IconButton(
            onPressed: _showHeldOrders,
            icon: const Icon(Icons.pause_circle_outlined),
            tooltip: 'طلبات معلقة',
          ),
        ),
        // Discount
        IconButton(
          onPressed: _showDiscountDialog,
          icon: const Icon(Icons.discount_outlined),
          tooltip: 'خصم',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TABLET / DESKTOP LAYOUT (60/40 split)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTabletLayout() {
    return Row(
      children: [
        // ── Product grid side (60%) ─────────────────────────────
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _buildSearchBar(),
              _buildCategoryChips(),
              Expanded(child: _buildProductGrid()),
            ],
          ),
        ),

        // ── Vertical divider ────────────────────────────────────
        const VerticalDivider(width: 1),

        // ── Cart side (40%) ─────────────────────────────────────
        Expanded(
          flex: 4,
          child: _buildCartPanel(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MOBILE LAYOUT (stacked)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryChips(),
        Expanded(
          child: _cart.isEmpty
              ? _buildProductGrid()
              : _buildCartPanel(),
        ),
      ],
    );
  }

  // ── Search bar ───────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'بحث عن منتج أو باركود...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('مسح'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category chips ───────────────────────────────────────────────
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategoryId == cat['id'];
          return FilterChip(
            avatar: Icon(cat['icon'] as IconData, size: 16),
            label: Text(cat['name'] as String),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedCategoryId = cat['id'] as int?);
            },
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            checkmarkColor: AppColors.primary,
          );
        },
      ),
    );
  }

  // ── Product grid ─────────────────────────────────────────────────
  Widget _buildProductGrid() {
    final products = _filteredProducts;

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('لا توجد منتجات', style: context.textTheme.titleMedium),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.78,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return _ProductCard(
          product: products[index],
          onTap: () => _addToCart(products[index]),
        );
      },
    );
  }

  // ── Cart panel ───────────────────────────────────────────────────
  Widget _buildCartPanel() {
    final isDark = context.isDarkMode;

    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.surfaceVariant,
      child: Column(
        children: [
          // ── Cart header ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'سلة المشتريات',
                  style: context.textTheme.titleSmall,
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _cart.clear()),
                    child: const Text('مسح الكل'),
                  ),
              ],
            ),
          ),

          // ── Cart items ────────────────────────────────────────
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 56, color: AppColors.textHint),
                        const SizedBox(height: 8),
                        Text('السلة فارغة',
                            style: context.textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text('اضغط على المنتج لإضافته',
                            style: context.textTheme.bodySmall),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return CartItemTile(
                        name: item.name,
                        quantity: item.quantity,
                        unitPrice: item.unitPrice,
                        total: item.total,
                        onIncrement: () {
                          setState(() {
                            _cart[index] = item.copyWith(
                              quantity: item.quantity + 1,
                            );
                          });
                        },
                        onDecrement: () {
                          setState(() {
                            if (item.quantity > 1) {
                              _cart[index] = item.copyWith(
                                quantity: item.quantity - 1,
                              );
                            } else {
                              _cart.removeAt(index);
                            }
                          });
                        },
                        onDelete: () {
                          setState(() => _cart.removeAt(index));
                        },
                      );
                    },
                  ),
          ),

          // ── Payment method quick buttons ──────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            child: Row(
              children: [
                _paymentButton('نقدي', 'cash', Icons.money),
                const SizedBox(width: 6),
                _paymentButton('آجل', 'credit', Icons.schedule),
                const SizedBox(width: 6),
                _paymentButton('بطاقة', 'card', Icons.credit_card),
              ],
            ),
          ),

          // ── Totals & action buttons ───────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Subtotal
                  _totalRow('المجموع الفرعي', CurrencyFormatter.format(_subtotal)),
                  if (_orderDiscount > 0) ...[
                    const SizedBox(height: 4),
                    _totalRow(
                      'الخصم',
                      '- ${CurrencyFormatter.format(_orderDiscount)}',
                      valueColor: AppColors.error,
                    ),
                  ],
                  const SizedBox(height: 4),
                  _totalRow(
                    'الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)',
                    CurrencyFormatter.format(_tax),
                  ),
                  const Divider(height: 16),
                  _totalRow(
                    'الإجمالي',
                    CurrencyFormatter.format(_total),
                    valueStyle: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Checkout button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _cart.isEmpty ? null : _checkout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'إنهاء البيع  ${CurrencyFormatter.format(_total)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Hold order button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _cart.isEmpty ? null : _holdOrder,
                      icon: const Icon(Icons.pause_circle_outline, size: 20),
                      label: const Text('تعليق الطلب'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentButton(String label, String method, IconData icon) {
    final selected = _paymentMethod == method;
    return Expanded(
      child: SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: () => setState(() => _paymentMethod = method),
          style: OutlinedButton.styleFrom(
            backgroundColor:
                selected ? AppColors.primary.withValues(alpha: 0.1) : null,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? AppColors.primary : null),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalRow(
    String label,
    String value, {
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium),
        Text(
          value,
          style: valueStyle ??
              context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════════════
  void _addToCart(Product product) {
    final existingIndex =
        _cart.indexWhere((i) => i.productId == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _cart[existingIndex] = _cart[existingIndex].copyWith(
          quantity: _cart[existingIndex].quantity + 1,
        );
      });
    } else {
      setState(() {
        _cart.add(_CartItem(
          productId: product.id!,
          name: product.nameAr,
          unitPrice: product.sellPrice,
          quantity: 1,
        ));
      });
    }
  }

  void _checkout() {
    // TODO: create invoice and navigate to receipt
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تم إنهاء البيع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الإجمالي: ${CurrencyFormatter.format(_total)}'),
            Text('طريقة الدفع: ${_paymentMethod == 'cash' ? 'نقدي' : _paymentMethod == 'credit' ? 'آجل' : 'بطاقة'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _cart.clear();
                _orderDiscount = 0;
              });
            },
            child: const Text('فاتورة جديدة'),
          ),
        ],
      ),
    );
  }

  void _holdOrder() {
    _heldOrders.add(_HeldOrder(
      items: List.from(_cart),
      paymentMethod: _paymentMethod,
      discount: _orderDiscount,
      createdAt: DateTime.now(),
    ));
    setState(() {
      _cart.clear();
      _orderDiscount = 0;
    });
    context.showSuccessSnackBar('تم تعليق الطلب');
  }

  void _showHeldOrders() {
    if (_heldOrders.isEmpty) {
      context.showSnackBar('لا توجد طلبات معلقة');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الطلبات المعلقة',
                  style: context.textTheme.titleLarge),
              const SizedBox(height: 12),
              ..._heldOrders.asMap().entries.map((entry) {
                final idx = entry.key;
                final order = entry.value;
                final total =
                    order.items.fold(0.0, (s, i) => s + i.total);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.secondary.withValues(alpha: 0.15),
                    child: Text('${idx + 1}'),
                  ),
                  title: Text(
                    '${order.items.length} صنف – ${CurrencyFormatter.format(total.toDouble())}',
                  ),
                  subtitle: Text(
                    DateFormatter.formatDateTime(order.createdAt),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _cart.clear();
                            _cart.addAll(order.items);
                            _paymentMethod = order.paymentMethod;
                            _orderDiscount = order.discount;
                            _heldOrders.removeAt(idx);
                          });
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.restore,
                            color: AppColors.primary),
                        tooltip: 'استرجاع',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _heldOrders.removeAt(idx));
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        tooltip: 'حذف',
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiscountDialog() {
    final controller = TextEditingController(
      text: _orderDiscount > 0 ? _orderDiscount.toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خصم على الطلب'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'مبلغ الخصم',
              suffixText: AppConstants.currency,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _orderDiscount = 0);
                Navigator.pop(ctx);
              },
              child: const Text('إزالة الخصم'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _orderDiscount =
                      double.tryParse(controller.text) ?? 0;
                });
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  void _scanBarcode() {
    // TODO: integrate barcode scanner
    context.showSnackBar('ماسح الباركود قيد التطوير');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRODUCT CARD (grid item)
// ═══════════════════════════════════════════════════════════════════════════
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lowStock = product.currentStock <= product.minStock && product.currentStock > 0;
    final outOfStock = product.currentStock <= 0;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon ───────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 8),

              // ── Name ───────────────────────────────────────────
              Text(
                product.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),

              // ── Price ──────────────────────────────────────────
              Text(
                CurrencyFormatter.format(product.sellPrice),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),

              // ── Stock badge ────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? AppColors.errorLight
                      : lowStock
                          ? AppColors.warningLight
                          : AppColors.successLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  outOfStock
                      ? 'نفذ'
                      : lowStock
                          ? 'مخزون منخفض'
                          : '${product.currentStock.toStringAsFixed(0)} قطعة',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? AppColors.error
                        : lowStock
                            ? AppColors.warning
                            : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CART ITEM MODEL (local to POS)
// ═══════════════════════════════════════════════════════════════════════════
class _CartItem {
  final int productId;
  final String name;
  final double unitPrice;
  final double quantity;

  _CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  double get total => unitPrice * quantity;

  _CartItem copyWith({int? productId, String? name, double? unitPrice, double? quantity}) {
    return _CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HELD ORDER MODEL
// ═══════════════════════════════════════════════════════════════════════════
class _HeldOrder {
  final List<_CartItem> items;
  final String paymentMethod;
  final double discount;
  final DateTime createdAt;

  _HeldOrder({
    required this.items,
    required this.paymentMethod,
    required this.discount,
    required this.createdAt,
  });
}
