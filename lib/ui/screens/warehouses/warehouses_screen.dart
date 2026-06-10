import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/repositories/product_repository.dart';
import 'package:firstpro/ui/screens/warehouses/add_warehouse_sheet.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  List<Map<String, dynamic>> _warehouses = [];
  Map<int, int> _productCounts = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _isLoading = true);
    try {
      final warehouses =
          await locator<ReferenceDataRepository>().getAllWarehouses();

      // Load product counts per warehouse
      final counts = <int, int>{};
      for (final w in warehouses) {
        final id = w['id'] as int;
        counts[id] =
            await locator<ProductRepository>().getProductCountByWarehouse(id);
      }

      if (mounted) {
        setState(() {
          _warehouses = warehouses;
          _productCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredWarehouses {
    if (_searchQuery.isEmpty) return _warehouses;
    final q = _searchQuery.toLowerCase();
    return _warehouses.where((w) {
      final name = (w['name'] as String? ?? '').toLowerCase();
      final location = (w['location'] as String? ?? '').toLowerCase();
      return name.contains(q) || location.contains(q);
    }).toList();
  }

  Future<void> _showAddSheet({Map<String, dynamic>? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddWarehouseSheet(existing: existing),
    );
    _loadWarehouses();
  }

  Future<void> _deleteWarehouse(Map<String, dynamic> warehouse) async {
    final id = warehouse['id'] as int;
    final name = warehouse['name'] as String;
    final productCount = _productCounts[id] ?? 0;

    if (productCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning, color: AppColors.warning, size: 40),
          title: const Text('لا يمكن الحذف'),
          content: Text(
              'لا يمكن حذف "$name" لأنه يحتوي على $productCount منتج. قم بنقل المنتجات أولاً.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف المستودع'),
        content: Text('هل أنت متأكد من حذف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await locator<ReferenceDataRepository>().deleteWarehouse(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف "$name"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadWarehouses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredWarehouses;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'بحث في المستودعات...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppColors.textHint),
                ),
                style: theme.textTheme.bodyLarge,
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('المستودعات'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'إغلاق البحث',
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _isSearching = false;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'بحث',
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'إضافة',
              onPressed: () => _showAddSheet(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warehouse,
                        size: 72,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'لا توجد مستودعات'
                            : 'لا توجد نتائج',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_searchQuery.isEmpty)
                        FilledButton.icon(
                          onPressed: () => _showAddSheet(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('إضافة مستودع'),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.warehouse,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'إجمالي المستودعات',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  '${_warehouses.length}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_productCounts.values.fold<int>(0, (sum, c) => sum + c)} منتج',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final warehouse = filtered[index];
                          return _WarehouseCard(
                            warehouse: warehouse,
                            productCount:
                                _productCounts[warehouse['id'] as int] ?? 0,
                            isDark: isDark,
                            onTap: () => _showAddSheet(existing: warehouse),
                            onDelete: () => _deleteWarehouse(warehouse),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        tooltip: 'إضافة مستودع',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      // إضافة أزرار التحويل المخزني والجرد
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppConstants.stockTransfer),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('تحويل مخزني'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppConstants.stocktaking),
                  icon: const Icon(Icons.fact_check, size: 18),
                  label: const Text('جرد المخازن'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondaryDark,
                    side: BorderSide(color: AppColors.secondaryDark),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.warehouse,
    required this.productCount,
    required this.isDark,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> warehouse;
  final int productCount;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = warehouse['name'] as String? ?? '';
    final location = warehouse['location'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warehouse,
                  color: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '$productCount',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.info,
                      ),
                    ),
                    Text(
                      'منتج',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
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
}
