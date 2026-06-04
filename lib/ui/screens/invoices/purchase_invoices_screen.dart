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

/// Purchase invoices listing screen – shows only purchase and purchase_return invoices.
class PurchaseInvoicesScreen extends StatefulWidget {
  const PurchaseInvoicesScreen({super.key});

  @override
  State<PurchaseInvoicesScreen> createState() => _PurchaseInvoicesScreenState();
}

class _PurchaseInvoicesScreenState extends State<PurchaseInvoicesScreen> {
  String _paymentStatusFilter = 'الكل';
  String _paymentMechanismFilter = 'الكل';
  DateTimeRange? _dateRange;

  final _searchController = TextEditingController();
  bool _isSearching = false;

  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    try {
      final allInvoices = await locator<InvoiceRepository>().getAllInvoices();
      if (mounted) {
        setState(() {
          _invoices = allInvoices.where((i) {
            final type = i['type'] as String? ?? '';
            return type == 'purchase' || type == 'purchase_return';
          }).toList();
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

  double get _totalPurchases => _invoices.fold(0.0, (sum, i) {
    final total = MoneyHelper.readMoney(i['total']);
    final isReturn = (i['is_return'] as int?) == 1 || (i['type'] as String? ?? '') == 'purchase_return';
    return sum + (isReturn ? -total : total);
  });
  double get _totalPaid => _invoices.fold(0.0, (sum, i) {
    final paid = MoneyHelper.readMoney(i['paid_amount']);
    final isReturn = (i['is_return'] as int?) == 1 || (i['type'] as String? ?? '') == 'purchase_return';
    return sum + (isReturn ? -paid : paid);
  });
  double get _totalRemaining => _invoices.fold(0.0, (sum, i) {
    final remaining = MoneyHelper.readMoney(i['remaining']);
    final isReturn = (i['is_return'] as int?) == 1 || (i['type'] as String? ?? '') == 'purchase_return';
    return sum + (isReturn ? -remaining : remaining);
  });
  int get _paidCount => _invoices.where((i) => i['status'] == 'paid').length;
  int get _unpaidCount => _invoices.where((i) => i['status'] == 'unpaid' || i['status'] == 'partial').length;

  List<Map<String, dynamic>> get _filteredInvoices {
    var result = _invoices;

    if (_paymentStatusFilter != 'الكل') {
      final statusMap = {'مدفوع': 'paid', 'غير مدفوع': 'unpaid', 'مدفوع جزئياً': 'partial'};
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
        return id.contains(query) || entityName.contains(query);
      }).toList();
    }

    return result;
  }

  String _displayInvoiceId(String? id) {
    if (id == null || id.isEmpty) return '—';
    if (id.length > 12) return '...${id.substring(id.length - 8)}';
    return id;
  }

  String _invoiceTypeAr(String? type) {
    return switch (type) {
      'purchase' => 'مشتريات',
      'purchase_return' => 'مرتجع مشتريات',
      _ => 'فاتورة',
    };
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
                  _buildStatisticsHeader(),
                  _buildFilterChips(),
                  Expanded(
                    child: _filteredInvoices.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadInvoices,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                return _PurchaseInvoiceCard(
                                  invoiceData: _filteredInvoices[index],
                                  displayInvoiceId: _displayInvoiceId,
                                  invoiceTypeAr: _invoiceTypeAr,
                                  onTap: () => _navigateToDetail(_filteredInvoices[index]),
                                  onPrint: () => _printInvoice(context, _filteredInvoices[index]),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreateInvoiceScreen(invoiceType: AppConstants.purchaseInvoice),
              ),
            ).then((_) => _loadInvoices());
          },
          icon: const Icon(Icons.add),
          label: const Text('فاتورة مشتريات'),
          backgroundColor: AppColors.accentOrange,
          foregroundColor: Colors.white,
        ),
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
                hintText: 'بحث في فواتير المشتريات...',
                hintStyle: TextStyle(color: Colors.white60),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            )
          : const Text('فواتير المشتريات'),
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
      ],
    );
  }

  Widget _buildStatisticsHeader() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accentOrange, const Color(0xFFFF8F00)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.accentOrange.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  label: 'إجمالي المشتريات',
                  value: CurrencyFormatter.formatCompactWithSymbol(_totalPurchases),
                  icon: Icons.shopping_cart,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _buildStatItem(
                  label: 'المدفوع',
                  value: CurrencyFormatter.formatCompactWithSymbol(_totalPaid),
                  icon: Icons.check_circle,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _buildStatItem(
                  label: 'المتبقي',
                  value: CurrencyFormatter.formatCompactWithSymbol(_totalRemaining),
                  icon: Icons.pending_actions,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Text('$_paidCount مدفوعة', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 12),
                Icon(Icons.warning_amber, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Text('$_unpaidCount معلقة', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String label, required String value, required IconData icon}) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: _paymentStatusFilter == 'الكل' ? 'حالة الدفع' : _paymentStatusFilter,
              icon: Icons.payments,
              items: const ['الكل', 'مدفوع', 'غير مدفوع', 'مدفوع جزئياً'],
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
              avatar: Icon(Icons.calendar_month, size: 16, color: _dateRange != null ? AppColors.accentOrange : null),
              label: Text(
                _dateRange != null
                    ? '${DateFormatter.formatDate(_dateRange!.start)} – ${DateFormatter.formatDate(_dateRange!.end)}'
                    : 'الفترة',
                style: TextStyle(fontSize: 12, color: _dateRange != null ? AppColors.accentOrange : null),
              ),
              side: _dateRange != null ? BorderSide(color: AppColors.accentOrange) : null,
              onPressed: _pickDateRange,
            ),
            if (_dateRange != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: () => setState(() => _dateRange = null),
                child: const Icon(Icons.close, size: 16, color: AppColors.textHint),
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
      avatar: Icon(icon, size: 16, color: isActive ? AppColors.accentOrange : null),
      label: Text(label, style: TextStyle(fontSize: 12, color: isActive ? AppColors.accentOrange : null, fontWeight: isActive ? FontWeight.w600 : null)),
      side: isActive ? BorderSide(color: AppColors.accentOrange) : null,
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
                  trailing: item == selected ? const Icon(Icons.check, color: AppColors.accentOrange, size: 20) : null,
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
          Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('لا توجد فواتير مشتريات', style: context.textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('أضف فاتورة مشتريات جديدة بالضغط على الزر أدناه', style: context.textTheme.bodySmall),
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

  Future<void> _printInvoice(BuildContext context, Map<String, dynamic> invoiceData) async {
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

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.accentOrange),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PURCHASE INVOICE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _PurchaseInvoiceCard extends StatelessWidget {
  const _PurchaseInvoiceCard({
    required this.invoiceData,
    required this.displayInvoiceId,
    required this.invoiceTypeAr,
    this.onTap,
    this.onPrint,
  });

  final Map<String, dynamic> invoiceData;
  final String Function(String?) displayInvoiceId;
  final String Function(String?) invoiceTypeAr;
  final VoidCallback? onTap;
  final VoidCallback? onPrint;

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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isReturn ? AppColors.warning : AppColors.info).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isReturn ? Icons.undo : Icons.shopping_cart,
                      color: isReturn ? AppColors.warning : AppColors.info,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayInvoiceId(invoiceData['id'] as String?),
                                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildTypeBadge(type),
                            const SizedBox(width: 4),
                            _buildPaymentBadge(isDark, paymentMechanism),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoiceData['entity_name'] as String? ?? 'بدون مورد',
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
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentOrange,
                        ),
                      ),
                      if (currency != 'YER')
                        Text(currency, style: context.textTheme.labelSmall?.copyWith(color: AppColors.textHint, fontSize: 9)),
                      GestureDetector(
                        onTap: onPrint,
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
                      DateFormatter.formatDateTime(
                        DateTime.tryParse(invoiceData['created_at'] as String? ?? '') ?? DateTime.now(),
                      ),
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
                          style: context.textTheme.labelSmall?.copyWith(
                            color: AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _buildTypeBadge(String type) {
    final label = invoiceTypeAr(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.info)),
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
      'partial' => ('مدفوع جزئياً', AppColors.infoLight, AppColors.info),
      'pending' => ('معلق', AppColors.warningLight, AppColors.warning),
      _ => (status, AppColors.surfaceVariant, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fgColor)),
    );
  }
}
