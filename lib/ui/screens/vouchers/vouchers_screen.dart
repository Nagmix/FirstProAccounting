import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/datasources/database_helper.dart';
import 'create_voucher_screen.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allVouchers = [];
  List<Map<String, dynamic>> _filteredVouchers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

  static const _tabs = [
    Tab(text: 'الكل'),
    Tab(text: 'سندات القبض'),
    Tab(text: 'سندات الصرف'),
    Tab(text: 'سندات التسوية'),
    Tab(text: 'السندات المزدوجة'),
  ];

  static const _tabTypes = <String?>[
    null,
    'receipt',
    'payment',
    'settlement',
    'compound',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _filterVouchers();
    }
  }

  Future<void> _loadData() async {
    try {
      final db = DatabaseHelper();
      final vouchers = await db.getAllVouchers();
      if (mounted) {
        setState(() {
          _allVouchers = vouchers;
          _isLoading = false;
        });
        _filterVouchers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _filterVouchers() {
    final typeFilter = _tabTypes[_tabController.index];
    List<Map<String, dynamic>> result = _allVouchers;

    if (typeFilter != null) {
      result = result.where((v) => v['voucher_type'] == typeFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((v) {
        final number = (v['voucher_number'] as String?) ?? '';
        final description = (v['description'] as String?) ?? '';
        final type = _getVoucherTypeAr(v['voucher_type'] as String? ?? '');
        return number.toLowerCase().contains(query) ||
            description.toLowerCase().contains(query) ||
            type.contains(query);
      }).toList();
    }

    setState(() {
      _filteredVouchers = result;
    });
  }

  String _getVoucherTypeAr(String type) {
    switch (type) {
      case 'receipt':
        return 'سند قبض';
      case 'payment':
        return 'سند صرف';
      case 'settlement':
        return 'سند تسوية';
      case 'compound':
        return 'سند مزدوج';
      case 'inventory':
        return 'سند جرد';
      default:
        return type;
    }
  }

  Color _getVoucherTypeColor(String type) {
    switch (type) {
      case 'receipt':
        return AppColors.success;
      case 'payment':
        return AppColors.error;
      case 'settlement':
        return AppColors.info;
      case 'compound':
        return AppColors.accentOrange;
      case 'inventory':
        return Colors.brown;
      default:
        return AppColors.primary;
    }
  }

  IconData _getVoucherTypeIcon(String type) {
    switch (type) {
      case 'receipt':
        return Icons.arrow_downward;
      case 'payment':
        return Icons.arrow_upward;
      case 'settlement':
        return Icons.swap_horiz;
      case 'compound':
        return Icons.compare_arrows;
      case 'inventory':
        return Icons.inventory;
      default:
        return Icons.receipt;
    }
  }

  Future<void> _deleteVoucher(int voucherId) async {
    final confirmed = await context.showConfirmDialog(
      title: 'حذف السند',
      message: 'هل أنت متأكد من حذف هذا السند؟ سيتم عكس القيود المحاسبية.',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;

    final db = DatabaseHelper();
    await db.deleteVoucher(voucherId);
    if (mounted) {
      context.showSuccessSnackBar('تم حذف السند بنجاح');
      _loadData();
    }
  }

  Future<void> _showVoucherDetail(Map<String, dynamic> voucher) async {
    final db = DatabaseHelper();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final number = voucher['voucher_number'] as String? ?? '';
    final type = voucher['voucher_type'] as String? ?? 'receipt';
    final date = voucher['date'] as String? ?? '';
    final totalAmount = (voucher['total_amount'] as num?)?.toDouble() ?? 0.0;
    final currency = voucher['currency'] as String? ?? 'YER';
    final description = voucher['description'] as String? ?? '';
    final voucherId = (voucher['id'] as num?)?.toInt() ?? 0;
    final typeAr = _getVoucherTypeAr(type);
    final typeColor = _getVoucherTypeColor(type);

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

    // Load voucher items from DB
    List<Map<String, dynamic>> items = [];
    try {
      items = await db.getVoucherItems(voucherId);
    } catch (_) {}

    if (!mounted) return;

    // Get account names for items
    final database = await db.database;
    final List<Map<String, dynamic>> enrichedItems = [];
    for (final item in items) {
      final accountId = (item['account_id'] as num?)?.toInt();
      String accountName = 'غير معروف';
      if (accountId != null) {
        try {
          final acct = await database.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
          if (acct.isNotEmpty) {
            accountName = acct.first['name_ar'] as String? ?? accountName;
          }
        } catch (_) {}
      }
      enrichedItems.add({...item, 'account_name': accountName});
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_getVoucherTypeIcon(type), color: typeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(number, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(typeAr, style: theme.textTheme.labelSmall?.copyWith(color: typeColor, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteVoucher(voucherId);
                    },
                    tooltip: 'حذف السند',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Details
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(theme, 'التاريخ', date),
                    if (description.isNotEmpty) _buildDetailRow(theme, 'الوصف', description),
                    _buildDetailRow(theme, 'العملة', currency),
                    _buildDetailRow(theme, 'المبلغ الإجمالي', CurrencyFormatter.format(totalAmount, symbol: currencySymbol)),
                  ],
                ),
              ),
              // Items
              if (enrichedItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.list_alt, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('بنود السند', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: enrichedItems.length,
                    itemBuilder: (context, index) {
                      final item = enrichedItems[index];
                      final acctName = item['account_name'] as String? ?? '';
                      final debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
                      final credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
                      final itemDesc = item['description'] as String? ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(acctName, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                ),
                                if (debit > 0)
                                  Text(CurrencyFormatter.format(debit, symbol: currencySymbol),
                                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                                if (credit > 0)
                                  Text(CurrencyFormatter.format(credit, symbol: currencySymbol),
                                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                              ],
                            ),
                            if (itemDesc.isNotEmpty)
                              Text(itemDesc, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Close button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _navigateToCreateVoucher({String? initialType}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateVoucherScreen(initialType: initialType),
      ),
    );
    if (result == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السندات'),
          bottom: TabBar(
            controller: _tabController,
            tabs: _tabs,
            isScrollable: true,
            labelColor: isDark ? Colors.white : AppColors.primary,
            unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabAlignment: TabAlignment.start,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // شريط البحث
                  _buildSearchBar(theme, isDark),
                  // قائمة السندات
                  Expanded(
                    child: _filteredVouchers.isEmpty
                        ? _buildEmptyState(theme)
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              padding: EdgeInsets.only(bottom: 80 + bottomPadding),
                              itemCount: _filteredVouchers.length,
                              itemBuilder: (context, index) =>
                                  _buildVoucherCard(_filteredVouchers[index], theme, isDark),
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _navigateToCreateVoucher(),
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
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            _searchQuery = value;
            _filterVouchers();
          });
        },
        decoration: InputDecoration(
          hintText: 'بحث في السندات...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchQuery = '';
                    _filterVouchers();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textHint,
          ),
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
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.receipt_long, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد سندات',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'أضف سند جديد بالضغط على زر الإضافة',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherCard(Map<String, dynamic> voucher, ThemeData theme, bool isDark) {
    final number = voucher['voucher_number'] as String? ?? '';
    final type = voucher['voucher_type'] as String? ?? 'receipt';
    final date = voucher['date'] as String? ?? '';
    final totalAmount = (voucher['total_amount'] as num?)?.toDouble() ?? 0.0;
    final currency = voucher['currency'] as String? ?? 'YER';
    final description = voucher['description'] as String? ?? '';
    final typeAr = _getVoucherTypeAr(type);
    final typeColor = _getVoucherTypeColor(type);
    final typeIcon = _getVoucherTypeIcon(type);
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.2) : AppColors.primary.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showVoucherDetail(voucher),
        onLongPress: () => _deleteVoucher(voucherId),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeIcon, color: typeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          number,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeAr,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: typeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyFormatter.format(totalAmount, symbol: currencySymbol),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: type == 'receipt' ? AppColors.success : AppColors.error,
                ),
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
