import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/empty_state.dart';
import 'add_product_sheet.dart';

/// Products / inventory management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or barcode.
/// - Tab bar: الكل / متوفر / نفذ / قارب النفاد.
/// - Horizontal scrollable category chips.
/// - 2-column product grid with price, stock, and category.
/// - FAB for adding a new product via [AddProductSheet].
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedCategoryIndex = 0;

  // ── Demo categories ──────────────────────────────────────────
  static const _categories = [
    'الكل',
    'إلكترونيات',
    'أجهزة منزلية',
    'ملابس',
    'مواد غذائية',
    'مستلزمات مكتبية',
  ];

  // ── Demo products ────────────────────────────────────────────
  final List<Product> _products = [
    Product(
      id: 1,
      nameAr: 'هاتف سامسونج A54',
      nameEn: 'Samsung A54',
      barcode: '6901234567890',
      categoryId: 1,
      costPrice: 1200.00,
      sellPrice: 1499.00,
      wholesalePrice: 1350.00,
      currentStock: 25,
      minStock: 5,
    ),
    Product(
      id: 2,
      nameAr: 'لابتوب HP Pavilion',
      nameEn: 'HP Pavilion Laptop',
      barcode: '6909876543210',
      categoryId: 1,
      costPrice: 2800.00,
      sellPrice: 3499.00,
      wholesalePrice: 3100.00,
      currentStock: 8,
      minStock: 3,
    ),
    Product(
      id: 3,
      nameAr: 'غسالة LG 8 كجم',
      nameEn: 'LG Washer 8kg',
      categoryId: 2,
      costPrice: 1500.00,
      sellPrice: 1999.00,
      wholesalePrice: 1750.00,
      currentStock: 0,
      minStock: 2,
    ),
    Product(
      id: 4,
      nameAr: 'قميص رجالي قطني',
      nameEn: 'Men Cotton Shirt',
      categoryId: 3,
      costPrice: 45.00,
      sellPrice: 89.00,
      wholesalePrice: 65.00,
      currentStock: 120,
      minStock: 20,
    ),
    Product(
      id: 5,
      nameAr: 'أرز بسمتي 5 كجم',
      nameEn: 'Basmati Rice 5kg',
      categoryId: 4,
      costPrice: 22.00,
      sellPrice: 35.00,
      wholesalePrice: 28.00,
      currentStock: 3,
      minStock: 10,
    ),
    Product(
      id: 6,
      nameAr: 'دبابة ورق A4',
      nameEn: 'Paper Clip A4',
      categoryId: 5,
      costPrice: 8.00,
      sellPrice: 15.00,
      wholesalePrice: 11.00,
      currentStock: 200,
      minStock: 50,
    ),
    Product(
      id: 7,
      nameAr: 'شاحن سريع 65W',
      nameEn: 'Fast Charger 65W',
      barcode: '6901112223334',
      categoryId: 1,
      costPrice: 55.00,
      sellPrice: 95.00,
      wholesalePrice: 72.00,
      currentStock: 0,
      minStock: 10,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Stock status helper ──────────────────────────────────────
  /// Returns 0=available, 1=out, 2=low
  int _stockStatus(Product p) {
    if (p.currentStock <= 0) return 1;
    if (p.currentStock <= p.minStock) return 2;
    return 0;
  }

  // ── Filter logic ─────────────────────────────────────────────
  List<Product> _filterProducts(int tabIndex) {
    var filtered = _products;

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered.where((p) {
        final nameMatch = p.nameAr.contains(q) || p.nameEn.contains(q);
        final barcodeMatch = p.barcode?.contains(q) ?? false;
        return nameMatch || barcodeMatch;
      }).toList();
    }

    // Category
    if (_selectedCategoryIndex > 0) {
      filtered = filtered
          .where((p) => p.categoryId == _selectedCategoryIndex)
          .toList();
    }

    // Tab filter
    switch (tabIndex) {
      case 1: // متوفر
        filtered =
            filtered.where((p) => _stockStatus(p) == 0).toList();
        break;
      case 2: // نفذ
        filtered =
            filtered.where((p) => _stockStatus(p) == 1).toList();
        break;
      case 3: // قارب النفاد
        filtered =
            filtered.where((p) => _stockStatus(p) == 2).toList();
        break;
    }

    return filtered;
  }

  // ── Open add-product bottom sheet ────────────────────────────
  void _showAddProductSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddProductSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة المنتجات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'تصفية',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'إضافة منتج',
            onPressed: _showAddProductSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'متوفر'),
            Tab(text: 'نفذ'),
            Tab(text: 'قارب النفاد'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchBar(
              controller: _searchController,
              hintText: 'بحث بالاسم أو الباركود...',
              leading: const Icon(Icons.search),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // ── Category chips ────────────────────────────────────
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = _selectedCategoryIndex == index;
                return FilterChip(
                  label: Text(_categories[index]),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedCategoryIndex = index);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.12),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : null,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              },
            ),
          ),

          // ── Product grid ──────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(4, (tabIndex) {
                final filtered = _filterProducts(tabIndex);

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: tabIndex == 0
                        ? Icons.inventory_2_outlined
                        : tabIndex == 2
                            ? Icons.block
                            : Icons.warning_amber,
                    title: tabIndex == 0
                        ? 'لا يوجد منتجات'
                        : tabIndex == 1
                            ? 'لا يوجد منتجات متوفرة'
                            : tabIndex == 2
                                ? 'لا يوجد منتجات نفذت'
                                : 'لا يوجد منتجات قاربت النفاد',
                    subtitle: tabIndex == 0
                        ? 'قم بإضافة منتجات جديدة لبدء إدارة المخزون'
                        : 'لم يتم العثور على نتائج مطابقة',
                    actionLabel: tabIndex == 0 ? 'إضافة منتج' : null,
                    onAction: tabIndex == 0 ? _showAddProductSheet : null,
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _ProductCard(
                      product: filtered[index],
                      categoryName:
                          _categories[filtered[index].categoryId ?? 0],
                      onTap: () {
                        // TODO: Navigate to product detail
                      },
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductSheet,
        tooltip: 'إضافة منتج',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PRODUCT CARD
// ═══════════════════════════════════════════════════════════════════
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.categoryName,
    this.onTap,
  });

  final Product product;
  final String categoryName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final status = _stockStatusValue(product);

    // Stock indicator colors
    final stockColor = status == 0
        ? AppColors.success
        : status == 1
            ? AppColors.error
            : AppColors.warning;

    final stockLabel = status == 0
        ? 'متوفر'
        : status == 1
            ? 'نفذ'
            : 'قارب النفاد';

    final stockBgColor = status == 0
        ? AppColors.successLight
        : status == 1
            ? AppColors.errorLight
            : AppColors.warningLight;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product image placeholder ─────────────────────
              Center(
                child: Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 36,
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── Product name ──────────────────────────────────
              Text(
                product.nameAr,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),

              // ── Category ─────────────────────────────────────
              Text(
                categoryName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isLight
                      ? AppColors.textSecondary
                      : AppColors.darkTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),

              // ── Price ────────────────────────────────────────
              Text(
                '${product.sellPrice.toStringAsFixed(2)} ${AppConstants.currency}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),

              // ── Stock & barcode row ──────────────────────────
              Row(
                children: [
                  // Stock badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stockBgColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 6, color: stockColor),
                        const SizedBox(width: 4),
                        Text(
                          '$stockLabel: ${product.currentStock.toStringAsFixed(0)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: stockColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Barcode icon
                  if (product.barcode != null)
                    Icon(
                      Icons.qr_code,
                      size: 18,
                      color: isLight
                          ? AppColors.textHint
                          : AppColors.darkTextSecondary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _stockStatusValue(Product p) {
    if (p.currentStock <= 0) return 1;
    if (p.currentStock <= p.minStock) return 2;
    return 0;
  }
}
