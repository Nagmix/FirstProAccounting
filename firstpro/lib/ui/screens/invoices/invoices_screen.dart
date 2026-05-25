import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';
import 'sales_invoices_screen.dart';
import 'purchase_invoices_screen.dart';

/// Invoices list screen – displays all invoices with tab-based filtering,
/// search, date-range filtering, payment-status filtering, and invoice-type filtering.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Filter state ────────────────────────────────────────────────
  String _paymentStatusFilter = 'الكل';
  String _paymentMethodFilter = 'الكل';
  String _invoiceTypeFilter = 'الكل'; // all, sale, purchase, pos
  DateTimeRange? _dateRange;

  // ── Search ──────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  bool _isSearching = false;

  // ── Data from DB ────────────────────────────────────────────────
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
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper();
    final maps = await db.getAllInvoices();
    setState(() {
      _invoices = maps;
      _isLoading = false;
    });
  }

  // ── Statistics ──────────────────────────────────────────────────
  double get _totalSales => _invoices
      .where((i) => i['type'] == 'sale' || i['type'] == 'sale_return')
      .fold(0.0, (sum, i) => sum + ((i['total'] as num?)?.toDouble() ?? 0.0));
  double get _totalPurchases => _invoices
      .where((i) => i['type'] == 'purchase' || i['type'] == 'purchase_return')
      .fold(0.0, (sum, i) => sum + ((i['total'] as num?)?.toDouble() ?? 0.0));
  double get _totalPOS => _invoices
      .where((i) => i['type'] == 'pos')
      .fold(0.0, (sum, i) => sum + ((i['total'] as num?)?.toDouble() ?? 0.0));

  // ═══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════
  //  FILTERING
  // ═══════════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> get _filteredInvoices {
    var result = _invoices;

    // Tab filter (5 tabs: all, sale, purchase, pos, returns)
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

    // Invoice type filter
    if (_invoiceTypeFilter != 'الكل') {
      final typeMap = {'مبيعات': 'sale', 'مشتريات': 'purchase', 'نقطة بيع': 'pos'};
      final typeVal = typeMap[_invoiceTypeFilter];
      if (typeVal != null) result = result.where((i) => i['type'] == typeVal).toList();
    }

    // Payment status filter (now includes 'partial')
    if (_paymentStatusFilter != 'الكل') {
      final statusMap = {'مدفوع': 'paid', 'غير مدفوع': 'unpaid', 'مدفوع جزئياً': 'partial', 'معلق': 'pending'};
      final status = statusMap[_paymentStatusFilter];
      if (status != null) result = result.where((i) => i['status'] == status).toList();
    }

    // Payment mechanism filter
    if (_paymentMethodFilter != 'الكل') {
      final methodMap = {'نقداً': 'cash', 'آجل': 'credit'};
      final method = methodMap[_paymentMethodFilter];
      if (method != null) result = result.where((i) => i['payment_mechanism'] == method).toList();
    }

    // Date range filter
    if (_dateRange != null) {
      result = result.where((i) {
        final createdAt = DateTime.tryParse(i['created_at'] as String? ?? '');
        if (createdAt == null) return false;
        return !createdAt.isBefore(_dateRange!.start) && !createdAt.isAfter(_dateRange!.end);
      }).toList();
    }

    // Search
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

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
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
                  // Statistics summary
                  _buildStatisticsSummary(),
                  // Tab bar
                  Container(
                    color: AppColors.primary,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: AppColors.secondary,
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'الكل'),
                        Tab(text: 'مبيعات'),
                        Tab(text: 'مشتريات'),
                        Tab(text: 'نقطة بيع'),
                        Tab(text: 'مرتجعات'),
                      ],
                    ),
                  ),
                  // Filter bar
                  _buildFilterBar(),
                  // Invoice list
                  Expanded(
                    child: _filteredInvoices.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadInvoices,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                return _ImprovedInvoiceCard(
                                  invoiceData: _filteredInvoices[index],
                                  onTap: () => _navigateToDetail(_filteredInvoices[index]),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddInvoiceMenu,
          icon: const Icon(Icons.add),
          label: const Text('فاتورة جديدة'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // ── Statistics summary ───────────────────────────────────────────
  Widget _buildStatisticsSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _MiniStatCard(
              label: 'المبيعات',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalSales),
              color: AppColors.success,
              icon: Icons.trending_up,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniStatCard(
              label: 'المشتريات',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalPurchases),
              color: AppColors.info,
              icon: Icons.shopping_cart,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniStatCard(
              label: 'نقطة البيع',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalPOS),
              color: AppColors.primary,
              icon: Icons.storefront,
            ),
          ),
        ],
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────
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
              onChanged: (_) => setState(() {}),
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

  // ── Filter bar ───────────────────────────────────────────────────
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.surfaceColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: 'النوع: $_invoiceTypeFilter',
              icon: Icons.receipt,
              items: const ['الكل', 'مبيعات', 'مشتريات', 'نقطة بيع'],
              selected: _invoiceTypeFilter,
              onChanged: (v) => setState(() => _invoiceTypeFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'حالة الدفع: $_paymentStatusFilter',
              icon: Icons.payments,
              items: const ['الكل', 'مدفوع', 'غير مدفوع', 'مدفوع جزئياً', 'معلق'],
              selected: _paymentStatusFilter,
              onChanged: (v) => setState(() => _paymentStatusFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'آلية الدفع: $_paymentMethodFilter',
              icon: Icons.credit_card,
              items: const ['الكل', 'نقداً', 'آجل'],
              selected: _paymentMethodFilter,
              onChanged: (v) => setState(() => _paymentMethodFilter = v),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                _dateRange != null
                    ? '${DateFormatter.formatDate(_dateRange!.start)} – ${DateFormatter.formatDate(_dateRange!.end)}'
                    : 'من تاريخ - إلى تاريخ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onPressed: _pickDateRange,
            ),
            if (_dateRange != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _dateRange = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(label.split(':').first),
            children: items.map((item) => SimpleDialogOption(
              onPressed: () {
                onChanged(item);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  if (item == selected) const Icon(Icons.check, size: 18, color: AppColors.primary),
                  if (item == selected) const SizedBox(width: 8),
                  Text(item),
                ],
              ),
            )).toList(),
          ),
        );
      },
    );
  }

  // ── Empty state ──────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لا توجد فواتير', style: context.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('أضف فاتورة جديدة بالضغط على الزر أدناه', style: context.textTheme.bodySmall),
        ],
      ),
    );
  }

  // ── Navigate to detail ───────────────────────────────────────────
  void _navigateToDetail(Map<String, dynamic> invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(invoiceId: invoice['id'] as String),
      ),
    ).then((_) => _loadInvoices());
  }

  // ── Add invoice popup menu ───────────────────────────────────────
  void _showAddInvoiceMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt, color: AppColors.success),
              title: const Text('فاتورة بيع جديدة'),
              subtitle: const Text('إنشاء فاتورة مبيعات'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesInvoicesScreen()),
                ).then((_) => _loadInvoices());
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart, color: AppColors.info),
              title: const Text('فاتورة شراء جديدة'),
              subtitle: const Text('إنشاء فاتورة مشتريات'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PurchaseInvoicesScreen()),
                ).then((_) => _loadInvoices());
              },
            ),
            ListTile(
              leading: Icon(Icons.add_circle, color: AppColors.primary),
              title: const Text('فاتورة مبيعات مباشرة'),
              subtitle: const Text('إنشاء فاتورة مبيعات مباشرة'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateInvoiceScreen(invoiceType: AppConstants.saleInvoice)),
                ).then((_) => _loadInvoices());
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter dialog ────────────────────────────────────────────────
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تصفية الفواتير', style: context.textTheme.titleLarge),
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
                  selected: _paymentMethodFilter == s,
                  onSelected: (_) => setState(() => _paymentMethodFilter = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Date range picker ────────────────────────────────────────────
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
//  MINI STAT CARD
// ═══════════════════════════════════════════════════════════════════════════
class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7)), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  IMPROVED INVOICE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _ImprovedInvoiceCard extends StatelessWidget {
  const _ImprovedInvoiceCard({required this.invoiceData, this.onTap});

