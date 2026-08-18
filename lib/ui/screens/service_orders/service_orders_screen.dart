import 'package:flutter/material.dart';

import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/core/service/service_order_status_policy.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/datasources/services/service_order_service.dart';
import 'package:firstpro/data/models/service_order_device_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';
import 'package:firstpro/data/models/service_payment_model.dart';
import 'package:firstpro/data/models/service_warranty_model.dart';

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
  final _cashBoxService = locator<CashBoxService>();
  ServiceOrder? _order;
  List<ServiceOrderDevice> _devices = const [];
  List<ServiceWarranty> _warranties = const [];
  List<ServicePayment> _payments = const [];
  List<Map<String, dynamic>> _cashBoxes = const [];
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
      if (order != null) {
        final related = await Future.wait([
          _service.getDevices(widget.orderId),
          _service.getWarranties(widget.orderId),
          _service.getPayments(widget.orderId),
          _cashBoxService.getAllCashBoxes(),
        ]);
        _devices = related[0] as List<ServiceOrderDevice>;
        _warranties = related[1] as List<ServiceWarranty>;
        _payments = related[2] as List<ServicePayment>;
        _cashBoxes = related[3] as List<Map<String, dynamic>>;
      }
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

  Future<void> _addDevice() async {
    final type = TextEditingController();
    final brand = TextEditingController();
    final model = TextEditingController();
    final serial = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('إضافة جهاز'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: type, decoration: const InputDecoration(labelText: 'نوع الجهاز *')),
                  TextField(controller: brand, decoration: const InputDecoration(labelText: 'العلامة التجارية')),
                  TextField(controller: model, decoration: const InputDecoration(labelText: 'الموديل')),
                  TextField(controller: serial, decoration: const InputDecoration(labelText: 'الرقم التسلسلي')),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),
              FilledButton(
                onPressed: () {
                  if (type.text.trim().isEmpty) {
                    setState(() => error = 'نوع الجهاز مطلوب');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'type': type.text.trim(),
                    'brand': brand.text.trim(),
                    'model': model.text.trim(),
                    'serial': serial.text.trim(),
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
    type.dispose();
    brand.dispose();
    model.dispose();
    serial.dispose();
    if (values == null) return;
    try {
      await _service.addDevice(
        device: ServiceOrderDevice(
          serviceOrderId: widget.orderId,
          deviceType: values['type']!,
          brand: values['brand']!.isEmpty ? null : values['brand'],
          model: values['model']!.isEmpty ? null : values['model'],
          serialNumber: values['serial']!.isEmpty ? null : values['serial'],
        ),
      );
      await _loadOrder();
      _showSuccess('تمت إضافة الجهاز');
    } catch (error) {
      _showError('تعذر إضافة الجهاز: $error');
    }
  }

  Future<void> _addWarranty() async {
    final type = TextEditingController(text: 'repair');
    final days = TextEditingController(text: '90');
    final terms = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('إضافة ضمان'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: type, decoration: const InputDecoration(labelText: 'نوع الضمان')),
                  TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'مدة الضمان بالأيام *'),
                  ),
                  TextField(
                    controller: terms,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الشروط'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),
              FilledButton(
                onPressed: () {
                  final parsedDays = int.tryParse(days.text.trim());
                  if (parsedDays == null || parsedDays <= 0) {
                    setState(() => error = 'مدة الضمان يجب أن تكون رقماً موجباً');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'type': type.text.trim().isEmpty ? 'repair' : type.text.trim(),
                    'days': parsedDays.toString(),
                    'terms': terms.text.trim(),
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
    type.dispose();
    days.dispose();
    terms.dispose();
    if (values == null) return;
    final startsAt = DateTime.now();
    try {
      await _service.addWarranty(
        warranty: ServiceWarranty(
          serviceOrderId: widget.orderId,
          serviceOrderLineId: null,
          warrantyType: values['type']!,
          startsAt: startsAt,
          endsAt: startsAt.add(Duration(days: int.parse(values['days']!))),
          terms: values['terms']!.isEmpty ? null : values['terms'],
        ),
      );
      await _loadOrder();
      _showSuccess('تمت إضافة الضمان');
    } catch (error) {
      _showError('تعذر إضافة الضمان: $error');
    }
  }

  Future<void> _addPayment() async {
    final order = _order;
    if (order == null) return;
    final compatibleBoxes = _cashBoxes
        .where((box) => (box['currency'] as String? ?? order.currencyCode) == order.currencyCode)
        .toList();
    final amount = TextEditingController();
    final method = TextEditingController(text: 'cash');
    final rate = TextEditingController(text: '1.0');
    final reference = TextEditingController();
    int? selectedCashBoxId = compatibleBoxes.isEmpty ? null : compatibleBoxes.first['id'] as int?;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('تسجيل دفعة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('العملة: ${order.currencyCode}'),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ * (المتبقي ${order.remaining.toStringAsFixed(2)})',
                    ),
                  ),
                  TextField(controller: method, decoration: const InputDecoration(labelText: 'طريقة الدفع')),
                  TextField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر الصرف إلى العملة الأساسية *'),
                  ),
                  DropdownButtonFormField<int>(
                    value: selectedCashBoxId,
                    decoration: const InputDecoration(labelText: 'صندوق النقد *'),
                    items: compatibleBoxes
                        .map((box) => DropdownMenuItem<int>(
                              value: box['id'] as int,
                              child: Text('${box['name']} (${box['currency']})'),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => selectedCashBoxId = value),
                  ),
                  TextField(controller: reference, decoration: const InputDecoration(labelText: 'رقم المرجع')),
                  if (compatibleBoxes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('لا يوجد صندوق نقد مطابق للعملة', style: TextStyle(color: Colors.red)),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),
              FilledButton(
                onPressed: () {
                  final parsedAmount = double.tryParse(amount.text.trim());
                  final parsedRate = double.tryParse(rate.text.trim());
                  if (parsedAmount == null || parsedAmount <= 0) {
                    setState(() => error = 'المبلغ يجب أن يكون موجباً');
                    return;
                  }
                  if (parsedRate == null || parsedRate <= 0) {
                    setState(() => error = 'سعر الصرف يجب أن يكون موجباً');
                    return;
                  }
                  if (selectedCashBoxId == null) {
                    setState(() => error = 'اختر صندوق نقد صالحاً');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'amount': parsedAmount,
                    'method': method.text.trim().isEmpty ? 'cash' : method.text.trim(),
                    'rate': parsedRate,
                    'cashBoxId': selectedCashBoxId,
                    'reference': reference.text.trim(),
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
    amount.dispose();
    method.dispose();
    rate.dispose();
    reference.dispose();
    if (values == null) return;
    try {
      await _service.createPayment(
        payment: ServicePayment(
          serviceOrderId: widget.orderId,
          paymentMethod: values['method'] as String,
          amount: values['amount'] as double,
          currencyCode: order.currencyCode,
          exchangeRate: values['rate'] as double,
          cashBoxId: values['cashBoxId'] as int,
          referenceNumber: (values['reference'] as String).isEmpty
              ? null
              : values['reference'] as String,
          paymentDate: DateTime.now(),
        ),
      );
      await _loadOrder();
      _showSuccess('تم حفظ الدفعة كمسودة؛ يمكنك ترحيلها من سجل الدفعات');
    } catch (error) {
      _showError('تعذر تسجيل الدفعة: $error');
    }
  }

  Future<void> _postPayment(int paymentId) async {
    try {
      await _service.postPayment(paymentId: paymentId);
      await _loadOrder();
      _showSuccess('تم ترحيل الدفعة محاسبياً');
    } catch (error) {
      _showError('تعذر ترحيل الدفعة: $error');
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
                      const SizedBox(height: 12),
                      _relatedRecordsCard(),
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
            if (!order.isPosted && !ServiceOrderStatusPolicy.isTerminal(order.status)) ...[
              OutlinedButton.icon(
                onPressed: _addDevice,
                icon: const Icon(Icons.phone_android),
                label: const Text('إضافة جهاز'),
              ),
              OutlinedButton.icon(
                onPressed: _addWarranty,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('إضافة ضمان'),
              ),
              OutlinedButton.icon(
                onPressed: _addPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تسجيل دفعة'),
              ),
            ],
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

  Widget _relatedRecordsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('السجلات المرتبطة', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _recordHeader(Icons.devices_other, 'الأجهزة', _devices.length),
            ..._devices.map((device) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.phone_android),
                  title: Text(device.deviceType),
                  subtitle: Text(
                    [device.brand, device.model, device.serialNumber]
                        .where((value) => value != null && value!.trim().isNotEmpty)
                        .map((value) => value!)
                        .join(' • '),
                  ),
                )),
            _recordHeader(Icons.verified_user_outlined, 'الضمانات', _warranties.length),
            ..._warranties.map((warranty) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    warranty.endsAt.isBefore(DateTime.now())
                        ? Icons.warning_amber
                        : Icons.verified,
                    color: warranty.endsAt.isBefore(DateTime.now())
                        ? Colors.orange
                        : AppColors.success,
                  ),
                  title: Text(warranty.warrantyType),
                  subtitle: Text(
                    '${_shortDate(warranty.startsAt)} - ${_shortDate(warranty.endsAt)} • ${warranty.status}',
                  ),
                )),
            _recordHeader(Icons.payments_outlined, 'الدفعات', _payments.length),
            ..._payments.map((payment) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    payment.isPosted ? Icons.verified : Icons.pending,
                    color: payment.isPosted ? AppColors.success : Colors.orange,
                  ),
                  title: Text(
                    '${payment.currencyCode} ${payment.amount.toStringAsFixed(2)}',
                  ),
                  subtitle: Text(
                    '${payment.paymentMethod} • ${_shortDate(payment.paymentDate)}',
                  ),
                  trailing: payment.isPosted
                      ? const Text('مرحّل')
                      : TextButton(
                          onPressed: payment.id == null ? null : () => _postPayment(payment.id!),
                          child: const Text('ترحيل'),
                        ),
                )),
            if (_devices.isEmpty && _warranties.isEmpty && _payments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد سجلات مرتبطة بعد'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recordHeader(IconData icon, String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text('$label ($count)', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
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
