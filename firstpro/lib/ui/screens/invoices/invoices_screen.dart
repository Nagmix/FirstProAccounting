import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/invoice_model.dart';
import 'create_invoice_screen.dart';

/// Invoices list screen – displays all invoices with tab-based filtering,
/// search, date-range filtering, and payment-status filtering.
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
  DateTimeRange? _dateRange;

  // ── Search ──────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  bool _isSearching = false;

  // ── Demo data ───────────────────────────────────────────────────
  final List<Invoice> _invoices = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadDemoData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadDemoData() {
    // Demo invoices for UI preview
    _invoices.addAll([
      Invoice(
        id: 'INV-001',
        type: AppConstants.saleInvoice,
        paymentType: 'cash',
        customerId: 1,
        subtotal: 1000,
        discountAmount: 50,
        taxAmount: 142.5,
        total: 1092.5,
        paidAmount: 1092.5,
        remaining: 0,
        status: 'paid',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Invoice(
        id: 'INV-002',
        type: AppConstants.purchaseInvoice,
        paymentType: 'credit',
        supplierId: 1,
        subtotal: 3500,
        discountAmount: 0,
        taxAmount: 525,
        total: 4025,
        paidAmount: 0,
        remaining: 4025,
        status: 'unpaid',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Invoice(
        id: 'INV-003',
        type: AppConstants.saleInvoice,
        paymentType: 'bank',
        customerId: 2,
        subtotal: 750,
        discountAmount: 25,
        taxAmount: 108.75,
        total: 833.75,
        paidAmount: 400,
        remaining: 433.75,
        status: 'pending',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Invoice(
        id: 'INV-004',
        type: AppConstants.returnInvoice,
        paymentType: 'cash',
        customerId: 1,
        subtotal: 200,
        discountAmount: 0,
        taxAmount: 30,
        total: 230,
        paidAmount: 230,
        remaining: 0,
        status: 'paid',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Invoice(
        id: 'INV-005',
        type: AppConstants.saleInvoice,
        paymentType: 'check',
        customerId: 3,
        subtotal: 5200,
        discountAmount: 200,
        taxAmount: 750,
        total: 5750,
        paidAmount: 0,
        remaining: 5750,
        status: 'unpaid',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  FILTERING
  // ═══════════════════════════════════════════════════════════════════
  List<Invoice> get _filteredInvoices {
    var result = _invoices;

    // Tab filter
    switch (_tabController.index) {
      case 1:
        result = result.where((i) => i.type == AppConstants.saleInvoice).toList();
      case 2:
        result = result.where((i) => i.type == AppConstants.purchaseInvoice).toList();
      case 3:
        result = result.where((i) => i.type == AppConstants.returnInvoice).toList();
    }

    // Payment status filter
    if (_paymentStatusFilter != 'الكل') {
      final statusMap = {
        'مدفوع': 'paid',
        'غير مدفوع': 'unpaid',
        'معلق': 'pending',
      };
      final status = statusMap[_paymentStatusFilter];
      if (status != null) {
        result = result.where((i) => i.status == status).toList();
      }
    }

    // Payment method filter
    if (_paymentMethodFilter != 'الكل') {
      final methodMap = {
        'نقدي': 'cash',
        'آجل': 'credit',
        'بنك': 'bank',
        'شيك': 'check',
      };
      final method = methodMap[_paymentMethodFilter];
      if (method != null) {
        result = result.where((i) => i.paymentType == method).toList();
      }
    }

    // Date range filter
    if (_dateRange != null) {
      result = result.where((i) {
        return !i.createdAt.isBefore(_dateRange!.start) &&
            !i.createdAt.isAfter(_dateRange!.end);
      }).toList();
    }

    // Search
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      result = result.where((i) {
        return i.id.toLowerCase().contains(query);
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
        body: Column(
          children: [
            // ── Tab bar ─────────────────────────────────────────
            Container(
              color: AppColors.primary,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.secondary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'الكل'),
                  Tab(text: 'مبيعات'),
                  Tab(text: 'مشتريات'),
                  Tab(text: 'مرتجعات'),
                ],
              ),
            ),

            // ── Filter bar ──────────────────────────────────────
            _buildFilterBar(),

            // ── Invoice list ────────────────────────────────────
            Expanded(
              child: _filteredInvoices.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _filteredInvoices.length,
                      itemBuilder: (context, index) {
                        return _InvoiceCard(
                          invoice: _filteredInvoices[index],
                          onTap: () {
                            // TODO: navigate to invoice detail
                          },
                        );
                      },
                    ),
            ),
          ],
        ),

        // ── FAB ─────────────────────────────────────────────────
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
              if (!_isSearching) {
                _searchController.clear();
              }
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
            // Payment status dropdown
            _buildFilterChip(
              label: 'حالة الدفع: $_paymentStatusFilter',
              icon: Icons.payments_outlined,
              items: const ['الكل', 'مدفوع', 'غير مدفوع', 'معلق'],
              selected: _paymentStatusFilter,
              onChanged: (v) => setState(() => _paymentStatusFilter = v),
            ),
            const SizedBox(width: 8),

            // Payment method dropdown
            _buildFilterChip(
              label: 'طريقة الدفع: $_paymentMethodFilter',
              icon: Icons.credit_card,
              items: const ['الكل', 'نقدي', 'آجل', 'بنك', 'شيك'],
              selected: _paymentMethodFilter,
              onChanged: (v) => setState(() => _paymentMethodFilter = v),
            ),
            const SizedBox(width: 8),

            // Date range
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
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
            children: items
                .map((item) => SimpleDialogOption(
                      onPressed: () {
                        onChanged(item);
                        Navigator.pop(ctx);
                      },
                      child: Row(
                        children: [
                          if (item == selected)
                            const Icon(Icons.check, size: 18, color: AppColors.primary),
                          if (item == selected) const SizedBox(width: 8),
                          Text(item),
                        ],
                      ),
                    ))
                .toList(),
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
          Icon(Icons.receipt_long_outlined, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لا توجد فواتير', style: context.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'أضف فاتورة جديدة بالضغط على الزر أدناه',
            style: context.textTheme.bodySmall,
          ),
        ],
      ),
    );
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
              leading: const Icon(Icons.sell, color: AppColors.success),
              title: const Text('فاتورة بيع جديدة'),
              subtitle: const Text('إنشاء فاتورة مبيعات'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateInvoiceScreen(
                      invoiceType: AppConstants.saleInvoice,
                    ),
                  ),
                );
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
                  MaterialPageRoute(
                    builder: (_) => const CreateInvoiceScreen(
                      invoiceType: AppConstants.purchaseInvoice,
                    ),
                  ),
                );
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
            // Payment status
            Text('حالة الدفع', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['الكل', 'مدفوع', 'غير مدفوع', 'معلق'].map((s) {
                return ChoiceChip(
                  label: Text(s),
                  selected: _paymentStatusFilter == s,
                  onSelected: (_) => setState(() => _paymentStatusFilter = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Payment method
            Text('طريقة الدفع', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['الكل', 'نقدي', 'آجل', 'بنك', 'شيك'].map((s) {
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
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppColors.primary,
              ),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INVOICE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, this.onTap});

  final Invoice invoice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ── Type icon ─────────────────────────────────────
              _buildTypeIcon(),
              const SizedBox(width: 14),

              // ── Info column ───────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          invoice.id,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPaymentMethodBadge(isDark),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _entityName,
                      style: context.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.formatDateTime(invoice.createdAt),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Amount + status ───────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(invoice.total),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusChip(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Type icon ────────────────────────────────────────────────────
  Widget _buildTypeIcon() {
    final (icon, color) = switch (invoice.type) {
      AppConstants.saleInvoice => (Icons.sell, AppColors.success),
      AppConstants.purchaseInvoice => (Icons.shopping_cart_outlined, AppColors.info),
      AppConstants.returnInvoice => (Icons.undo, AppColors.warning),
      _ => (Icons.receipt_outlined, AppColors.textSecondary),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  // ── Payment method badge ─────────────────────────────────────────
  Widget _buildPaymentMethodBadge(bool isDark) {
    final methodAr = switch (invoice.paymentType) {
      'cash' => 'نقدي',
      'credit' => 'آجل',
      'bank' => 'بنك',
      'check' => 'شيك',
      'card' => 'بطاقة',
      _ => invoice.paymentType,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        methodAr,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Status chip ──────────────────────────────────────────────────
  Widget _buildStatusChip() {
    final (label, bgColor, fgColor) = switch (invoice.status) {
      'paid' => ('مدفوع', AppColors.successLight, AppColors.success),
      'unpaid' => ('غير مدفوع', AppColors.errorLight, AppColors.error),
      'pending' => ('معلق', AppColors.warningLight, AppColors.warning),
      _ => (invoice.status, AppColors.surfaceVariant, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }

  // ── Entity name helper ───────────────────────────────────────────
  String get _entityName {
    if (invoice.customerId != null) return 'عميل #${invoice.customerId}';
    if (invoice.supplierId != null) return 'مورد #${invoice.supplierId}';
    return 'بدون عميل';
  }
}
