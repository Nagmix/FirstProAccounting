import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/models/product_model.dart';
import '../../widgets/empty_state.dart';
import 'add_product_sheet.dart';

/// Products / inventory management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name, barcode, or item code.
/// - Tab bar: الكل / متوفر / نفذ / قارب النفاد.
/// - Horizontal scrollable category chips loaded from DB.
/// - 2-column product grid with price, stock, and category.
/// - FAB for adding a new product via [AddProductSheet].
/// - All data loaded from DatabaseHelper (no mock data).
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
  Timer? _searchDebounce;
  int _selectedCategoryIndex = 0;

  // ── Data from DB ──────────────────────────────────────────────
  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  // Resolved category names by id
  final Map<int, String> _categoryNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.trim());
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Load products and categories from DB ──────────────────────
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        locator<ProductRepository>().getAllProducts(),
        locator<ReferenceDataRepository>().getAllCategories(),
      ]);

      if (!mounted) return;

      final productsRaw = results[0];
      final categoriesRaw = results[1];

      final products =
          productsRaw.map((m) => Product.fromMap(m)).toList();

      // Build category name lookup
      final catNames = <int, String>{};
      for (final c in categoriesRaw) {
        catNames[c['id'] as int] = c['name'] as String;
      }

      setState(() {
        _products = products;
        _categories = categoriesRaw;
        _categoryNames
          ..clear()
          ..addAll(catNames);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
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
        final nameMatch = p.nameAr.contains(q) ||
            p.nameEn.contains(q) ||
            (p.itemCode?.contains(q) ?? false);
        final barcodeMatch = p.barcode?.contains(q) ?? false;
        return nameMatch || barcodeMatch;
      }).toList();
    }

    // Category
    if (_selectedCategoryIndex > 0 && _categories.isNotEmpty) {
      final selectedCatId = _categories[_selectedCategoryIndex - 1]['id'] as int;
      filtered =
          filtered.where((p) => p.categoryId == selectedCatId).toList();
    }

    // Tab filter
    switch (tabIndex) {
      case 1: // متوفر
        filtered = filtered.where((p) => _stockStatus(p) == 0).toList();
        break;
      case 2: // نفذ
        filtered = filtered.where((p) => _stockStatus(p) == 1).toList();
        break;
      case 3: // قارب النفاد
        filtered = filtered.where((p) => _stockStatus(p) == 2).toList();
        break;
    }

    return filtered;
  }

  // ── Open add-product screen ───────────────────────────────────
  Future<void> _showAddProductSheet() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddProductSheet()),
    );
    // Refresh list if a product was added
    if (result == true) {
      _loadData();
    }
  }

  // ── Get category name for product ─────────────────────────────
  String _getCategoryName(Product p) {
    if (p.categoryId != null && _categoryNames.containsKey(p.categoryId)) {
      return _categoryNames[p.categoryId]!;
    }
    return 'غير مصنف';
  }

  // ── Category chip labels ──────────────────────────────────────
  List<String> get _categoryChipLabels {
    return ['الكل', ..._categories.map((c) => c['name'] as String)];
  }

  // ── Category management dialog ────────────────────────────────
  Future<void> _showCategoryManagement() async {
    final categories = await locator<ReferenceDataRepository>().getAllCategories();

    if (!mounted) return;

    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إدارة التصنيفات'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Add new category
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم التصنيف',
                          prefixIcon: Icon(Icons.folder),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;
                        await locator<ReferenceDataRepository>().insertCategory({
                          'name': nameController.text.trim(),
                          'is_active': 1,
                          'created_at': DateTime.now().toIso8601String(),
                        });
                        nameController.clear();
                        final updated = await locator<ReferenceDataRepository>().getAllCategories();
                        setDialogState(() => categories.clear());
                        setDialogState(() => categories.addAll(updated));
                        _loadData();
                      },
                      icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // List of categories
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: categories.isEmpty
                      ? const Center(child: Text('لا توجد تصنيفات'))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final cat = categories[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder, size: 20, color: AppColors.accentOrange),
                              title: Text(cat['name'] as String),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: AppColors.error),
                                onPressed: () async {
                                  // Check if any products use this category before deleting
                                  final catId = cat['id'] as int;
                                  try {
                                    final productsWithCategory = await locator<ProductRepository>().getProductsByCategoryId(catId);
                                    if (productsWithCategory.isNotEmpty) {
                                      final productNames = productsWithCategory.map((p) => p['name_ar'] as String? ?? '').join('، ');
                                      final extra = productsWithCategory.length > 5 ? ' وغيرها...' : '';
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('لا يمكن حذف التصنيف لأنه مستخدم في الأصناف: $productNames$extra'),
                                            backgroundColor: AppColors.error,
                                            duration: const Duration(seconds: 4),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                  } catch (_) {
                                    // If check fails, proceed with delete attempt
                                  }

                                  await locator<ReferenceDataRepository>().deleteCategory(catId);
                                  final updated = await locator<ReferenceDataRepository>().getAllCategories();
                                  setDialogState(() => categories.clear());
                                  setDialogState(() => categories.addAll(updated));
                                  _loadData();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nameController.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الأصناف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.straighten),
            tooltip: 'إدارة الوحدات',
            onPressed: () => Navigator.pushNamed(context, '/units'),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'إدارة التصنيفات',
            onPressed: _showCategoryManagement,
          ),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'إضافة صنف',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث بالاسم، الباركود، أو رمز الصنف...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Category chips ──────────────────────────────
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    itemCount: _categoryChipLabels.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final selected = _selectedCategoryIndex == index;
                      return FilterChip(
                        label: Text(_categoryChipLabels[index]),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedCategoryIndex = index);
                        },
                        selectedColor:
                            AppColors.primary.withOpacity(0.12),
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

                // ── Product grid ────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List.generate(4, (tabIndex) {
                      final filtered = _filterProducts(tabIndex);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: tabIndex == 0
                              ? Icons.inventory_2
                              : tabIndex == 2
                                  ? Icons.block
                                  : Icons.warning,
                          title: tabIndex == 0
                              ? 'لا يوجد أصناف'
                              : tabIndex == 1
                                  ? 'لا يوجد أصناف متوفرة'
                                  : tabIndex == 2
                                      ? 'لا يوجد أصناف نفذت'
                                      : 'لا يوجد أصناف قاربت النفاد',
                          subtitle: tabIndex == 0
                              ? 'قم بإضافة أصناف جديدة لبدء إدارة المخزون'
                              : 'لم يتم العثور على نتائج مطابقة',
                          actionLabel:
                              tabIndex == 0 ? 'إضافة صنف' : null,
                          onAction:
                              tabIndex == 0 ? _showAddProductSheet : null,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadData,
                        child: GridView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
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
                                  _getCategoryName(filtered[index]),
                              onTap: () async {
                                final result = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => AddProductSheet(existing: filtered[index]),
                                  ),
                                );
                                if (result == true) {
                                  _loadData();
                                }
                              },
                            );
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductSheet,
        tooltip: 'إضافة صنف',
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

  int _stockStatusValue(Product p) {
    if (p.currentStock <= 0) return 1;
    if (p.currentStock <= p.minStock) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final status = _stockStatusValue(product);

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
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    size: 36,
                    color: AppColors.primary.withOpacity(0.4),
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
              if (product.nameEn.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  product.nameEn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isLight
                        ? AppColors.textSecondary
                        : AppColors.darkTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stockBgColor.withOpacity(0.5),
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
                  // Barcode / item code icon
                  if (product.barcode != null || product.itemCode != null)
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
}
