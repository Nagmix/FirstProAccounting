import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';
import '../invoices/create_invoice_screen.dart';

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allQuotations = [];
  List<Map<String, dynamic>> _filteredQuotations = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _searchQuery = '';
  late TabController _tabController;

  final List<MapEntry<String, String>> _statusTabs = [
    const MapEntry('all', 'الكل'),
    const MapEntry('draft', 'مسودة'),
    const MapEntry('sent', 'مرسل'),
    const MapEntry('accepted', 'مقبول'),
    const MapEntry('rejected', 'مرفوض'),
    const MapEntry('expired', 'منتهي'),
    const MapEntry('converted', 'تم التحويل'),
  ];

  static const Map<String, Color> _statusColors = {
    'draft': Colors.grey,
    'sent': Colors.blue,
    'accepted': Colors.green,
    'rejected': Colors.red,
    'expired': Colors.orange,
    'converted': Colors.purple,
  };

  static const Map<String, String> _statusLabels = {
    'draft': 'مسودة',
    'sent': 'مرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي الصلاحية',
    'converted': 'تم التحويل',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedStatus = _statusTabs[_tabController.index].key);
        _applyFilters();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      _allQuotations = await db.getAllQuotations();
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = _allQuotations;
    if (_selectedStatus != 'all') {
      filtered = filtered.where((q) => q['status'] == _selectedStatus).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((q) {
        final num = (q['quotation_number'] ?? '').toString().toLowerCase();
        final name = (q['customer_name'] ?? '').toString().toLowerCase();
        return num.contains(query) || name.contains(query);
      }).toList();
    }
    setState(() => _filteredQuotations = filtered);
  }

  Future<void> _deleteQuotation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف عرض السعر'),
        content: const Text('هل أنت متأكد من حذف عرض السعر هذا؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper().deleteQuotation(id);
      _loadData();
    }
  }

  Future<void> _changeStatus(String id, String newStatus) async {
    await DatabaseHelper().updateQuotation(id, {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _loadData();
  }

  /// Convert an accepted quotation to a sales invoice
  Future<void> _convertToInvoice(Map<String, dynamic> quotation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل إلى فاتورة مبيعات'),
        content: Text('سيتم تحويل عرض السعر ${quotation['quotation_number']} إلى فاتورة مبيعات فعلية مع إنشاء القيود المحاسبية. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('تحويل'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = DatabaseHelper();
      final quotationId = quotation['id'] as String;
      final now = DateTime.now().toIso8601String();

      // Get quotation items
      final items = await db.getQuotationItems(quotationId);

      // Create invoice from quotation data
      final invoiceId = 'SI-${now.substring(0, 10).replaceAll('-', '')}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final invoiceMap = {
        'id': invoiceId,
        'type': 'sale',
        'payment_mechanism': 'cash',
        'payment_method': 'cash',
        'is_return': 0,
        'cash_box_id': null,
        'customer_id': quotation['customer_id'],
        'subtotal': (quotation['subtotal'] as num?)?.toDouble() ?? 0.0,
        'discount_rate': (quotation['discount_rate'] as num?)?.toDouble() ?? 0.0,
        'discount_amount': (quotation['discount_amount'] as num?)?.toDouble() ?? 0.0,
        'tax_amount': (quotation['tax_amount'] as num?)?.toDouble() ?? 0.0,
        'total': (quotation['total'] as num?)?.toDouble() ?? 0.0,
        'paid_amount': 0.0,
        'remaining': (quotation['total'] as num?)?.toDouble() ?? 0.0,
        'status': 'pending',
        'currency': quotation['currency'] ?? 'YER',
        'exchange_rate': (quotation['exchange_rate'] as num?)?.toDouble() ?? 1.0,
        'is_posted': 0,
        'created_at': now,
      };

      final invoiceItems = items.map((item) => {
        'invoice_id': invoiceId,
        'product_id': item['product_id'],
        'product_name': item['product_name'] ?? '',
        'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
        'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
        'total_price': (item['total_price'] as num?)?.toDouble() ?? 0.0,
      }).toList();

      // Save invoice with journal entries
      await db.saveInvoiceWithJournalEntries(
        invoiceMap,
        invoiceItems,
        invoiceType: 'sale',
        paymentMechanism: 'cash',
        isReturn: false,
      );

      // Update quotation status to converted
      await db.updateQuotation(quotationId, {
        'status': 'converted',
        'converted_to_sales_order': 1,
        'updated_at': now,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحويل عرض السعر إلى فاتورة مبيعات بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحويل: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showQuotationDetails(Map<String, dynamic> quotation) {
    final status = quotation['status'] ?? 'draft';
    final canConvert = status == 'accepted' || status == 'sent';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تفاصيل عرض السعر', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                _detailRow('رقم العرض', quotation['quotation_number'] ?? ''),
                _detailRow('العميل', quotation['customer_name'] ?? 'بدون عميل'),
                _detailRow('العملة', quotation['currency'] ?? 'YER'),
                _detailRow('الإجمالي', CurrencyFormatter.format((quotation['total'] as num?)?.toDouble() ?? 0)),
                _detailRow('الحالة', _statusLabels[status] ?? status),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(ctx); _showStatusMenu(quotation['id'], status); },
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('تغيير الحالة'),
                      ),
                    ),
                    if (canConvert) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _convertToInvoice(quotation);
                          },
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('تحويل لفاتورة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _showStatusMenu(String quotationId, String currentStatus) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('تغيير حالة عرض السعر', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const Divider(),
              ..._statusLabels.entries.where((e) => e.key != currentStatus).map((entry) => ListTile(
                leading: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: _statusColors[entry.key], shape: BoxShape.circle),
                ),
                title: Text(entry.value),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeStatus(quotationId, entry.key);
                },
              )),
            ],
          ),
        ),
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
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('عروض الأسعار'),
          centerTitle: true,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            tabs: _statusTabs.map((e) => Tab(text: e.value)).toList(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          onChanged: (v) { _searchQuery = v; _applyFilters(); },
                          decoration: InputDecoration(
                            hintText: 'بحث برقم العرض أو اسم العميل...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor: isDark ? AppColors.darkSurface : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: _buildSummaryCard(theme, isDark),
                      ),
                    ),
                    if (_filteredQuotations.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState(isDark))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _buildQuotationCard(ctx, _filteredQuotations[i], isDark, theme),
                            childCount: _filteredQuotations.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('قريباً - إنشاء عرض سعر جديد')),
            );
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('عرض سعر جديد', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, bool isDark) {
    final totalValue = _filteredQuotations.fold<double>(0, (sum, q) => sum + ((q['total'] as num?)?.toDouble() ?? 0));
    final acceptedCount = _filteredQuotations.where((q) => q['status'] == 'accepted').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي العروض', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('${_filteredQuotations.length} عرض', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القيمة الإجمالية', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.format(totalValue), style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المقبولة', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('$acceptedCount', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotationCard(BuildContext ctx, Map<String, dynamic> q, bool isDark, ThemeData theme) {
    final status = q['status'] ?? 'draft';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final total = (q['total'] as num?)?.toDouble() ?? 0;
    final currency = q['currency'] ?? 'YER';
    final createdAt = q['created_at'] != null ? DateTime.tryParse(q['created_at']) : null;
    final canConvert = status == 'accepted' || status == 'sent';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => _showQuotationDetails(q),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                q['quotation_number'] ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _statusLabels[status] ?? status,
                                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q['customer_name'] ?? 'بدون عميل',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
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
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (canConvert) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _convertToInvoice(q),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('تحويل إلى فاتورة مبيعات', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description, size: 64, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('لا توجد عروض أسعار', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('اضغط على + لإنشاء عرض سعر جديد', style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
        ],
      ),
    );
  }
}
