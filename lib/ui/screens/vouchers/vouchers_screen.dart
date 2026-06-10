import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/voucher_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import 'create_receipt_payment_voucher_screen.dart';
import 'create_general_entry_screen.dart';
import 'create_settlement_voucher_screen.dart';

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
    Tab(text: 'قيود عامة'),
    Tab(text: 'سندات التسوية'),
    Tab(text: 'السندات المزدوجة'),
  ];

  static const _tabTypes = <String?>[
    null,
    'receipt',
    'payment',
    'settlement', // القيود العامة تُحفظ كنوع settlement
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
      final vouchers = await locator<CashBoxService>().getAllVouchers();
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
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _filterVouchers() {
    final tabIndex = _tabController.index;
    final typeFilter = _tabTypes[tabIndex];
    List<Map<String, dynamic>> result = _allVouchers;

    if (typeFilter != null) {
      if (tabIndex == 3) {
        // القيود العامة: settlement vouchers without cash_box_id
        result = result.where((v) =>
          v['voucher_type'] == 'settlement' && v['cash_box_id'] == null).toList();
      } else if (tabIndex == 4) {
        // سندات التسوية: settlement vouchers with cash_box_id
        result = result.where((v) =>
          v['voucher_type'] == 'settlement' && v['cash_box_id'] != null).toList();
      } else {
        result = result.where((v) => v['voucher_type'] == typeFilter).toList();
      }
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
        return AppColors.secondary;
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
    if (!mounted) return;
    if (!confirmed) return;

    await locator<CashBoxService>().deleteVoucher(voucherId);
    if (mounted) {
      context.showSuccessSnackBar('تم حذف السند بنجاح');
      _loadData();
    }
  }

  Future<void> _showVoucherDetail(Map<String, dynamic> voucher) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final number = voucher['voucher_number'] as String? ?? '';
    final type = voucher['voucher_type'] as String? ?? 'receipt';
    final dateStr = voucher['date'] as String? ?? '';
    final formattedDate = dateStr.isNotEmpty
        ? DateFormatter.formatDateTime(DateTime.parse(dateStr))
        : '';
    final totalAmount = MoneyHelper.readMoney(voucher['total_amount']);
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
      items = await locator<CashBoxService>().getVoucherItems(voucherId);
    } catch (e) {
      debugPrint('VouchersScreen._showVoucherDetails: $e');
    }

    if (!mounted) return;

    // Get account names for items
    final voucherRepo = locator<VoucherRepository>();
    final List<Map<String, dynamic>> enrichedItems = [];
    for (final item in items) {
      final accountId = (item['account_id'] as num?)?.toInt();
      String accountName = 'غير معروف';
      if (accountId != null) {
        try {
          final acct = await voucherRepo.getAccountById(accountId);
          if (acct != null) {
            accountName = acct['name_ar'] as String? ?? accountName;
          }
        } catch (e) {
          debugPrint('VouchersScreen._showVoucherDetails.getAccountName: $e');
        }
      }
      enrichedItems.add({...item, 'account_name': accountName});
    }

    if (!mounted) return;
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
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(theme, 'التاريخ', formattedDate),
                    if (description.isNotEmpty) _buildDetailRow(theme, 'الوصف', description),
                    _buildDetailRow(theme, 'العملة', currency),
                    _buildDetailRow(theme, 'المبلغ الإجمالي', CurrencyFormatter.format(totalAmount, symbol: currencySymbol)),
                  ],
                ),
              ),
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
                      final debit = MoneyHelper.readMoney(item['debit']);
                      final credit = MoneyHelper.readMoney(item['credit']);
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

  /// عرض قائمة الإضافة المنسدلة
  void _showCreateMenu() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text('إنشاء سند جديد', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              // سند قبض
              _buildCreateOption(
                theme: theme,
                isDark: isDark,
                icon: Icons.arrow_downward,
                color: AppColors.success,
                title: 'سند قبض',
                subtitle: 'استلام نقدية من عميل/مورد/موظف',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCreateReceiptPayment(isReceipt: true);
                },
              ),
              const SizedBox(height: 8),
              // سند صرف
              _buildCreateOption(
                theme: theme,
                isDark: isDark,
                icon: Icons.arrow_upward,
                color: AppColors.error,
                title: 'سند صرف',
                subtitle: 'دفع نقدية لعميل/مورد/موظف',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCreateReceiptPayment(isReceipt: false);
                },
              ),
              const SizedBox(height: 8),
              // قيد عام
              _buildCreateOption(
                theme: theme,
                isDark: isDark,
                icon: Icons.swap_horiz,
                color: AppColors.accentPurple,
                title: 'قيد عام',
                subtitle: 'تحويل بين حسابات (من حساب إلى حساب)',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCreateGeneralEntry();
                },
              ),
              const SizedBox(height: 8),
              // سند تسوية
              _buildCreateOption(
                theme: theme,
                isDark: isDark,
                icon: Icons.balance,
                color: AppColors.info,
                title: 'سند تسوية',
                subtitle: 'تسوية بين حسابات شجرة المحاسبة',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCreateSettlement(isCompound: false);
                },
              ),
              const SizedBox(height: 8),
              // سند تسوية مزدوج
              _buildCreateOption(
                theme: theme,
                isDark: isDark,
                icon: Icons.compare_arrows,
                color: AppColors.secondary,
                title: 'سند تسوية مزدوج',
                subtitle: 'قيد متعدد البنود بين حسابات شجرة المحاسبة',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCreateSettlement(isCompound: true);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateOption({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.arrow_back_ios, size: 16, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToCreateReceiptPayment({required bool isReceipt}) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateReceiptPaymentVoucherScreen(isReceipt: isReceipt),
      ),
    );
    // Always refresh list when returning from create screen
    if (mounted) _loadData();
  }

  Future<void> _navigateToCreateGeneralEntry() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateGeneralEntryScreen(),
      ),
    );
    // Always refresh list when returning from create screen
    if (mounted) _loadData();
  }

  Future<void> _navigateToCreateSettlement({required bool isCompound}) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateSettlementVoucherScreen(isCompound: isCompound),
      ),
    );
    // Always refresh list when returning from create screen
    if (mounted) _loadData();
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
          title: const Text('السندات والقيود'),
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
                  _buildSearchBar(theme, isDark),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateMenu,
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('إضافة سند', style: TextStyle(color: Colors.white)),
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
          hintText: 'بحث في السندات والقيود...',
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
              width: 80, height: 80,
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
    final dateStr = voucher['date'] as String? ?? '';
    final formattedDate = dateStr.isNotEmpty
        ? DateFormatter.formatDateTime(DateTime.parse(dateStr))
        : '';
    final totalAmount = MoneyHelper.readMoney(voucher['total_amount']);
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
                width: 44, height: 44,
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
                        Text(number, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(typeAr, style: theme.textTheme.labelSmall?.copyWith(
                            color: typeColor, fontWeight: FontWeight.w700,
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 12, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(formattedDate, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        if (description.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(description,
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
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
