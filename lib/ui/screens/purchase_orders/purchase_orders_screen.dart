import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/order_repository.dart';
import '../../../data/datasources/repositories/supplier_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';

/// Helper class for purchase order line items in the creation form.
class _OrderItem {
  int? productId;
  String productName = '';
  double quantity = 1.0;
  double unitPrice = 0.0;

  double get total => quantity * unitPrice;
}

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _searchQuery = '';
  late TabController _tabController;

  final List<MapEntry<String, String>> _statusTabs = [
    const MapEntry('all', 'الكل'),
    const MapEntry('draft', 'مسودة'),
    const MapEntry('sent', 'مرسل'),
    const MapEntry('received', 'مستلم'),
    const MapEntry('cancelled', 'ملغي'),
  ];

  static const Map<String, Color> _statusColors = {
    'draft': Colors.grey,
    'sent': Colors.blue,
    'received': Colors.green,
    'cancelled': Colors.red,
  };

  static const Map<String, String> _statusLabels = {
    'draft': 'مسودة',
    'sent': 'مرسل',
    'received': 'مستلم',
    'cancelled': 'ملغي',
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
      _allOrders = await locator<OrderRepository>().getAllPurchaseOrders();
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = _allOrders;
    if (_selectedStatus != 'all') {
      filtered = filtered.where((o) => o['status'] == _selectedStatus).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        final num = (o['order_number'] ?? '').toString().toLowerCase();
        final name = (o['supplier_name'] ?? '').toString().toLowerCase();
        return num.contains(query) || name.contains(query);
      }).toList();
    }
    setState(() => _filteredOrders = filtered);
  }

  Future<void> _deleteOrder(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف طلب الشراء'),
        content: const Text(
            'هل أنت متأكد من حذف طلب الشراء هذا؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await locator<OrderRepository>().deletePurchaseOrder(id);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('حدث خطأ أثناء الحذف'),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _changeStatus(String id, String newStatus) async {
    try {
      await locator<OrderRepository>().updatePurchaseOrder(id, {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      });
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء التحديث'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final status = order['status'] ?? 'draft';
    final orderId = order['id'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.4,
            maxChildSize: 0.85,
            expand: false,
            builder: (ctx, scrollController) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future:
                    locator<OrderRepository>().getPurchaseOrderItems(orderId),
                builder: (ctx, snapshot) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewPadding.bottom,
                      left: 20,
                      right: 20,
                      top: 20,
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle bar
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                  color: Colors.grey[400],
                                  borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                          Text('تفاصيل طلب الشراء',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          _detailRow('رقم الطلب', order['order_number'] ?? ''),
                          _detailRow(
                              'المورد', order['supplier_name'] ?? 'بدون مورد'),
                          _detailRow('العملة', order['currency'] ?? 'YER'),
                          _detailRow(
                              'الإجمالي',
                              CurrencyFormatter.format(
                                  MoneyHelper.readMoney(order['total']))),
                          if (order['expected_date'] != null)
                            _detailRow(
                                'تاريخ الاستلام المتوقع',
                                DateFormatter.formatDate(
                                    DateTime.tryParse(order['expected_date']) ??
                                        DateTime.now())),
                          if (order['notes'] != null &&
                              (order['notes'] as String).isNotEmpty)
                            _detailRow('ملاحظات', order['notes']),
                          _detailRow('الحالة', _statusLabels[status] ?? status),
                          const Divider(height: 32),
                          // Items
                          Text('الأصناف',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator()))
                          else if (snapshot.hasData &&
                              snapshot.data!.isNotEmpty)
                            ...snapshot.data!.map((item) => _buildItemRow(item))
                          else
                            const Text('لا توجد أصناف',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showStatusMenu(order['id'], status);
                                  },
                                  icon: const Icon(Icons.sync, size: 18),
                                  label: const Text('تغيير الحالة'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteOrder(order['id']);
                                  },
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  label: const Text('حذف'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(item['product_name'] ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 1,
            child: Text('${(item['quantity'] as num?)?.toDouble() ?? 0}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              CurrencyFormatter.format(
                  MoneyHelper.readMoney(item['total_price'])),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _showStatusMenu(String orderId, String currentStatus) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('تغيير حالة طلب الشراء',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const Divider(),
              ..._statusLabels.entries
                  .where((e) => e.key != currentStatus)
                  .map((entry) => ListTile(
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: _statusColors[entry.key],
                              shape: BoxShape.circle),
                        ),
                        title: Text(entry.value),
                        onTap: () {
                          Navigator.pop(ctx);
                          _changeStatus(orderId, entry.key);
                        },
                      )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Create Purchase Order Dialog ─────────────────────────────────

  void _showCreateOrderDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreatePurchaseOrderForm(
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
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('طلبات الشراء'),
          centerTitle: true,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
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
                          onChanged: (v) {
                            _searchQuery = v;
                            _applyFilters();
                          },
                          decoration: InputDecoration(
                            hintText: 'بحث برقم الطلب أو اسم المورد...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor:
                                isDark ? AppColors.darkSurface : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkDivider
                                      : AppColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkDivider
                                      : AppColors.divider),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
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
                    if (_filteredOrders.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState(isDark))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _buildOrderCard(
                                ctx, _filteredOrders[i], isDark, theme),
                            childCount: _filteredOrders.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateOrderDialog,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('طلب شراء جديد',
              style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, bool isDark) {
    final totalValue = _filteredOrders.fold<double>(
        0, (sum, o) => sum + (MoneyHelper.readMoney(o['total'])));
    final receivedCount =
        _filteredOrders.where((o) => o['status'] == 'received').length;

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
                Text('إجمالي الطلبات',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('${_filteredOrders.length} طلب',
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القيمة الإجمالية',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.format(totalValue),
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المستلمة',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 4),
                Text('$receivedCount',
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(
      BuildContext ctx, Map<String, dynamic> o, bool isDark, ThemeData theme) {
    final status = o['status'] ?? 'draft';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final total = MoneyHelper.readMoney(o['total']);
    final currency = o['currency'] ?? 'YER';
    final createdAt =
        o['created_at'] != null ? DateTime.tryParse(o['created_at']) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.darkDivider : AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(o),
        onLongPress: () => _deleteOrder(o['id']),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shopping_cart, color: statusColor, size: 22),
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
                            o['order_number'] ?? '',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _statusLabels[status] ?? status,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      o['supplier_name'] ?? 'بدون مورد',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currency,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.formatDate(createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
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
          Icon(Icons.shopping_cart,
              size: 64,
              color:
                  isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('لا توجد طلبات شراء',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('اضغط على + لإنشاء طلب شراء جديد',
              style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.textTertiary)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Create Purchase Order Form (Bottom Sheet)
// ══════════════════════════════════════════════════════════════════

class _CreatePurchaseOrderForm extends StatefulWidget {
  final VoidCallback onSaved;
  const _CreatePurchaseOrderForm({required this.onSaved});

  @override
  State<_CreatePurchaseOrderForm> createState() =>
      _CreatePurchaseOrderFormState();
}

class _CreatePurchaseOrderFormState extends State<_CreatePurchaseOrderForm> {
  final _discountRateController = TextEditingController();
  final _discountAmountController = TextEditingController();
  final _notesController = TextEditingController();

  int? _selectedSupplierId;
  String _selectedCurrency = 'YER';
  DateTime? _expectedDate;
  List<_OrderItem> _items = [];
  bool _isSaving = false;

  // Dropdown data
  List<Map<String, dynamic>> _suppliers = [];
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
      final suppliers = await locator<SupplierRepository>().getAllSuppliers();
      final products = await locator<ProductRepository>()
          .getAllProducts(activeOnly: true, orderBy: 'name_ar ASC');
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          _products = products;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  double get _subtotal =>
      _items.fold<double>(0, (sum, item) => sum + item.total);

  double get _discountRate {
    final val = double.tryParse(_discountRateController.text) ?? 0;
    return val.clamp(0, 100);
  }

  double get _discountAmount {
    final val = double.tryParse(_discountAmountController.text) ?? 0;
    return val < 0 ? 0 : val;
  }

  double get _calculatedDiscountAmount => _subtotal * (_discountRate / 100);

  double get _effectiveDiscountAmount =>
      _discountAmount > 0 ? _discountAmount : _calculatedDiscountAmount;

  double get _total => _subtotal - _effectiveDiscountAmount;

  void _onDiscountRateChanged(String value) {
    setState(() {
      if (value.isNotEmpty &&
          double.tryParse(value) != null &&
          double.tryParse(value)! > 0) {
        _discountAmountController.clear();
      }
    });
  }

  void _onDiscountAmountChanged(String value) {
    setState(() {
      if (value.isNotEmpty &&
          double.tryParse(value) != null &&
          double.tryParse(value)! > 0) {
        _discountRateController.clear();
      }
    });
  }

  void _addItem() {
    setState(() => _items.add(_OrderItem()));
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _updateItem(int index, {_OrderItem? Function(_OrderItem)? update}) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      final current = _items[index];
      final updated = update != null ? update(current) : current;
      if (updated != null) _items[index] = updated;
    });
  }

  Future<void> _pickExpectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _expectedDate = picked);
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
                return nameAr.contains(q) ||
                    nameEn.contains(q) ||
                    barcode.contains(q);
              }).toList();
            }
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text('اختر منتج',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close)),
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
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
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
                                final costPrice =
                                    MoneyHelper.readMoney(p['cost_price']);
                                return ListTile(
                                  title: Text(p['name_ar'] ?? ''),
                                  subtitle: Text(CurrencyFormatter.formatValue(
                                          costPrice) +
                                      ' ${_currencySymbol[_selectedCurrency] ?? ''}'),
                                  trailing: Text(
                                      'كود: ${p['item_code'] ?? p['id'] ?? ''}',
                                      style: const TextStyle(fontSize: 12)),
                                  onTap: () {
                                    _updateItem(itemIndex, update: (item) {
                                      item.productId = p['id'] as int?;
                                      item.productName = p['name_ar'] ?? '';
                                      item.unitPrice = costPrice;
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

  Future<void> _saveOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى إضافة صنف واحد على الأقل'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    for (int i = 0; i < _items.length; i++) {
      if (_items[i].productId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('يرجى اختيار المنتج للصنف ${i + 1}'),
              backgroundColor: AppColors.error),
        );
        return;
      }
      if (_items[i].quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('يرجى إدخال كمية صحيحة للصنف ${i + 1}'),
              backgroundColor: AppColors.error),
        );
        return;
      }
      if (_items[i].unitPrice < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('يرجى إدخال سعر صحيح للصنف ${i + 1}'),
              backgroundColor: AppColors.error),
        );
        return;
      }
    }

    if (_discountRate < 0 || _discountRate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('نسبة الخصم يجب أن تكون بين 0 و 100'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    if (_discountAmount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('مبلغ الخصم لا يمكن أن يكون سالباً'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    if (_effectiveDiscountAmount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('الخصم لا يمكن أن يتجاوز المجموع الفرعي'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final orderNumber =
          await locator<OrderRepository>().getNextPurchaseOrderNumber();
      final now = DateTime.now();

      final orderMap = {
        'id': orderNumber,
        'order_number': orderNumber,
        'supplier_id': _selectedSupplierId,
        'currency': _selectedCurrency,
        'exchange_rate': 1.0,
        'subtotal': _subtotal,
        'discount_rate': _discountRate,
        'discount_amount': _effectiveDiscountAmount,
        'tax_amount': 0.0,
        'total': _total,
        'status': 'draft',
        'expected_date': _expectedDate?.toIso8601String(),
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'terms_conditions': null,
        'warehouse_id': null,
        'converted_to_invoice': 0,
        'invoice_id': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final orderItems = _items
          .map((item) => {
                'purchase_order_id': orderNumber,
                'product_id': item.productId,
                'product_name': item.productName,
                'description': null,
                'quantity': item.quantity,
                'unit_price': item.unitPrice,
                'total_price': item.total,
              })
          .toList();

      await locator<OrderRepository>()
          .insertPurchaseOrderWithItems(orderMap, orderItems);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء طلب الشراء $orderNumber بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء الحفظ'),
              backgroundColor: AppColors.error),
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
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Text('إنشاء طلب شراء جديد',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form body
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 16,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Supplier dropdown
                          DropdownButtonFormField<int>(
                            value: _selectedSupplierId,
                            decoration: InputDecoration(
                              labelText: 'المورد',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('بدون مورد')),
                              ..._suppliers.map((s) => DropdownMenuItem(
                                    value: s['id'] as int,
                                    child: Text(s['name'] ?? '',
                                        overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedSupplierId = v),
                          ),
                          const SizedBox(height: 12),
                          // Currency dropdown
                          DropdownButtonFormField<String>(
                            value: _selectedCurrency,
                            decoration: InputDecoration(
                              labelText: 'العملة',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            items: _currencyLabels.entries
                                .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedCurrency = v!),
                          ),
                          const SizedBox(height: 12),
                          // Expected date
                          InkWell(
                            onTap: _pickExpectedDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'تاريخ الاستلام المتوقع',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _expectedDate != null
                                        ? DateFormatter.formatDate(
                                            _expectedDate!)
                                        : 'اختر التاريخ',
                                    style: TextStyle(
                                      color: _expectedDate != null
                                          ? null
                                          : AppColors.textHint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Items
                          Row(
                            children: [
                              Text('الأصناف',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _addItem,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة صنف'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_items.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: isDark
                                        ? AppColors.darkDivider
                                        : AppColors.divider,
                                    style: BorderStyle.solid),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('لم يتم إضافة أصناف بعد',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textHint)),
                            )
                          else
                            ...List.generate(_items.length,
                                (i) => _buildItemCard(i, isDark, theme)),
                          const SizedBox(height: 12),
                          // Discount
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _discountRateController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'خصم %',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  onChanged: _onDiscountRateChanged,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _discountAmountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'خصم ثابت',
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  onChanged: _onDiscountAmountChanged,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Notes
                          TextField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'ملاحظات',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Totals box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('المجموع الفرعي',
                                        style: TextStyle(fontSize: 14)),
                                    Text(
                                        '${CurrencyFormatter.formatValue(_subtotal)} ${_currencySymbol[_selectedCurrency] ?? ''}',
                                        style: const TextStyle(fontSize: 14)),
                                  ],
                                ),
                                if (_effectiveDiscountAmount > 0) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('الخصم',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: AppColors.error)),
                                      Text(
                                          '- ${CurrencyFormatter.formatValue(_effectiveDiscountAmount)} ${_currencySymbol[_selectedCurrency] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: AppColors.error)),
                                    ],
                                  ),
                                ],
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('الإجمالي',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary)),
                                    Text(
                                        '${CurrencyFormatter.formatValue(_total)} ${_currencySymbol[_selectedCurrency] ?? ''}',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Save button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveOrder,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check,
                                      color: Colors.white),
                              label: Text(
                                  _isSaving
                                      ? 'جاري الحفظ...'
                                      : 'حفظ طلب الشراء',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index, bool isDark, ThemeData theme) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppColors.darkDivider : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showProductPicker(index),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.productName.isEmpty
                                ? 'اختر منتج'
                                : item.productName,
                            style: TextStyle(
                              fontSize: 13,
                              color: item.productName.isEmpty
                                  ? AppColors.textHint
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeItem(index),
                icon: Icon(Icons.close, size: 18, color: AppColors.error),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  controller: TextEditingController(
                      text:
                          item.quantity == 1.0 ? '' : item.quantity.toString()),
                  onChanged: (v) => _updateItem(index, update: (i) {
                    i.quantity = double.tryParse(v) ?? 1.0;
                    return i;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'سعر الوحدة',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  controller: TextEditingController(
                      text:
                          item.unitPrice == 0 ? '' : item.unitPrice.toString()),
                  onChanged: (v) => _updateItem(index, update: (i) {
                    i.unitPrice = double.tryParse(v) ?? 0;
                    return i;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyFormatter.formatValue(item.total),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
