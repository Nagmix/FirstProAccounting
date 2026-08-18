import 'package:flutter/material.dart';

import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/service/service_order_status_policy.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/data/datasources/services/service_order_service.dart';
import 'package:firstpro/data/models/service_order_model.dart';

class ServiceOrdersScreen extends StatefulWidget {
  const ServiceOrdersScreen({super.key});

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen>
    with SingleTickerProviderStateMixin {
  final _service = locator<ServiceOrderService>();
  final _searchController = TextEditingController();
  late final TabController _tabController;
  List<ServiceOrder> _orders = const [];
  List<ServiceOrder> _filtered = const [];
  bool _loading = true;
  String _selectedStatus = 'all';

  static const _tabs = <MapEntry<String, String>>[
    MapEntry('all', 'الكل'),
    MapEntry('draft', 'مسودة'),
    MapEntry('received', 'مستلم'),
    MapEntry('diagnosing', 'تشخيص'),
    MapEntry('in_progress', 'قيد التنفيذ'),
    MapEntry('ready', 'جاهز'),
    MapEntry('delivered', 'تم التسليم'),
    MapEntry('cancelled', 'ملغي'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _selectedStatus = _tabs[_tabController.index].key;
        _applyFilter();
      }
    });
    _searchController.addListener(_applyFilter);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController
      ..removeListener(_applyFilter)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (mounted) setState(() => _loading = true);
    try {
      _orders = await _service.getAll();
      _applyFilter();
    } catch (error) {
      if (mounted) _showError('تعذر تحميل أوامر الخدمة: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    final result = _orders.where((order) {
      final statusMatches = _selectedStatus == 'all' ||
          order.status == _selectedStatus;
      final queryMatches = query.isEmpty ||
          order.orderNumber.toLowerCase().contains(query) ||
          order.id.toLowerCase().contains(query) ||
          (order.notes ?? '').toLowerCase().contains(query);
      return statusMatches && queryMatches;
    }).toList(growable: false);
    if (mounted) setState(() => _filtered = result);
  }

  Future<void> _createDraft() async {
    final now = DateTime.now();
    final id = 'SO-${now.millisecondsSinceEpoch}';
    try {
      await _service.createDraft(
        order: ServiceOrder(
          id: id,
          orderNumber: id,
          receivedAt: now,
          currencyCode: 'YER',
        ),
      );
      if (mounted) {
        _showSuccess('تم إنشاء أمر الخدمة $id كمسودة');
        await _loadOrders();
      }
    } catch (error) {
      if (mounted) _showError('تعذر إنشاء أمر الخدمة: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أوامر الخدمة والصيانة'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((tab) => Tab(text: tab.value)).toList(),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadOrders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'بحث في رقم أمر الخدمة أو الملاحظات',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadOrders,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 140),
                              Center(child: Text('لا توجد أوامر خدمة')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                            itemCount: _filtered.length,
                            itemBuilder: (_, index) => _OrderCard(
                              order: _filtered[index],
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ServiceOrderDetailScreen(
                                      orderId: _filtered[index].id,
                                    ),
                                  ),
                                );
                                _loadOrders();
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createDraft,
        icon: const Icon(Icons.add),
        label: const Text('أمر خدمة جديد'),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final ServiceOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.14),
          child: Icon(Icons.build, color: color),
        ),
        title: Text(order.orderNumber),
        subtitle: Text(
          '${_statusLabel(order.status)} • ${order.currencyCode} ${order.total.toStringAsFixed(2)}\n'
          'المتبقي: ${order.remaining.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: order.isPosted
            ? const Tooltip(
                message: 'مرحّل محاسبياً',
                child: Icon(Icons.verified, color: AppColors.success),
              )
            : const Icon(Icons.chevron_left),
      ),
    );
  }
}