  final Map<String, dynamic> invoiceData;
  final VoidCallback? onTap;

  String _displayId(String? id, String? type) {
    if (type == 'pos') return 'فاتورة نقطة بيع';
    if (id == null || id.isEmpty) return '—';
    if (id.length > 12) return '...${id.substring(id.length - 8)}';
    return id;
  }

  String _typeAr(String? type) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final type = invoiceData['type'] as String? ?? '';
    final isPosted = (invoiceData['is_posted'] as int?) == 1;
    final cashierName = invoiceData['cashier_name'] as String?;
    final status = invoiceData['status'] as String? ?? 'pending';
    final remaining = (invoiceData['remaining'] as num?)?.toDouble() ?? 0.0;
    final total = (invoiceData['total'] as num?)?.toDouble() ?? 0.0;
    final paymentMechanism = invoiceData['payment_mechanism'] as String? ?? 'cash';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Type icon
              _buildTypeIcon(),
              const SizedBox(width: 14),

              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _displayId(invoiceData['id'] as String?, type),
                            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildTypeBadge(isDark),
                        const SizedBox(width: 4),
                        _buildPaymentMethodBadge(isDark),
                        if (!isPosted) ...[
                          const SizedBox(width: 4),
                          _buildPendingBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoiceData['entity_name'] as String? ?? 'بدون عميل',
                      style: context.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (cashierName != null && cashierName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            cashierName,
                            style: context.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.formatDateTime(DateTime.tryParse(invoiceData['created_at'] as String? ?? '') ?? DateTime.now()),
                      style: context.textTheme.bodySmall?.copyWith(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                    ),
                    // Show remaining amount for partial/unpaid
                    if (remaining > 0.005) ...[
                      const SizedBox(height: 4),
                      Text(
                        'المتبقي: ${CurrencyFormatter.format(remaining)}',
                        style: context.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),

              // Amount + status + print
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(total),
                    style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusChip(),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.print, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      // TODO: print invoice
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon() {
    final type = invoiceData['type'] as String? ?? '';
    final isReturn = (invoiceData['is_return'] as int?) == 1;
    final (icon, color) = switch (type) {
      'sale' => isReturn ? (Icons.refresh, AppColors.warning) : (Icons.receipt, AppColors.success),
      'purchase' => isReturn ? (Icons.refresh, AppColors.warning) : (Icons.shopping_cart, AppColors.info),
      'pos' => (Icons.storefront, AppColors.primary),
      'sale_return' => (Icons.refresh, AppColors.warning),
      'purchase_return' => (Icons.refresh, AppColors.warning),
      'return' => (Icons.refresh, AppColors.warning),
      _ => (Icons.receipt, AppColors.textSecondary),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildTypeBadge(bool isDark) {
    final type = invoiceData['type'] as String? ?? '';
    final label = _typeAr(type);
    final bgColor = switch (type) {
      'sale' => AppColors.successLight,
      'purchase' => AppColors.infoLight,
      'pos' => AppColors.primary.withValues(alpha: 0.1),
      _ => AppColors.surfaceVariant,
    };
    final fgColor = switch (type) {
      'sale' => AppColors.success,
      'purchase' => AppColors.info,
      'pos' => AppColors.primary,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fgColor), overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildPaymentMethodBadge(bool isDark) {
    final paymentMechanism = invoiceData['payment_mechanism'] as String? ?? 'cash';
    final methodAr = paymentMechanism == 'cash' ? 'نقداً' : 'آجل';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(methodAr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildPendingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange, width: 0.5),
      ),
      child: const Text('معلق', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.orange)),
    );
  }

  Widget _buildStatusChip() {
    final status = invoiceData['status'] as String? ?? 'pending';
    final (label, bgColor, fgColor) = switch (status) {
      'paid' => ('مدفوع', AppColors.successLight, AppColors.success),
      'unpaid' => ('غير مدفوع', AppColors.errorLight, AppColors.error),
      'pending' => ('معلق', AppColors.warningLight, AppColors.warning),
      'partial' => ('مدفوع جزئياً', AppColors.infoLight, AppColors.info),
      _ => (status, AppColors.surfaceVariant, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
    );
  }
}
