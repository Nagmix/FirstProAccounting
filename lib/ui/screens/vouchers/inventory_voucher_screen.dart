import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/stock_service.dart';
import 'create_inventory_voucher_screen.dart';

class InventoryVoucherScreen extends StatefulWidget {
  const InventoryVoucherScreen({super.key});

  @override
  State<InventoryVoucherScreen> createState() => _InventoryVoucherScreenState();
}

class _InventoryVoucherScreenState extends State<InventoryVoucherScreen> {
  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _filteredVouchers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  DateTime? _dateFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final vouchers = await locator<StockService>().getInventoryVouchers(searchQuery: _searchQuery.isEmpty ? null : _searchQuery);
      if (mounted) {
        setState(() {
          _vouchers = vouchers;
          _isLoading = false;
        });
        _filterVouchers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _filterVouchers() {
    List<Map<String, dynamic>> result = _vouchers;
    if (_dateFilter != null) {
      final filterStr = _dateFilter!.toIso8601String().substring(0, 10);
      result = result.where((v) => (v['date'] as String? ?? '').startsWith(filterStr)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((v) {
        final number = (v['voucher_number'] as String?) ?? '';
        final desc = (v['description'] as String?) ?? '';
        final warehouse = (v['warehouse_name'] as String?) ?? '';
        return number.toLowerCase().contains(query) ||
            desc.toLowerCase().contains(query) ||
            warehouse.toLowerCase().contains(query);
      }).toList();
    }
    setState(() {
      _filteredVouchers = result;
    });
  }

  Future<void> _navigateToCreate() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateInventoryVoucherScreen()),
    );
    // Always refresh list when returning from create screen
    if (mounted) _loadData();
  }

  Future<void> _navigateToDetail(int voucherId) async {
    final details = await locator<StockService>().getInventoryVoucherDetails(voucherId);
    if (details != null && mounted) {
      _showVoucherDetail(details);
    }
  }

  void _showVoucherDetail(Map<String, dynamic> details) {
    final theme = Theme.of(context);
    final items = details['items'] as List<Map<String, dynamic>>? ?? [];
    final currency = details['currency'] as String? ?? 'YER';

    String currencySymbol;
    switch (currency) {
      case 'SAR':
        currencySymbol = 'ر.س';
        break;
      case 'USD':
        currencySymbol = r'$';
        break;
      default:
        currencySymbol = 'ر.ي';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('تفاصيل سند الجرد', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(theme, 'رقم السند', details['voucher_number'] as String? ?? ''),
              _buildDetailRow(theme, 'التاريخ', details['date'] as String? ?? ''),
              _buildDetailRow(theme, 'المخزن', details['warehouse_name'] as String? ?? 'غير محدد'),
              _buildDetailRow(theme, 'الوصف', details['description'] as String? ?? ''),
              _buildDetailRow(theme, 'القيمة الإجمالية', CurrencyFormatter.format(MoneyHelper.readMoney(details['total_value']), symbol: currencySymbol)),
              const Divider(height: 24),
              Text('البنود', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['product_name'] as String? ?? 'منتج غير معروف',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('الكمية النظامية: ', style: theme.textTheme.bodySmall),
                                Text('${item['system_quantity']}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 16),
                                Text('الكمية الفعلية: ', style: theme.textTheme.bodySmall),
                                Text('${item['actual_quantity']}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Row(
                              children: [
                                Text('الفرق: ', style: theme.textTheme.bodySmall),
                                Text(
                                  '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(2)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: difference > 0 ? AppColors.success : AppColors.error,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text('القيمة: ', style: theme.textTheme.bodySmall),
                                Text(
                                  CurrencyFormatter.format(MoneyHelper.readMoney(item['total_value']), symbol: currencySymbol),
                                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سندات الجرد'),
          actions: [
            if (_dateFilter != null)
              IconButton(
                icon: const Icon(Icons.calendar_today, color: AppColors.primary),
                tooltip: 'مسح فلتر التاريخ',
                onPressed: () {
                  setState(() => _dateFilter = null);
                  _filterVouchers();
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () {
                setState(() => _isLoading = true);
                _loadData();
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchBar(theme, isDark),
                  if (_dateFilter != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.filter_alt, size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text('تصفية: ${_dateFilter!.year}-${_dateFilter!.month.toString().padLeft(2, '0')}-${_dateFilter!.day.toString().padLeft(2, '0')}',
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() => _dateFilter = null);
                              _filterVouchers();
                            },
                            child: const Text('مسح', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _filteredVouchers.isEmpty
                        ? _buildEmptyState(theme)
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              padding: EdgeInsets.only(bottom: 80 + MediaQuery.of(context).padding.bottom),
                              itemCount: _filteredVouchers.length,
                              itemBuilder: (context, index) =>
                                  _buildVoucherCard(_filteredVouchers[index], theme, isDark),
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _navigateToCreate,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        onChanged: (value) {
          _searchQuery = value;
          _filterVouchers();
        },
        decoration: InputDecoration(
          hintText: 'بحث في سندات الجرد...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchQuery = '';
                    _filterVouchers();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.calendar_today, size: 18),
                tooltip: 'تصفية بالتاريخ',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dateFilter ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) {
                    setState(() => _dateFilter = picked);
                    _filterVouchers();
                  }
                },
              ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.inventory, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('لا توجد سندات جرد', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('أضف سند جرد جديد بالضغط على زر الإضافة', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherCard(Map<String, dynamic> voucher, ThemeData theme, bool isDark) {
    final number = voucher['voucher_number'] as String? ?? '';
    final date = voucher['date'] as String? ?? '';
    final totalValue = MoneyHelper.readMoney(voucher['total_value']);
    final currency = voucher['currency'] as String? ?? 'YER';
    final warehouseName = voucher['warehouse_name'] as String? ?? '';
    final status = voucher['status'] as String? ?? 'approved';
    final description = voucher['description'] as String? ?? '';
    final voucherId = (voucher['id'] as num?)?.toInt() ?? 0;

    String currencySymbol;
    switch (currency) {
      case 'SAR':
        currencySymbol = 'ر.س';
        break;
      case 'USD':
        currencySymbol = r'$';
        break;
      default:
        currencySymbol = 'ر.ي';
    }

    Color statusColor;
    String statusAr;
    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        statusAr = 'معتمد';
        break;
      case 'draft':
        statusColor = AppColors.warning;
        statusAr = 'مسودة';
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        statusAr = 'ملغي';
        break;
      default:
        statusColor = AppColors.primary;
        statusAr = status;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(voucherId),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.brown.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory, color: Colors.brown, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(number, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(statusAr, style: theme.textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(date, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        if (warehouseName.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.warehouse, size: 12, color: AppColors.textHint),
                          const SizedBox(width: 4),
                          Expanded(child: Text(warehouseName, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary), overflow: TextOverflow.ellipsis, maxLines: 1)),
                        ],
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyFormatter.format(totalValue, symbol: currencySymbol),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_back_ios, size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