class ServiceOrderDetailScreen extends StatefulWidget {
  const ServiceOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ServiceOrderDetailScreen> createState() =>
      _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState extends State<ServiceOrderDetailScreen> {
  final _service = locator<ServiceOrderService>();
  ServiceOrder? _order;
  bool _loading = true;
  String? _error;

  static const _nextStatuses = <String, String>{
    'draft': 'received',
    'received': 'diagnosing',
    'diagnosing': 'in_progress',
    'in_progress': 'ready',
    'ready': 'delivered',
  };

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    try {
      final order = await _service.getById(widget.orderId);
      if (mounted) {
        setState(() {
          _order = order;
          _error = order == null ? 'أمر الخدمة غير موجود' : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _transition(String toStatus) async {
    try {
      await _service.transitionStatus(
        orderId: widget.orderId,
        toStatus: toStatus,
      );
      await _loadOrder();
    } catch (error) {
      _showError('تعذر تغيير الحالة: $error');
    }
  }

  Future<void> _post() async {
    try {
      await _service.postServiceOrder(orderId: widget.orderId);
      await _loadOrder();
      _showSuccess('تم ترحيل أمر الخدمة محاسبياً');
    } catch (error) {
      _showError('تعذر الترحيل: $error');
    }
  }

  Future<void> _cancel() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء أمر الخدمة'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'سبب الإلغاء',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء الأمر'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || reason.isEmpty) return;
    try {
      await _service.cancelServiceOrder(
        orderId: widget.orderId,
        reason: reason,
      );
      await _loadOrder();
      _showSuccess('تم إلغاء أمر الخدمة مع حفظ القيد الأصلي والعكس');
    } catch (error) {
      _showError('تعذر الإلغاء: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل أمر الخدمة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || order == null
              ? Center(child: Text(_error ?? 'أمر الخدمة غير موجود'))
              : RefreshIndicator(
                  onRefresh: _loadOrder,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summaryCard(order),
                      const SizedBox(height: 12),
                      _actionCard(order),
                      const SizedBox(height: 12),
                      _financialCard(order),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard(ServiceOrder order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.orderNumber,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('الحالة: ${_statusLabel(order.status)}'),
            Text('الأولوية: ${order.priority}'),
            Text('تاريخ الاستلام: ${_shortDate(order.receivedAt)}'),
            if (order.notes?.trim().isNotEmpty == true) Text('ملاحظات: ${order.notes}'),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(ServiceOrder order) {
    final nextStatus = _nextStatuses[order.status];
    final canPost = !order.isPosted && ServiceOrderStatusPolicy.canPost(order.status);
    final canCancel = !ServiceOrderStatusPolicy.isTerminal(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (nextStatus != null)
              FilledButton.icon(
                onPressed: () => _transition(nextStatus),
                icon: const Icon(Icons.arrow_forward),
                label: Text('تغيير إلى ${_statusLabel(nextStatus)}'),
              ),
            if (canPost)
              FilledButton.icon(
                onPressed: _post,
                icon: const Icon(Icons.account_balance),
                label: const Text('ترحيل محاسبي'),
              ),
            if (canCancel)
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _financialCard(ServiceOrder order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الملخص المالي', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _amountRow('الإجمالي', order.total, order.currencyCode),
            _amountRow('المدفوع', order.paidAmount, order.currencyCode),
            _amountRow('المتبقي', order.remaining, order.currencyCode),
            if (order.isPosted)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified, color: AppColors.success),
                title: Text('تم الترحيل مع الاحتفاظ بسجل التدقيق'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _amountRow(String label, double amount, String currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$currency ${amount.toStringAsFixed(2)}'),
        ],
      ),
    );
  }
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _statusLabel(String status) {
  const labels = {
    'draft': 'مسودة',
    'received': 'مستلم',
    'diagnosing': 'تشخيص',
    'in_progress': 'قيد التنفيذ',
    'ready': 'جاهز',
    'delivered': 'تم التسليم',
    'cancelled': 'ملغي',
  };
  return labels[status] ?? status;
}

Color _statusColor(String status) {
  const colors = {
    'draft': Colors.grey,
    'received': Colors.blue,
    'diagnosing': Colors.deepPurple,
    'in_progress': Colors.orange,
    'ready': Colors.teal,
    'delivered': AppColors.success,
    'cancelled': AppColors.error,
  };
  return colors[status] ?? AppColors.primary;
}
