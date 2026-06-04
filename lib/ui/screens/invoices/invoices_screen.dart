import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/invoice_repository.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';

/// Invoices list screen – displays all invoices with tab-based filtering,
/// search, date-range filtering, payment-status filtering.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String _paymentStatusFilter = 'الكل';
  String _paymentMechanismFilter = 'الكل';
  String _invoiceTypeFilter = 'الكل';
  DateTimeRange? _dateRange;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadInvoices();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    try {
      final maps = await locator<InvoiceRepository>().getAllInvoices();
      if (mounted) {
        setState(() {
          _invoices = maps;
          _isLoading = false;
        });
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

  double get _totalSales => _invoices
      .where((i) => i['type'] == 'sale' || i['type'] == 'sale_return')
      .fold(0.0, (sum, i) {
        final total = MoneyHelper.readMoney(i['total']);
        final isReturn = (i['is_return'] as int?) == 1 || (i['type'] as String? ?? '') == 'sale_return';
        return sum + (isReturn ? -total : total);
      });
  double get _totalPurchases => _invoices
      .where((i) => i['type'] == 'purchase' || i['type'] == 'purchase_return')
      .fold(0.0, (sum, i) {
        final total = MoneyHelper.readMoney(i['total']);
        final isReturn = (i['is_return'] as int?) == 1 || (i['type'] as String? ?? '') == 'purchase_return';
        return sum + (isReturn ? -total : total);
      });
  double get _totalPOS => _invoices
      .where((i) => i['type'] == 'pos')
      .fold(0.0, (sum, i) => sum + (MoneyHelper.readMoney(i['total'])));
  int get _totalCount => _invoices.length;

  String _displayInvoiceId(String? id, String? type) {
    if (type == 'pos') return 'فاتورة نقطة بيع';
    if (id == null || id.isEmpty) return '—';
    if (id.length > 12) return '...${id.substring(id.length - 8)}';
    return id;
  }

  String _invoiceTypeAr(String? type) {
    return switch (type) {
      'sale' => 'فاتورة مبيعات',
      'purchase' => 'فاتورة مشتريات',
      'pos' => 'فاتورة نقطة بيع',
      'sale_return' => 'فاتورة مرتجع مبيعات',
      'purchase_return' => 'فاتورة مرتجع مشتريات',
      'return' => 'فاتورة مرتجع',
      _ => 'فاتورة',
    };
  }

  List<Map<String, dynamic>> get _filteredInvoices {
    var result = _invoices;

    switch (_tabController.index) {
      case 1:
        result = result.where((i) => i['type'] == AppConstants.saleInvoice || i['type'] == 'sale_return').toList();
      case 2:
        result = result.where((i) => i['type'] == AppConstants.purchaseInvoice || i['type'] == 'purchase_return').toList();
      case 3:
        result = result.where((i) => i['type'] == 'pos').toList();
      case 4:
        result = result.where((i) => (i['is_return'] ?? 0) == 1).toList();
    }

    if (_invoiceTypeFilter != 'الكل') {
      final typeMap = {'مبيعات': 'sale', 'مشتريات': 'purchase', 'نقطة بيع': 'pos'};
      final typeVal = typeMap[_invoiceTypeFilter];
      if (typeVal != null) result = result.where((i) => i['type'] == typeVal).toList();
    }

    if (_paymentStatusFilter != 'الكل') {
      final statusMap = {'مدفوع': 'paid', 'غير مدفوع': 'unpaid', 'مدفوع جزئياً': 'partial', 'معلق': 'pending'};
      final status = statusMap[_paymentStatusFilter];
      if (status != null) result = result.where((i) => i['status'] == status).toList();
    }

    if (_paymentMechanismFilter != 'الكل') {
      final methodMap = {'نقداً': 'cash', 'آجل': 'credit'};
      final method = methodMap[_paymentMechanismFilter];
      if (method != null) result = result.where((i) => i['payment_mechanism'] == method).toList();
    }

    if (_dateRange != null) {
      result = result.where((i) {
        final createdAt = DateTime.tryParse(i['created_at'] as String? ?? '');
        if (createdAt == null) return false;
        return !createdAt.isBefore(_dateRange!.start) && !createdAt.isAfter(_dateRange!.end);
      }).toList();
    }

    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      result = result.where((i) {
        final id = (i['id'] as String? ?? '').toLowerCase();
        final entityName = (i['entity_name'] as String? ?? '').toLowerCase();
        final cashierName = (i['cashier_name'] as String? ?? '').toLowerCase();
        return id.contains(query) || entityName.contains(query) || cashierName.contains(query);
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildStatisticsSummary(),
                  _buildTabBar(),
                  _buildFilterBar(),
                  Expanded(
                    child: _filteredInvoices.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadInvoices,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                return _InvoiceCard(
                                  invoiceData: _filteredInvoices[index],
                                  displayInvoiceId: _displayInvoiceId,
                                  invoiceTypeAr: _invoiceTypeAr,
                                  onTap: () => _navigateToDetail(_filteredInvoices[index]),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddInvoiceMenu,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildStatisticsSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniStatItem(
              label: 'المبيعات',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalSales),
              color: AppColors.success,
              icon: Icons.trending_up,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.divider),
          Expanded(
            child: _MiniStatItem(
              label: 'المشتريات',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalPurchases),
              color: AppColors.info,
              icon: Icons.shopping_cart,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.divider),
          Expanded(
            child: _MiniStatItem(
              label: 'نقطة البيع',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalPOS),
              color: AppColors.primary,
              icon: Icons.storefront,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.divider),
          Expanded(
            child: _MiniStatItem(
              label: 'الإجمالي',
              value: '$_totalCount',
              color: AppColors.accentOrange,
              icon: Icons.receipt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.all(4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: const [
          Tab(text: 'الكل'),
          Tab(text: 'مبيعات'),
          Tab(text: 'مشتريات'),
          Tab(text: 'نقطة بيع'),
          Tab(text: 'مرتجعات'),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'بحث في الفواتير...',
                hintStyle: TextStyle(color: Colors.white60),
                border: InputBorder.none,
              ),
              onChanged: (_) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() {});
                });
              },
            )
          : const Text('الفواتير'),
      actions: [
        IconButton(
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) _searchController.clear();
            });
          },
          icon: Icon(_isSearching ? Icons.close : Icons.search),
        ),
        IconButton(
          onPressed: _showFilterDialog,
          icon: const Icon(Icons.filter_list),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final hasActiveFilters = _paymentStatusFilter != 'الكل' || _paymentMechanismFilter != 'الكل' || _invoiceTypeFilter != 'الكل' || _dateRange != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: _invoiceTypeFilter == 'الكل' ? 'النوع' : _invoiceTypeFilter,
              icon: Icons.receipt,
              items: const ['الكل', 'مبيعات', 'مشتريات', 'نقطة بيع'],
              selected: _invoiceTypeFilter,
              onChanged: (v) => setState(() => _invoiceTypeFilter = v),
              isActive: _invoiceTypeFilter != 'الكل',
            ),
            const SizedBox(width: 6),
            _buildFilterChip(
              label: _paymentStatusFilter == 'الكل' ? 'حالة الدفع' : _paymentStatusFilter,
              icon: Icons.payments,
              items: const ['الكل', 'مدفوع', 'غير مدفوع', 'مدفوع جزئياً', 'معلق'],
              selected: _paymentStatusFilter,
              onChanged: (v) => setState(() => _paymentStatusFilter = v),
              isActive: _paymentStatusFilter != 'الكل',
            ),
            const SizedBox(width: 6),
            _buildFilterChip(
              label: _paymentMechanismFilter == 'الكل' ? 'آلية الدفع' : _paymentMechanismFilter,
              icon: Icons.credit_card,
              items: const ['الكل', 'نقداً', 'آجل'],
              selected: _paymentMechanismFilter,
              onChanged: (v) => setState(() => _paymentMechanismFilter = v),
              isActive: _paymentMechanismFilter != 'الكل',
            ),
            const SizedBox(width: 6),
            ActionChip(
              avatar: Icon(Icons.calendar_month, size: 16, color: _dateRange != null ? AppColors.primary : null),
              label: Text(
                _dateRange != null
                    ? '${DateFormatter.formatDate(_dateRange!.start)} – ${DateFormatter.formatDate(_dateRange!.end)}'
                    : 'الفترة',
                style: TextStyle(fontSize: 12, color: _dateRange != null ? AppColors.primary : null),
              ),
              side: _dateRange != null ? BorderSide(color: AppColors.primary) : null,
              onPressed: _pickDateRange,
            ),
            if (_dateRange != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: () => setState(() => _dateRange = null),
                child: const Icon(Icons.close, size: 16, color: AppColors.textHint),
              ),
            ],
            if (hasActiveFilters) ...[
              const SizedBox(width: 6),
              ActionChip(
                label: const Text('مسح الكل', style: TextStyle(fontSize: 11, color: AppColors.error)),
                onPressed: () => setState(() {
                  _paymentStatusFilter = 'الكل';
                  _paymentMechanismFilter = 'الكل';
                  _invoiceTypeFilter = 'الكل';
                  _dateRange = null;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required List<String> items,
    required String selected,
    required ValueChanged<String> onChanged,
    bool isActive = false,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: isActive ? AppColors.primary : null),
      label: Text(label, style: TextStyle(fontSize: 12, color: isActive ? AppColors.primary : null, fontWeight: isActive ? FontWeight.w600 : null)),
      side: isActive ? BorderSide(color: AppColors.primary) : null,
      onPressed: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                ...items.map((item) => ListTile(
                  title: Text(item, style: TextStyle(fontWeight: item == selected ? FontWeight.w700 : FontWeight.w400)),
                  trailing: item == selected ? const Icon(Icons.check, color: AppColors.primary, size: 20) : null,
                  onTap: () {
                    onChanged(item);
                    Navigator.pop(ctx);
                  },
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('لا توجد فواتير', style: context.textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('أضف فاتورة جديدة بالضغط على الزر +', style: context.textTheme.bodySmall),
        ],
      ),
    );
  }

  void _navigateToDetail(Map<String, dynamic> invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(invoiceId: invoice['id'] as String),
      ),
    ).then((_) => _loadInvoices());
  }

  // ── Add invoice menu – only 2 options: sales or purchase ────────
  void _showAddInvoiceMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('إنشاء فاتورة جديدة', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Sales invoice option
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateInvoiceScreen(invoiceType: AppConstants.saleInvoice)),
                  ).then((_) => _loadInvoices());
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long, color: AppColors.success, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('فاتورة مبيعات', style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                            const SizedBox(height: 2),
                            Text('إنشاء فاتورة مبيعات جديدة', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.success),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Purchase invoice option
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateInvoiceScreen(invoiceType: AppConstants.purchaseInvoice)),
                  ).then((_) => _loadInvoices());
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.info.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shopping_cart, color: AppColors.info, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('فاتورة مشتريات', style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.info)),
                            const SizedBox(height: 2),
                            Text('إنشاء فاتورة مشتريات جديدة', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.info),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter dialog ────────────────────────────────────────────────
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('تصفية الفواتير', style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Text('نوع الفاتورة', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['الكل', 'مبيعات', 'مشتريات', 'نقطة بيع'].map((s) {
                return ChoiceChip(
                  label: Text(s),
                  selected: _invoiceTypeFilter == s,
                  onSelected: (_) => setState(() => _invoiceTypeFilter = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('حالة الدفع', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['الكل', 'مدفوع', 'غير مدفوع', 'مدفوع جزئياً', 'معلق'].map((s) {
                return ChoiceChip(
                  label: Text(s),
                  selected: _paymentStatusFilter == s,
                  onSelected: (_) => setState(() => _paymentStatusFilter = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('آلية الدفع', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['الكل', 'نقداً', 'آجل'].map((s) {
                return ChoiceChip(
                  label: Text(s),
                  selected: _paymentMechanismFilter == s,
                  onSelected: (_) => setState(() => _paymentMechanismFilter = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MINI STAT ITEM
// ═══════════════════════════════════════════════════════════════════════════
class _MiniStatItem extends StatelessWidget {
  const _MiniStatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7)), textAlign: TextAlign.center),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INVOICE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoiceData,
    required this.displayInvoiceId,
    required this.invoiceTypeAr,
    this.onTap,
  });

  final Map<String, dynamic> invoiceData;
  final String Function(String?, String?) displayInvoiceId;
  final String Function(String?) invoiceTypeAr;
  final VoidCallback? onTap;

  Future<void> _printInvoice(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إنشاء ملف PDF...'), duration: Duration(seconds: 1)),
      );
      final items = await locator<InvoiceRepository>().getInvoiceItems(invoiceData['id'] as String);
      await InvoicePdfGenerator.printInvoice(invoiceData, items);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final type = invoiceData['type'] as String? ?? '';
    final isReturn = (invoiceData['is_return'] as int?) == 1;
    final status = invoiceData['status'] as String? ?? 'pending';
    final remaining = MoneyHelper.readMoney(invoiceData['remaining']);
    final total = MoneyHelper.readMoney(invoiceData['total']);
    final paidAmount = MoneyHelper.readMoney(invoiceData['paid_amount']);
    final paymentMechanism = invoiceData['payment_mechanism'] as String? ?? 'cash';
    final currency = invoiceData['currency'] as String? ?? 'YER';

    // Type-specific colors
    final typeColor = switch (type) {
      'sale' || 'sale_return' => AppColors.success,
      'purchase' || 'purchase_return' => AppColors.info,
      'pos' => AppColors.primary,
      _ => AppColors.textSecondary,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReturn ? AppColors.warning.withOpacity(0.3) : AppColors.border.withOpacity(0.5),
          width: isReturn ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  _buildTypeIcon(typeColor, type, isReturn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayInvoiceId(invoiceData['id'] as String?, type),
                                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildTypeBadge(typeColor, type),
                            const SizedBox(width: 4),
                            _buildPaymentBadge(isDark, paymentMechanism),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoiceData['entity_name'] as String? ?? '—',
                          style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(total),
                        style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: typeColor),
                      ),
                      if (currency != 'YER')
                        Text(currency, style: context.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontSize: 9)),
                      GestureDetector(
                        onTap: () => _printInvoice(context),
                        child: Icon(Icons.print, size: 16, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      DateFormatter.formatDateTime(DateTime.tryParse(invoiceData['created_at'] as String? ?? '') ?? DateTime.now()),
                      style: context.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontSize: 10),
                    ),
                    const Spacer(),
                    _buildStatusChip(status),
                    if (remaining > 0.005) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'متبقي ${CurrencyFormatter.format(remaining)}',
                          style: context.textTheme.labelSmall?.copyWith(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ] else if (status == 'paid' && paidAmount > 0) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle, size: 12, color: AppColors.success),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(Color color, String type, bool isReturn) {
    final icon = switch (type) {
      'sale' => isReturn ? Icons.undo : Icons.receipt_long,
      'purchase' => isReturn ? Icons.undo : Icons.shopping_cart,
      'pos' => Icons.storefront,
      'sale_return' => Icons.undo,
      'purchase_return' => Icons.undo,
      _ => Icons.receipt,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildTypeBadge(Color color, String type) {
    final label = invoiceTypeAr(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildPaymentBadge(bool isDark, String paymentMechanism) {
    final isCash = paymentMechanism == 'cash';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: (isCash ? AppColors.success : AppColors.accentOrange).withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isCash ? 'نقداً' : 'آجل',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isCash ? AppColors.success : AppColors.accentOrange),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final (label, bgColor, fgColor) = switch (status) {
      'paid' => ('مدفوع', AppColors.successLight, AppColors.success),
      'unpaid' => ('غير مدفوع', AppColors.errorLight, AppColors.error),
      'pending' => ('معلق', AppColors.warningLight, AppColors.warning),
      'partial' => ('مدفوع جزئياً', AppColors.infoLight, AppColors.info),
      _ => (status, AppColors.surfaceVariant, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fgColor)),
    );
  }
}
