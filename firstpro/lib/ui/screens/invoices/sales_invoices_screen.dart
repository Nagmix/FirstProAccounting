import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/invoice_pdf_generator.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/invoice_item_model.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';

/// Sales invoices listing screen – shows only sale and sale_return invoices.
class SalesInvoicesScreen extends StatefulWidget {
  const SalesInvoicesScreen({super.key});

  @override
  State<SalesInvoicesScreen> createState() => _SalesInvoicesScreenState();
}

class _SalesInvoicesScreenState extends State<SalesInvoicesScreen> {
  // ── Filter state ────────────────────────────────────────────────
  String _paymentStatusFilter = 'الكل';
  String _paymentMechanismFilter = 'الكل';
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
    _loadInvoices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper();
    final allInvoices = await db.getAllInvoices();
    setState(() {
      _invoices = allInvoices.where((i) {
        final type = i['type'] as String? ?? '';
        return type == 'sale' || type == 'sale_return';
      }).toList();
      _isLoading = false;
    });
  }

  // ── Statistics ──────────────────────────────────────────────────
  double get _totalSales => _invoices.fold(0.0, (sum, i) => sum + ((i['total'] as num?)?.toDouble() ?? 0.0));
  double get _totalPaid => _invoices.fold(0.0, (sum, i) => sum + ((i['paid_amount'] as num?)?.toDouble() ?? 0.0));
  double get _totalRemaining => _invoices.fold(0.0, (sum, i) => sum + ((i['remaining'] as num?)?.toDouble() ?? 0.0));

  // ── Filtered invoices ──────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredInvoices {
    var result = _invoices;

    // Payment status filter
    if (_paymentStatusFilter != 'الكل') {
      final statusMap = {
        'مدفوع': 'paid',
        'غير مدفوع': 'unpaid',
        'مدفوع جزئياً': 'partial',
      };
      final status = statusMap[_paymentStatusFilter];
      if (status != null) {
        result = result.where((i) => i['status'] == status).toList();
      }
    }

    // Payment mechanism filter
    if (_paymentMechanismFilter != 'الكل') {
      final methodMap = {
        'نقداً': 'cash',
        'آجل': 'credit',
      };
      final method = methodMap[_paymentMechanismFilter];
      if (method != null) {
        result = result.where((i) => i['payment_mechanism'] == method).toList();
      }
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
        return id.contains(query) || entityName.contains(query);
      }).toList();
    }

    return result;
  }

  // ── Display helpers ─────────────────────────────────────────────
  String _displayInvoiceId(String? id) {
    if (id == null || id.isEmpty) return '—';
    if (id.length > 12) return '...${id.substring(id.length - 8)}';
    return id;
  }

  String _invoiceTypeAr(String? type) {
    return switch (type) {
      'sale' => 'مبيعات',
      'sale_return' => 'مرتجع مبيعات',
      _ => 'فاتورة',
    };
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
                                return _SalesInvoiceCard(
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreateInvoiceScreen(invoiceType: AppConstants.saleInvoice),
              ),
            ).then((_) => _loadInvoices());
          },
          icon: const Icon(Icons.add),
          label: const Text('فاتورة مبيعات'),
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
                hintText: 'بحث في فواتير المبيعات...',
                hintStyle: TextStyle(color: Colors.white60),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            )
          : const Text('فواتير المبيعات'),
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
      ],
    );
  }

  // ── Statistics header ────────────────────────────────────────────
  Widget _buildStatisticsHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'إجمالي المبيعات',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalSales),
              icon: Icons.trending_up,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'المدفوع',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalPaid),
              icon: Icons.check_circle,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'المتبقي',
              value: CurrencyFormatter.formatCompactWithSymbol(_totalRemaining),
              icon: Icons.pending,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: 'حالة الدفع: $_paymentStatusFilter',
              icon: Icons.payments,
              items: const ['الكل', 'مدفوع', 'غير مدفوع', 'مدفوع جزئياً'],
              selected: _paymentStatusFilter,
              onChanged: (v) => setState(() => _paymentStatusFilter = v),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: 'آلية الدفع: $_paymentMechanismFilter',
              icon: Icons.credit_card,
              items: const ['الكل', 'نقداً', 'آجل'],
              selected: _paymentMechanismFilter,
              onChanged: (v) => setState(() => _paymentMechanismFilter = v),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                _dateRange != null
                    ? '${DateFormatter.formatDate(_dateRange!.start)} – ${DateFormatter.formatDate(_dateRange!.end)}'
                    : 'الفترة',
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
          Icon(Icons.receipt_long, size: 72, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لا توجد فواتير مبيعات', style: context.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'أضف فاتورة مبيعات جديدة بالضغط على الزر أدناه',
            style: context.textTheme.bodySmall,
          ),
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

  // ── Print invoice ────────────────────────────────────────────────
  Future<void> _printInvoice(BuildContext context, Map<String, dynamic> invoiceData) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إنشاء ملف PDF...'), duration: Duration(seconds: 1)),
      );
      final db = DatabaseHelper();
      final items = await db.getInvoiceItems(invoiceData['id'] as String);
      await InvoicePdfGenerator.printInvoice(invoiceData, items);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الطباعة: $e'), backgroundColor: AppColors.error),
        );
      }
    }
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
//  STAT CARD
// ═══════════════════════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SALES INVOICE CARD
// ═══════════════════════════════════════════════════════════════════════════
class _SalesInvoiceCard extends StatelessWidget {
  const _SalesInvoiceCard({
    required this.invoiceData,
    required this.displayInvoiceId,
    required this.invoiceTypeAr,
    this.onTap,
  });

