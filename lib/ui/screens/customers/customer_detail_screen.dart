import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/models/customer_model.dart';
import '../settings/bluetooth_printer_settings_screen.dart';

/// Customer Detail / Ledger Screen — Modern Professional Design
/// Displays all financial movements for a specific customer with
/// filtering, search, statistics, and voucher creation capabilities.
class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allMovements = [];
  List<Map<String, dynamic>> _filteredMovements = [];

  // Filter state
  int _selectedFilterIndex = 0;
  String? _selectedCurrency = 'YER';
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  // Search controller
  final TextEditingController _searchController = TextEditingController();

  // Statistics
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  // Customer data (refreshable)
  Customer? _freshCustomer;

  // Cash boxes for voucher dialog
  List<Map<String, dynamic>> _cashBoxes = [];

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'جميع الحركات والفواتير'),
    _FilterTab(key: 'opening_balance', label: 'رصيد افتتاحي'),
    _FilterTab(key: 'debit', label: 'عليه'),
    _FilterTab(key: 'credit', label: 'له'),
    _FilterTab(key: 'payment_voucher', label: 'سند صرف'),
    _FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
    _FilterTab(key: 'general_entry', label: 'قيد عام'),
    _FilterTab(key: 'outgoing_transfer', label: 'حوالة صادرة'),
    _FilterTab(key: 'incoming_transfer', label: 'حوالة وارده'),
    _FilterTab(key: 'sales', label: 'مبيعات فقط'),
    _FilterTab(key: 'purchases', label: 'مشتريات فقط'),
    _FilterTab(key: 'returns', label: 'مرتجع'),
    _FilterTab(key: 'compound_entry', label: 'قيد متعدد'),
  ];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  @override
  void initState() {
    super.initState();
    _freshCustomer = widget.customer;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final customerMap = await locator<CustomerRepository>().getCustomerById(widget.customer.id!);
      if (customerMap != null) {
        _freshCustomer = Customer.fromMap(customerMap);
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadData [refreshCustomer]: $e');
    }

    try {
      _cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadData [cashBoxes]: $e');
    }

    try {
      await _loadMovements();
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadData [movements]: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadMovements() async {
    final customerId = widget.customer.id!;
    final customerRepo = locator<CustomerRepository>();
    final movements = <Map<String, dynamic>>[];

    // 1. Load invoices for this customer
    try {
      final invoices = await customerRepo.getCustomerInvoices(customerId);
      for (final inv in invoices) {
        final type = inv['type'] as String? ?? 'sale';
        final isReturn = (inv['is_return'] as int? ?? 0) == 1;
        final total = MoneyHelper.readMoney(inv['total']);
        final currency = inv['currency'] as String? ?? 'YER';
        final createdAt = inv['created_at'] as String? ?? DateTime.now().toIso8601String();

        String effectiveType, typeAr, filterKey;
        IconData icon; Color color;
        double debit = 0.0, credit = 0.0;

        if (type == 'sale' && !isReturn) {
          effectiveType = 'sale'; typeAr = 'فاتورة مبيعات'; icon = Icons.receipt_long;
          color = AppColors.primary; debit = total; filterKey = 'sales';
        } else if (type == 'sale' && isReturn) {
          effectiveType = 'sale_return'; typeAr = 'مرتجع مبيعات'; icon = Icons.keyboard_return;
          color = AppColors.warning; credit = total; filterKey = 'returns';
        } else if (type == 'purchase' && !isReturn) {
          effectiveType = 'purchase'; typeAr = 'فاتورة مشتريات'; icon = Icons.shopping_cart;
          color = AppColors.accentOrange; credit = total; filterKey = 'purchases';
        } else if (type == 'purchase' && isReturn) {
          effectiveType = 'purchase_return'; typeAr = 'مرتجع مشتريات'; icon = Icons.keyboard_return;
          color = AppColors.accentPink; debit = total; filterKey = 'returns';
        } else {
          effectiveType = type; typeAr = 'فاتورة'; icon = Icons.receipt;
          color = AppColors.textSecondary; debit = total; filterKey = 'all';
        }

        final remaining = MoneyHelper.readMoney(inv['remaining']);
        final desc = '$typeAr - ${inv['id'] ?? ''}${remaining > 0 ? ' (متبقي: ${remaining.toStringAsFixed(2)})' : ''}';

        movements.add({
          'id': inv['id'], 'date': createdAt, 'type': effectiveType, 'type_ar': typeAr,
          'filter_key': filterKey, 'icon': icon, 'color': color, 'description': desc,
          'debit': debit, 'credit': credit, 'currency': currency,
          'source': 'invoice', 'voucher_type': null,
        });
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadMovements [invoices]: $e');
    }

    // 2. Load vouchers
    try {
      final voucherRows = await customerRepo.getCustomerVouchers(customerId);

      final customerCurrency = _freshCustomer?.currency ?? widget.customer.currency ?? 'YER';
      final customerAccounts = await customerRepo.getCustomerReceivableAccounts(customerCurrency);
      final customerAccountIds = customerAccounts.map((a) => a['id']).toList();

      if (customerAccountIds.isNotEmpty) {
        final unlinkedVouchers = await customerRepo.getUnlinkedVouchers();
        for (final v in unlinkedVouchers) {
          final voucherId = v['id'] as int?;
          if (voucherId == null) continue;
          try {
            final items = await locator<CashBoxService>().getVoucherItems(voucherId);
            for (final item in items) {
              final accountId = item['account_id'] as int?;
              if (accountId != null && customerAccountIds.contains(accountId)) {
                final desc = v['description'] as String? ?? '';
                final customerName = _freshCustomer?.name ?? widget.customer.name;
                if (desc.contains(customerName)) {
                  voucherRows.add(v);
                }
                break;
              }
            }
          } catch (_) {}
        }
      }

      for (final v in voucherRows) {
        final voucherType = v['voucher_type'] as String? ?? '';
        final totalAmount = MoneyHelper.readMoney(v['total_amount']);
        final currency = v['currency'] as String? ?? 'YER';
        final dateStr = v['date'] as String? ?? v['created_at'] as String? ?? DateTime.now().toIso8601String();

        String typeAr, filterKey;
        IconData icon; Color color;
        double debit = 0.0, credit = 0.0;

        switch (voucherType) {
          case 'receipt':
            typeAr = 'سند قبض'; icon = Icons.assignment_turned_in; color = AppColors.success;
            credit = totalAmount; filterKey = 'receipt_voucher'; break;
          case 'payment':
            typeAr = 'سند صرف'; icon = Icons.assignment_return; color = AppColors.error;
            debit = totalAmount; filterKey = 'payment_voucher'; break;
          case 'settlement':
            typeAr = 'قيد عام'; icon = Icons.balance; color = AppColors.info;
            credit = totalAmount; filterKey = 'general_entry'; break;
          case 'compound':
            typeAr = 'قيد متعدد'; icon = Icons.dynamic_feed; color = AppColors.accentBlue;
            debit = totalAmount; filterKey = 'compound_entry'; break;
          default:
            typeAr = 'سند'; icon = Icons.description; color = AppColors.textSecondary;
            debit = totalAmount; filterKey = 'all';
        }

        final description = v['description'] as String? ?? '$typeAr - ${v['voucher_number'] ?? ''}';
        movements.add({
          'id': 'v_${v['id']}', 'date': dateStr, 'type': voucherType, 'type_ar': typeAr,
          'filter_key': filterKey, 'icon': icon, 'color': color, 'description': description,
          'debit': debit, 'credit': credit, 'currency': currency,
          'source': 'voucher', 'voucher_type': voucherType,
        });
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadMovements [vouchers]: $e');
    }

    // 3. Opening balance transactions
    try {
      final customer = _freshCustomer ?? widget.customer;
      final obTransactions = await locator<CustomerRepository>().getCustomerOpeningBalanceTransactions(customerId);

      for (final ob in obTransactions) {
        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ?? ob['created_at'] as String? ?? DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';
        final obCurrency = ob['account_currency'] as String? ?? customer.currency ?? 'YER';

        movements.add({
          'id': 'ob_${ob['id']}', 'date': dateStr, 'type': 'opening_balance', 'type_ar': 'رصيد افتتاحي',
          'filter_key': 'opening_balance', 'icon': Icons.account_balance_wallet, 'color': AppColors.accentBlue,
          'description': description, 'debit': debit, 'credit': credit, 'currency': obCurrency,
          'source': 'opening_balance', 'voucher_type': null,
        });
      }

      // Fallback for legacy data
      if (obTransactions.isEmpty && (customer.balance != 0.0 || (customer.currency?.isNotEmpty ?? false))) {
        double allDebit = 0.0, allCredit = 0.0;
        for (final m in movements) {
          allDebit += MoneyHelper.readMoney(m['debit']);
          allCredit += MoneyHelper.readMoney(m['credit']);
        }
        final customerSignedBalance = customer.balanceType == 'credit' ? customer.balance : -customer.balance;
        final openingAmount = customerSignedBalance - (allCredit - allDebit);

        if (openingAmount.abs() >= 0.005) {
          final obCurrency = customer.currency ?? 'YER';
          final isCredit = openingAmount > 0;
          movements.insert(0, {
            'id': 'opening_balance', 'date': customer.createdAt ?? DateTime.now().toIso8601String(),
            'type': 'opening_balance', 'type_ar': 'رصيد افتتاحي', 'filter_key': 'opening_balance',
            'icon': Icons.account_balance_wallet, 'color': AppColors.accentBlue,
            'description': 'رصيد افتتاحي (${isCredit ? "له" : "عليه"})',
            'debit': isCredit ? 0.0 : openingAmount.abs(), 'credit': isCredit ? openingAmount.abs() : 0.0,
            'currency': obCurrency, 'source': 'opening_balance', 'voucher_type': null,
          });
        }
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen._loadMovements [opening_balance]: $e');
    }

    movements.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    _allMovements = movements;
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = _allMovements.map((m) => Map<String, dynamic>.from(m)).toList();

    // Apply tab filter
    final filterKey = _filterTabs[_selectedFilterIndex].key;
    if (filterKey == 'debit') {
      filtered = filtered.where((m) => MoneyHelper.readMoney(m['debit']) > 0).toList();
    } else if (filterKey == 'credit') {
      filtered = filtered.where((m) => MoneyHelper.readMoney(m['credit']) > 0).toList();
    } else if (filterKey != 'all') {
      filtered = filtered.where((m) => m['filter_key'] == filterKey).toList();
    }

    // Apply currency filter
    if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
      filtered = filtered.where((m) => m['currency'] == _selectedCurrency).toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String;
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_dateRange!.start) && !date.isAfter(_dateRange!.end.add(const Duration(days: 1)));
        } catch (_) { return true; }
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        final desc = (m['description'] as String? ?? '').toLowerCase();
        final typeAr = (m['type_ar'] as String? ?? '').toLowerCase();
        return desc.contains(q) || typeAr.contains(q);
      }).toList();
    }

    // Calculate running balance
    double runningBalance = 0.0, totalDebit = 0.0, totalCredit = 0.0;
    for (final m in filtered) {
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      runningBalance += credit - debit;
      totalDebit += debit;
      totalCredit += credit;
      m['running_balance'] = runningBalance;
    }

    setState(() {
      _filteredMovements = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = runningBalance;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: now,
      initialDateRange: _dateRange, locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) { setState(() => _dateRange = picked); _applyFilters(); }
  }

  void _clearDateRange() { setState(() => _dateRange = null); _applyFilters(); }

  // ── Show filter popup ──────────────────────────────────────────
  void _showFilterPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.filter_list, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('تصفية الحركات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setSheetState(() => _selectedFilterIndex = 0);
                        setState(() => _selectedFilterIndex = 0);
                      },
                      child: Text('الكل', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // All filters as chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_filterTabs.length, (index) {
                    final isSelected = _selectedFilterIndex == index;
                    return ChoiceChip(
                      label: Text(_filterTabs[index].label),
                      selected: isSelected,
                      onSelected: (_) {
                        setSheetState(() => _selectedFilterIndex = index);
                        setState(() => _selectedFilterIndex = index);
                        _applyFilters();
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                      backgroundColor: Theme.of(context).brightness == Brightness.light ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                      selectedColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('تطبيق'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add Voucher Dialog ──────────────────────────────────────────
  Future<void> _showAddVoucherDialog(String voucherType) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int? selectedCashBoxId;
    String selectedCurrency = _selectedCurrency ?? 'YER';
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'العميل', prefixIcon: Icon(Icons.person)),
                  child: Text(_freshCustomer?.name ?? ''),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  decoration: InputDecoration(labelText: 'المبلغ', prefixIcon: const Icon(Icons.attach_money), suffixText: selectedCurrency),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'العملة', prefixIcon: Icon(Icons.currency_exchange)),
                  items: const [
                    DropdownMenuItem(value: 'YER', child: Text('ريال يمني (YER)')),
                    DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (SAR)')),
                    DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (USD)')),
                  ],
                  onChanged: (v) { if (v != null) setDialogState(() => selectedCurrency = v); },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int?>(
                  value: selectedCashBoxId,
                  decoration: const InputDecoration(labelText: 'الصندوق', prefixIcon: Icon(Icons.account_balance_wallet)),
                  items: _cashBoxes.map((cb) => DropdownMenuItem<int?>(value: cb['id'] as int?, child: Text('${cb['name']}'))).toList(),
                  onChanged: (v) { setDialogState(() => selectedCashBoxId = v); },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: voucherType == 'receipt' ? 'بيان سند القبض' : 'بيان سند الصرف',
                    prefixIcon: const Icon(Icons.description),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: isSaving ? null : () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صالح'), backgroundColor: AppColors.error));
                  return;
                }
                if (selectedCashBoxId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الصندوق'), backgroundColor: AppColors.error));
                  return;
                }
                setDialogState(() => isSaving = true);
                try {
                  final autoMappingService = locator<VoucherAutoMappingService>();
                  final dateStr = DateTime.now().toIso8601String().split('T').first;
                  await autoMappingService.createReceiptPaymentVoucher(
                    voucherType: voucherType,
                    entityType: VoucherAutoMappingService.entityCustomer,
                    entityId: _freshCustomer?.id ?? 0,
                    cashBoxId: selectedCashBoxId,
                    amount: amount,
                    currency: selectedCurrency,
                    date: dateStr,
                    description: descriptionController.text.trim().isEmpty
                        ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - ${_freshCustomer?.name}'
                        : descriptionController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(voucherType == 'receipt' ? 'تم إنشاء سند القبض بنجاح' : 'تم إنشاء سند الصرف بنجاح'),
                      backgroundColor: AppColors.success,
                    ));
                    _loadData();
                  }
                } catch (e) {
                  if (context.mounted) {
                    final msg = e.toString().replaceFirst('Exception: ', '');
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(msg.isNotEmpty ? msg : 'حدث خطأ أثناء الحفظ'), backgroundColor: AppColors.error,
                    ));
                  }
                  setDialogState(() => isSaving = false);
                }
              },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(voucherType == 'receipt' ? 'إنشاء سند قبض' : 'إنشاء سند صرف'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    descriptionController.dispose();
  }

  // ── Print / Export ─────────────────────────────────────────────
  void _printReport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('خيارات الطباعة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('إنشاء ملف PDF لكشف الحساب'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () { Navigator.pop(ctx); _generatePdfStatement(); },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.accentBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.bluetooth, color: AppColors.accentBlue),
                ),
                title: const Text('طباعة حرارية بلوتوث', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('طباعة كشف حساب على طابعة حرارية'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () async { Navigator.pop(ctx); await _printBluetoothStatement(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generatePdfStatement() async {
    final customer = _freshCustomer ?? widget.customer;
    try {
      await AccountStatementPdfGenerator.printAccountStatement(
        entityName: customer.name, entityType: 'customer', movements: _filteredMovements,
        totalDebit: _totalDebit, totalCredit: _totalCredit, netBalance: _netBalance,
        balanceLabel: _netBalance > 0 ? 'له' : (_netBalance < 0 ? 'عليه' : 'متساوي'),
        phone: customer.phone, currency: customer.currency ?? 'YER',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء إنشاء كشف الحساب'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _printBluetoothStatement() async {
    final printerService = BluetoothPrinterService.instance;
    final customer = _freshCustomer ?? widget.customer;
    if (!printerService.isConnected) {
      final connected = await printerService.autoConnect();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('الطابعة غير متصلة. يرجى الذهاب إلى الإعدادات لتوصيلها'),
            backgroundColor: AppColors.warning,
            action: SnackBarAction(label: 'الإعدادات', textColor: Colors.white, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothPrinterSettingsScreen()))),
          ));
        }
        return;
      }
    }
    try {
      await printerService.printCustomerStatement({'name': customer.name, 'balance': customer.balance, 'balance_type': customer.balanceType, 'currency': customer.currency});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال كشف الحساب للطابعة الحرارية'), backgroundColor: AppColors.success));
    } on PrinterException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error));
    }
  }

  void _exportToExcel() async {
    final customer = _freshCustomer ?? widget.customer;
    try {
      await ExcelExporter.exportAccountStatementToExcel(
        entityName: customer.name, entityType: 'عميل', movements: _filteredMovements,
        totalDebit: _totalDebit, totalCredit: _totalCredit, netBalance: _netBalance,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء التصدير'), backgroundColor: AppColors.error));
    }
  }

  String _currencySymbol(String? code) {
    switch (code) { case 'SAR': return 'ر.س'; case 'USD': return r'$'; case 'YER': default: return 'ر.ي'; }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final customer = _freshCustomer ?? widget.customer;
    final isDebit = customer.balanceType == 'debit';

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(icon: const Icon(Icons.print), tooltip: 'طباعة', onPressed: _printReport),
          IconButton(icon: const Icon(Icons.file_download), tooltip: 'تصدير إكسل', onPressed: _exportToExcel),
        ],
      ),
      body: Column(
        children: [
          // ── Header Card ────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: DesignSystem.cardShadow(isLight: false),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        customer.name.isNotEmpty ? customer.name[0] : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.name, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [const Icon(Icons.phone, size: 13, color: Colors.white70), const SizedBox(width: 4), Text(customer.phone!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70))]),
                        ],
                      ],
                    ),
                  ),
                  // Balance badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${customer.balance.abs().toStringAsFixed(2)} ${_currencySymbol(customer.currency)}',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDebit ? AppColors.error : AppColors.success).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isDebit ? 'عليه' : (customer.balance > 0 ? 'له' : 'متساوي'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Toolbar: Search + Filters ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                // Search field
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) { setState(() => _searchQuery = v.trim()); _applyFilters(); },
                      decoration: InputDecoration(
                        hintText: 'بحث حركة...',
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); _applyFilters(); })
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Filter button
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: _selectedFilterIndex > 0 ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                    color: _selectedFilterIndex > 0 ? AppColors.primary.withOpacity(0.08) : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _showFilterPopup,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list, size: 18, color: _selectedFilterIndex > 0 ? AppColors.primary : AppColors.textSecondary),
                            if (_selectedFilterIndex > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Date range button
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: _dateRange != null ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                    color: _dateRange != null ? AppColors.primary.withOpacity(0.08) : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _dateRange != null ? _clearDateRange : _pickDateRange,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_dateRange != null ? Icons.event_busy : Icons.date_range, size: 18,
                              color: _dateRange != null ? AppColors.primary : AppColors.textSecondary),
                            if (_dateRange != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${_dateRange!.start.day}/${_dateRange!.start.month}',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Currency dropdown
                Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedCurrency ?? 'YER',
                    underline: const SizedBox.shrink(),
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
                    items: _currencyOptions.map((e) => DropdownMenuItem<String>(value: e.value, child: Text(e.key, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) { if (v != null && v.isNotEmpty) { setState(() => _selectedCurrency = v); _applyFilters(); } },
                  ),
                ),
              ],
            ),
          ),

          // ── Active filter label ────────────────────────────────
          if (_selectedFilterIndex > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              color: isLight ? AppColors.surface : AppColors.darkSurface,
              child: Row(
                children: [
                  Text('الفلتر: ', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_filterTabs[_selectedFilterIndex].label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () { setState(() => _selectedFilterIndex = 0); _applyFilters(); },
                          child: Icon(Icons.close, size: 14, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('${_filteredMovements.length} حركة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                ],
              ),
            ),

          // ── Action buttons row ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('receipt'),
                    icon: const Icon(Icons.assignment_turned_in, size: 16),
                    label: const Text('سند قبض', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success, side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('payment'),
                    icon: const Icon(Icons.assignment_return, size: 16),
                    label: const Text('سند صرف', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Movements List ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMovements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: AppColors.textHint.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text('لا توجد حركات', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80, top: 4),
                        itemCount: _filteredMovements.length,
                        itemBuilder: (context, index) {
                          final m = _filteredMovements[index];
                          return _MovementCard(
                            movement: m,
                            currencySymbol: _currencySymbol(m['currency']),
                            isLight: isLight,
                            onPrint: () {
                              // Print single transaction
                              _printSingleTransaction(m);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),

      // ── Bottom Statistics Bar ──────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.surface : AppColors.darkSurface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, -2), blurRadius: 8)],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // له (credit)
                Expanded(
                  child: _StatItem(label: 'له', value: _totalCredit.toStringAsFixed(2), color: AppColors.success, symbol: _currencySymbol(_selectedCurrency)),
                ),
                Container(width: 1, height: 36, color: AppColors.divider),
                // عليه (debit)
                Expanded(
                  child: _StatItem(label: 'عليه', value: _totalDebit.toStringAsFixed(2), color: AppColors.error, symbol: _currencySymbol(_selectedCurrency)),
                ),
                Container(width: 1, height: 36, color: AppColors.divider),
                // الرصيد (net)
                Expanded(
                  child: _StatItem(
                    label: _netBalance >= 0 ? 'له' : 'عليه',
                    value: _netBalance.abs().toStringAsFixed(2),
                    color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                    symbol: _currencySymbol(_selectedCurrency),
                    isBold: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Print single transaction
  void _printSingleTransaction(Map<String, dynamic> m) {
    final customer = _freshCustomer ?? widget.customer;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('طباعة الحركة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(m['description'] ?? '', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdfStatement(); // Will print filtered movements
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  FILTER TAB MODEL
// ═══════════════════════════════════════════════════════════════════
class _FilterTab {
  final String key;
  final String label;
  const _FilterTab({required this.key, required this.label});
}

// ═══════════════════════════════════════════════════════════════════
//  MOVEMENT CARD — Professional Design
// ═══════════════════════════════════════════════════════════════════
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final String currencySymbol;
  final bool isLight;
  final VoidCallback? onPrint;

  const _MovementCard({required this.movement, required this.currencySymbol, required this.isLight, this.onPrint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = movement['icon'] as IconData;
    final color = movement['color'] as Color;
    final typeAr = movement['type_ar'] as String;
    final description = movement['description'] as String;
    final debit = MoneyHelper.readMoney(movement['debit']);
    final credit = MoneyHelper.readMoney(movement['credit']);
    final runningBalance = MoneyHelper.readMoney(movement['running_balance']);
    final dateStr = movement['date'] as String;

    String formattedDate;
    try {
      final date = DateTime.parse(dateStr);
      formattedDate = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) { formattedDate = dateStr; }

    final balanceColor = runningBalance >= 0 ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLight ? AppColors.border.withOpacity(0.5) : AppColors.darkBorder.withOpacity(0.5), width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isLight ? 0.03 : 0.15), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),

            // Description + date + type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(description, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(formattedDate, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(typeAr, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 10)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Amount + running balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (debit > 0)
                  Text('${debit.toStringAsFixed(2)} $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700))
                else if (credit > 0)
                  Text('${credit.toStringAsFixed(2)} $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700))
                else
                  Text('0.00 $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                const SizedBox(height: 2),
                Text(
                  '${runningBalance.abs().toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: balanceColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),

            // Print button
            const SizedBox(width: 4),
            SizedBox(
              width: 28, height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.print, size: 14, color: AppColors.textHint),
                onPressed: onPrint,
                tooltip: 'طباعة',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STAT ITEM — Professional Design
// ═══════════════════════════════════════════════════════════════════
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String symbol;
  final bool isBold;

  const _StatItem({required this.label, required this.value, required this.color, required this.symbol, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$value $symbol',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
