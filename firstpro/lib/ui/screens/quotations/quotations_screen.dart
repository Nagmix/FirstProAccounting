import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/database_helper.dart';

/// Helper class for quotation line items in the creation form.
class _QuotationItem {
  int? productId;
  String productName;
  double quantity;
  double unitPrice;

  _QuotationItem({
    this.productId,
    this.productName = '',
    this.quantity = 1.0,
    this.unitPrice = 0.0,
  });

  double get total => quantity * unitPrice;
}

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

  // ── Create Quotation Dialog ────────────────────────────────────

  static const Map<String, String> _currencyLabels = {
    'YER': 'ر.ي (ريال يمني)',
    'SAR': 'ر.س (ريال سعودي)',
    'USD': '\$ (دولار أمريكي)',
  };

  void _showCreateQuotationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateQuotationForm(
        onSaved: () => _loadData(),
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
          onPressed: _showCreateQuotationDialog,
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
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
                      color: statusColor.withValues(alpha: 0.1),
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
                                color: statusColor.withValues(alpha: 0.1),
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

// ══════════════════════════════════════════════════════════════════
//  Create Quotation Form (Bottom Sheet)
// ══════════════════════════════════════════════════════════════════

class _CreateQuotationForm extends StatefulWidget {
  final VoidCallback onSaved;
  const _CreateQuotationForm({required this.onSaved});

  @override
  State<_CreateQuotationForm> createState() => _CreateQuotationFormState();
}

class _CreateQuotationFormState extends State<_CreateQuotationForm> {
  final _formKey = GlobalKey<FormState>();
  final _discountRateController = TextEditingController();
  final _discountAmountController = TextEditingController();
  final _notesController = TextEditingController();

  int? _selectedCustomerId;
  String _selectedCurrency = 'YER';
  DateTime _validUntilDate = DateTime.now().add(const Duration(days: 30));
  List<_QuotationItem> _items = [];
  bool _isSaving = false;

  // Dropdown data
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _products = [];
  bool _isLoadingData = true;

  static const Map<String, String> _currencyLabels = {
    'YER': 'ر.ي (ريال يمني)',
    'SAR': 'ر.س (ريال سعودي)',
    'USD': '\$ (دولار أمريكي)',
  };

  static const Map<String, String> _currencySymbol = {
    'YER': 'ر.ي',
    'SAR': 'ر.س',
    'USD': '\$',
  };

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  @override
  void dispose() {
    _discountRateController.dispose();
    _discountAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdownData() async {
    try {
      final db = DatabaseHelper();
      final customers = await db.getAllCustomers(orderBy: 'name ASC');
      final products = await db.getAllProducts(activeOnly: true, orderBy: 'name_ar ASC');
      if (mounted) {
        setState(() {
          _customers = customers;
          _products = products;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  double get _subtotal => _items.fold<double>(0, (sum, item) => sum + item.total);

  double get _discountRate {
    final val = double.tryParse(_discountRateController.text) ?? 0;
    return val.clamp(0, 100);
  }

  double get _discountAmount {
    final val = double.tryParse(_discountAmountController.text) ?? 0;
    return val < 0 ? 0 : val;
  }

  double get _calculatedDiscountAmount => _subtotal * (_discountRate / 100);

  double get _effectiveDiscountAmount => _discountAmount > 0 ? _discountAmount : _calculatedDiscountAmount;

  double get _total => _subtotal - _effectiveDiscountAmount;

  void _onDiscountRateChanged(String value) {
    setState(() {
      // Clear fixed amount when rate is being used
      if (value.isNotEmpty && double.tryParse(value) != null && double.tryParse(value)! > 0) {
        _discountAmountController.clear();
      }
    });
  }

  void _onDiscountAmountChanged(String value) {
    setState(() {
      // Clear rate when fixed amount is being used
      if (value.isNotEmpty && double.tryParse(value) != null && double.tryParse(value)! > 0) {
        _discountRateController.clear();
      }
    });
  }

  void _addItem() {
    setState(() {
      _items.add(_QuotationItem());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _updateItem(int index, {_QuotationItem? Function(_QuotationItem)? update}) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      final current = _items[index];
      final updated = update != null ? update(current) : current;
      if (updated != null) _items[index] = updated;
    });
  }

  Future<void> _pickValidUntilDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntilDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _validUntilDate = picked);
    }
  }

  void _showProductPicker(int itemIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            var filtered = _products;
            if (searchQuery.isNotEmpty) {
              final q = searchQuery.toLowerCase();
              filtered = _products.where((p) {
                final nameAr = (p['name_ar'] ?? '').toString().toLowerCase();
                final nameEn = (p['name_en'] ?? '').toString().toLowerCase();
                final barcode = (p['barcode'] ?? '').toString().toLowerCase();
                return nameAr.contains(q) || nameEn.contains(q) || barcode.contains(q);
              }).toList();
            }
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text('اختر منتج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'بحث بالاسم أو الباركود...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        onChanged: (v) => setModalState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد منتجات'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final p = filtered[i];
                                final sellPrice = (p['sell_price'] as num?)?.toDouble() ?? 0;
                                return ListTile(
                                  title: Text(p['name_ar'] ?? ''),
                                  subtitle: Text(CurrencyFormatter.formatValue(sellPrice) + ' ${_currencySymbol[_selectedCurrency] ?? ''}'),
                                  trailing: Text('كود: ${p['item_code'] ?? p['id'] ?? ''}', style: const TextStyle(fontSize: 12)),
                                  onTap: () {
                                    _updateItem(itemIndex, update: (item) {
                                      item.productId = p['id'] as int?;
                                      item.productName = p['name_ar'] ?? '';
                                      item.unitPrice = sellPrice;
                                      return item;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveQuotation() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة صنف واحد على الأقل'), backgroundColor: AppColors.error),
      );
      return;
    }

    // Validate items
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].productId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('يرجى اختيار المنتج للصنف ${i + 1}'), backgroundColor: AppColors.error),
        );
        return;
      }
      if (_items[i].quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('يرجى إدخال كمية صحيحة للصنف ${i + 1}'), backgroundColor: AppColors.error),
        );
        return;
      }
      if (_items[i].unitPrice < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('يرجى إدخال سعر صحيح للصنف ${i + 1}'), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    if (_discountRate < 0 || _discountRate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نسبة الخصم يجب أن تكون بين 0 و 100'), backgroundColor: AppColors.error),
      );
      return;
    }

    if (_discountAmount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مبلغ الخصم لا يمكن أن يكون سالباً'), backgroundColor: AppColors.error),
      );
      return;
    }

    if (_effectiveDiscountAmount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الخصم لا يمكن أن يتجاوز المجموع الفرعي'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = DatabaseHelper();
      final quotationNumber = await db.getNextQuotationNumber();
      final now = DateTime.now();

      final quotationMap = {
        'id': quotationNumber,
        'quotation_number': quotationNumber,
        'customer_id': _selectedCustomerId,
        'currency': _selectedCurrency,
        'exchange_rate': 1.0,
        'subtotal': _subtotal,
        'discount_rate': _discountRate,
        'discount_amount': _effectiveDiscountAmount,
        'tax_amount': 0.0,
        'total': _total,
        'status': 'draft',
        'valid_until': _validUntilDate.toIso8601String(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'terms_conditions': null,
        'converted_to_sales_order': 0,
        'sales_order_id': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final quotationItems = _items.map((item) => {
        'quotation_id': quotationNumber,
        'product_id': item.productId,
        'product_name': item.productName,
        'description': null,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total_price': item.total,
      }).toList();

      await db.insertQuotationWithItems(quotationMap, quotationItems);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء عرض السعر $quotationNumber بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ عرض السعر: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Text('إنشاء عرض سعر جديد', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form body
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 20, right: 20, top: 16,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Customer & Currency Row ──
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<int>(
                                    value: _selectedCustomerId,
                                    decoration: InputDecoration(
                                      labelText: 'العميل',
                                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    ),
                                    hint: const Text('بدون عميل'),
                                    items: _customers.map((c) => DropdownMenuItem<int>(
                                      value: c['id'] as int?,
                                      child: Text(c['name'] ?? '', overflow: TextOverflow.ellipsis),
                                    )).toList(),
                                    onChanged: (v) => setState(() {
                                      _selectedCustomerId = v;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedCurrency,
                                    decoration: InputDecoration(
                                      labelText: 'العملة',
                                      prefixIcon: const Icon(Icons.currency_exchange, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    ),
                                    items: _currencyLabels.entries.map((e) => DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    )).toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _selectedCurrency = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── Valid Until ──
                            InkWell(
                              onTap: _pickValidUntilDate,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'صالح حتى',
                                  prefixIcon: const Icon(Icons.calendar_today, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                ),
                                child: Text(
                                  '${_validUntilDate.day}/${_validUntilDate.month}/${_validUntilDate.year}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Items Section ──
                            Row(
                              children: [
                                Text('الأصناف', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: _addItem,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('إضافة صنف'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Items list
                            if (_items.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkBackground : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.divider, style: BorderStyle.solid),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 40, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
                                    const SizedBox(height: 8),
                                    Text('لم يتم إضافة أصناف بعد', style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
                                  ],
                                ),
                              )
                            else
                              ..._items.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final item = entry.value;
                                return _buildItemCard(idx, item, isDark, theme);
                              }),

                            const SizedBox(height: 16),

                            // ── Discount ──
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _discountRateController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'نسبة الخصم %',
                                      prefixIcon: const Icon(Icons.percent, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    ),
                                    onChanged: _onDiscountRateChanged,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _discountAmountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'مبلغ الخصم',
                                      prefixIcon: const Icon(Icons.money_off, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    ),
                                    onChanged: _onDiscountAmountChanged,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── Notes ──
                            TextFormField(
                              controller: _notesController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'ملاحظات',
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(bottom: 20),
                                  child: Icon(Icons.note, size: 20),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Totals ──
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkBackground : Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.divider),
                              ),
                              child: Column(
                                children: [
                                  _buildTotalRow('المجموع الفرعي', _subtotal, isDark),
                                  if (_effectiveDiscountAmount > 0) ...[
                                    const SizedBox(height: 8),
                                    _buildTotalRow('الخصم', -_effectiveDiscountAmount, isDark, color: Colors.red),
                                  ],
                                  const Divider(height: 20),
                                  _buildTotalRow('الإجمالي', _total, isDark, isBold: true, color: AppColors.primary),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Save Button ──
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveQuotation,
                                icon: _isSaving
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save, size: 20),
                                label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ عرض السعر (مسودة)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index, _QuotationItem item, bool isDark, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkDivider : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Product row
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showProductPicker(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: item.productId == null ? AppColors.error : (isDark ? AppColors.darkDivider : AppColors.divider)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 18, color: item.productId == null ? AppColors.error : AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.productName.isEmpty ? 'اختر منتج...' : item.productName,
                            style: TextStyle(
                              color: item.productName.isEmpty ? AppColors.error : null,
                              fontWeight: item.productName.isEmpty ? FontWeight.w400 : FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeItem(index),
                icon: Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quantity, Price, Total row
          Row(
            children: [
              // Quantity
              Expanded(
                child: TextFormField(
                  initialValue: item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) {
                    final val = double.tryParse(v) ?? 0;
                    _updateItem(index, update: (i) { i.quantity = val > 0 ? val : 0; return i; });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Unit price
              Expanded(
                child: TextFormField(
                  initialValue: item.unitPrice.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'سعر الوحدة',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) {
                    final val = double.tryParse(v) ?? 0;
                    _updateItem(index, update: (i) { i.unitPrice = val >= 0 ? val : 0; return i; });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Total (read-only)
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'الإجمالي',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  child: Text(
                    CurrencyFormatter.formatValue(item.total),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, bool isDark, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            fontSize: isBold ? 16 : 14,
            color: color ?? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
          ),
        ),
        Text(
          '${amount < 0 ? '-' : ''}${CurrencyFormatter.formatValue(amount.abs())} ${_currencySymbol[_selectedCurrency] ?? ''}',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
            color: color ?? (isDark ? AppColors.darkText : AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