  final Map<String, dynamic> invoiceData;
  final String Function(String?) displayInvoiceId;
  final String Function(String?) invoiceTypeAr;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final type = invoiceData['type'] as String? ?? '';
    final isReturn = (invoiceData['is_return'] as int?) == 1;
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
              // ── Type icon ─────────────────────────────────────
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (isReturn ? AppColors.warning : AppColors.success).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isReturn ? Icons.refresh : Icons.receipt,
                  color: isReturn ? AppColors.warning : AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // ── Info column ───────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: ID + type badge + payment badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayInvoiceId(invoiceData['id'] as String?),
                            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildTypeBadge(isDark, type),
                        const SizedBox(width: 4),
                        _buildPaymentBadge(isDark, paymentMechanism),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Entity name
                    Text(
                      invoiceData['entity_name'] as String? ?? 'بدون عميل',
                      style: context.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    // Date
                    Text(
                      DateFormatter.formatDateTime(
                        DateTime.tryParse(invoiceData['created_at'] as String? ?? '') ?? DateTime.now(),
                      ),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    // Remaining amount
                    if (remaining > 0.005) ...[
                      const SizedBox(height: 4),
                      Text(
                        'المتبقي: ${CurrencyFormatter.format(remaining)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Amount + status + print ────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(total),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusChip(status),
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.print, size: 18, color: AppColors.textSecondary),
                    onPressed: () => _printInvoice(context, invoiceData),
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

  Widget _buildTypeBadge(bool isDark, String type) {
    final label = invoiceTypeAr(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildPaymentBadge(bool isDark, String paymentMechanism) {
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

  Widget _buildStatusChip(String status) {
    final (label, bgColor, fgColor) = switch (status) {
      'paid' => ('مدفوع', AppColors.successLight, AppColors.success),
      'unpaid' => ('غير مدفوع', AppColors.errorLight, AppColors.error),
      'partial' => ('مدفوع جزئياً', AppColors.infoLight, AppColors.info),
      'pending' => ('معلق', AppColors.warningLight, AppColors.warning),
      _ => (status, AppColors.surfaceVariant, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
    );
  }
}
