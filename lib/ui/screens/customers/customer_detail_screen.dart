import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../core/services/invoice_pdf_service.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/datasources/repositories/invoice_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/models/customer_model.dart';
import '../settings/bluetooth_printer_settings_screen.dart';
import 'edit_customer_sheet.dart';

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

  // Period filter state: 0=all, 1=daily, 2=monthly, 3=yearly
  int _periodFilter = 3; // default = الجميع

  // Sort order: false=ascending (oldest first), true=descending (newest first)
  bool _sortDescending = false;

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
          color = AppColors.secondary; credit = total; filterKey = 'purchases';
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

      // Discover unlinked vouchers across ALL currencies (customer is
      // multi-currency, so we must check receivable accounts for all).
      final allCustomerAccounts = await customerRepo.getCustomerReceivableAccountsAllCurrencies();
      final customerAccountIds = allCustomerAccounts.map((a) => a['id']).toList();

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
          case 'outgoing_transfer':
            typeAr = 'حوالة صادرة'; icon = Icons.send; color = AppColors.warning;
            debit = totalAmount; filterKey = 'outgoing_transfer'; break;
          case 'incoming_transfer':
            typeAr = 'حوالة وارده'; icon = Icons.download; color = AppColors.info;
            credit = totalAmount; filterKey = 'incoming_transfer'; break;
          case 'settlement':
          case 'compound':
            // For settlement/compound vouchers, the debit/credit direction
            // depends on the voucher_items. Look up the actual effect on the
            // customer's receivable account (code 12xx).
            typeAr = voucherType == 'settlement' ? 'قيد عام' : 'قيد متعدد';
            icon = voucherType == 'settlement' ? Icons.balance : Icons.dynamic_feed;
            color = voucherType == 'settlement' ? AppColors.info : AppColors.accentBlue;
            filterKey = voucherType == 'settlement' ? 'general_entry' : 'compound_entry';
            // Determine direction from voucher_items
            final vId = v['id'];
            try {
              final vItems = await locator<CashBoxService>().getVoucherItems(vId as int);
              for (final vi in vItems) {
                final viAccountId = vi['account_id'] as int?;
                if (viAccountId != null && customerAccountIds.contains(viAccountId)) {
                  final viDebit = MoneyHelper.readMoney(vi['debit']);
                  final viCredit = MoneyHelper.readMoney(vi['credit']);
                  debit += viDebit;
                  credit += viCredit;
                }
              }
            } catch (_) {
              // Fallback: assume credit (له) as default direction
              credit = totalAmount;
            }
            break;
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

    // Calculate running balance for ALL movements chronologically, per currency
    final currencyRunBal = <String, double>{};
    for (final m in movements) {
      final currency = m['currency'] as String? ?? 'YER';
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      currencyRunBal[currency] = (currencyRunBal[currency] ?? 0.0) + credit - debit;
      m['running_balance'] = currencyRunBal[currency];
    }

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

    // Apply period filter
    if (_periodFilter != 3) {
      final now = DateTime.now();
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String;
        try {
          final date = DateTime.parse(dateStr);
          switch (_periodFilter) {
            case 0: // يومي - today
              return date.year == now.year && date.month == now.month && date.day == now.day;
            case 1: // شهري - current month
              return date.year == now.year && date.month == now.month;
            case 2: // سنوي - current year
              return date.year == now.year;
            default:
              return true;
          }
        } catch (_) { return true; }
      }).toList();
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

    // Apply sort order
    if (_sortDescending) {
      filtered = filtered.reversed.toList();
    }

    // Preserve running balance from full calculation (_allMovements)
    // instead of recalculating from filtered subset.
    // The running balance must reflect the true cumulative position at each
    // point in time, including transactions that are hidden by filters.
    final allBalances = <String, double>{};
    for (final m in _allMovements) {
      final mId = m['id'] as String?;
      if (mId != null) {
        allBalances[mId] = MoneyHelper.readMoney(m['running_balance']);
      }
    }
    for (final m in filtered) {
      final mId = m['id'] as String?;
      if (mId != null && allBalances.containsKey(mId)) {
        m['running_balance'] = allBalances[mId];
      }
    }

    // Calculate totals from filtered movements
    double totalDebit = 0.0, totalCredit = 0.0;
    for (final m in filtered) {
      totalDebit += MoneyHelper.readMoney(m['debit']);
      totalCredit += MoneyHelper.readMoney(m['credit']);
    }

    // Compute net balance from ALL movements (for the selected currency), not just filtered
    double netBalance = 0.0;
    for (final m in _allMovements) {
      if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
        final mCurrency = m['currency'] as String? ?? 'YER';
        if (mCurrency != _selectedCurrency) continue;
      }
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      netBalance += credit - debit;
    }

    setState(() {
      _filteredMovements = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = netBalance;
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
                        Navigator.pop(ctx);
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
                const SizedBox(height: 16),
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

  // ── Edit Customer ──────────────────────────────────────────────
  Future<void> _showEditCustomerSheet() async {
    final customer = _freshCustomer ?? widget.customer;
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => EditCustomerSheet(customer: customer),
    );
    // If the edit was successful, reload data
    if (result == true) {
      _loadData();
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
    // Use the computed net balance for the selected currency instead of
    // the stored single-currency balance/balance_type fields.
    final isDebit = _netBalance < 0;

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Modern print button
          Container(
            margin: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
            child: Material(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _printReport,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('طباعة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Modern export button
          Container(
            margin: const EdgeInsets.only(left: 4, right: 8, top: 8, bottom: 8),
            child: Material(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _exportToExcel,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sim_card_download_outlined, size: 18, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('تصدير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                          '${_netBalance.abs().toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDebit ? AppColors.error : AppColors.success).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isDebit ? 'عليه' : (_netBalance > 0 ? 'له' : 'متساوي'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Period Filter RadioButtons ──────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textHint),
                const SizedBox(width: 8),
                _buildPeriodChip('اليوم', 0),
                const SizedBox(width: 6),
                _buildPeriodChip('هذا الشهر', 1),
                const SizedBox(width: 6),
                _buildPeriodChip('هذه السنة', 2),
                const SizedBox(width: 6),
                _buildPeriodChip('الكل', 3),
              ],
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
                const SizedBox(width: 6),
                // Sort order toggle
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: _sortDescending ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                    color: _sortDescending ? AppColors.primary.withOpacity(0.08) : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        setState(() => _sortDescending = !_sortDescending);
                        _applyFilters();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Tooltip(
                        message: _sortDescending ? 'ترتيب تنازلي' : 'ترتيب تصاعدي',
                        child: Icon(
                          _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 16,
                          color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showEditCustomerSheet,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary),
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
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
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
                        )
                      ),
          ),
        ],
      ),

      // ── Bottom Balance Bar — Three separate fields: له / عليه / الرصيد ─
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.surface : AppColors.darkSurface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, -2), blurRadius: 8)],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // ── له (Credit) ──────────────────────────────
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.25), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('له', style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 12,
                        )),
                        const SizedBox(height: 4),
                        Text(
                          '${_totalCredit.toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900, color: AppColors.success, fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // ── عليه (Debit) ─────────────────────────────
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.25), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('عليه', style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 12,
                        )),
                        const SizedBox(height: 4),
                        Text(
                          '${_totalDebit.toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900, color: AppColors.error, fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // ── الرصيد (Net Balance) — direction by color ─
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _netBalance >= 0
                            ? [AppColors.success.withOpacity(0.15), AppColors.success.withOpacity(0.05)]
                            : [AppColors.error.withOpacity(0.15), AppColors.error.withOpacity(0.05)],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _netBalance >= 0 ? AppColors.success.withOpacity(0.4) : AppColors.error.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _netBalance >= 0 ? Icons.trending_up : Icons.trending_down,
                              size: 13,
                              color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                            ),
                            const SizedBox(width: 4),
                            Text('الرصيد', style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                              fontSize: 12,
                            )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_netBalance.abs().toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Period filter chip builder ───────────────────────────────
  Widget _buildPeriodChip(String label, int value) {
    final isSelected = _periodFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _periodFilter = value);
        _applyFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : (Theme.of(context).brightness == Brightness.light ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Print single transaction based on its type
  void _printSingleTransaction(Map<String, dynamic> m) async {
    final source = m['source'] as String? ?? '';
    final type = m['type'] as String? ?? '';
    final customer = _freshCustomer ?? widget.customer;

    try {
      if (source == 'invoice') {
        // Print invoice using InvoicePdfService
        final invoiceId = m['id']?.toString() ?? '';
        if (invoiceId.isEmpty) throw Exception('معرف الفاتورة غير موجود');

        final invoiceRepo = locator<InvoiceRepository>();
        final invoice = await invoiceRepo.getInvoiceById(invoiceId);
        if (invoice == null) throw Exception('لم يتم العثور على بيانات الفاتورة');

        final items = await invoiceRepo.getInvoiceItems(invoiceId);
        final pdfService = InvoicePdfService();
        final pdfBytes = await pdfService.generateSalesInvoicePdf(invoice, items);
        await Printing.sharePdf(bytes: pdfBytes, filename: 'invoice_${invoiceId}.pdf');
      } else if (source == 'voucher') {
        // Print voucher as a voucher document
        final rawId = (m['id'] ?? '').toString().replaceAll('v_', '');
        final voucherId = int.tryParse(rawId);
        if (voucherId == null) throw Exception('معرف السند غير موجود');

        final cashBoxService = locator<CashBoxService>();
        final db = await locator<DatabaseHelper>().database;
        final voucherRows = await db.query('vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
        if (voucherRows.isEmpty) throw Exception('لم يتم العثور على بيانات السند');
        final voucherData = voucherRows.first;
        final voucherItems = await cashBoxService.getVoucherItems(voucherId);

        final pdfBytes = await _generateVoucherPdf(voucherData, voucherItems, customer.name);
        await Printing.sharePdf(bytes: pdfBytes, filename: 'voucher_$voucherId.pdf');
      } else if (source == 'opening_balance') {
        // Print opening balance as a receipt
        final pdfBytes = await _generateSingleTransactionPdf(m, customer.name);
        await Printing.sharePdf(bytes: pdfBytes, filename: 'opening_balance.pdf');
      } else {
        // Fallback: print as single transaction
        final pdfBytes = await _generateSingleTransactionPdf(m, customer.name);
        await Printing.sharePdf(bytes: pdfBytes, filename: 'transaction.pdf');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة: ${e.toString().replaceFirst('Exception: ', '')}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Generate a PDF for a single voucher document.
  Future<Uint8List> _generateVoucherPdf(
    Map<String, dynamic> voucherData,
    List<Map<String, dynamic>> items,
    String customerName,
  ) async {
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      arabicFont = pw.Font.ttf(fontData);
    } catch (_) {}

    final businessName = await locator<ReferenceDataRepository>().getSetting('business_name') ?? 'الأول برو المحاسبي';
    final businessPhone = await locator<ReferenceDataRepository>().getSetting('business_phone') ?? '';

    final voucherType = voucherData['voucher_type'] as String? ?? '';
    final voucherNumber = voucherData['voucher_number']?.toString() ?? '';
    final dateStr = voucherData['date'] as String? ?? voucherData['created_at'] as String? ?? '';
    final currency = voucherData['currency'] as String? ?? 'YER';
    final currencySymbol = currency == 'USD' ? r'$' : (currency == 'SAR' ? 'ر.س' : 'ر.ي');
    final description = voucherData['description'] as String? ?? '';
    final totalAmount = MoneyHelper.readMoney(voucherData['total_amount']);

    String voucherTypeAr;
    switch (voucherType) {
      case 'receipt': voucherTypeAr = 'سند قبض'; break;
      case 'payment': voucherTypeAr = 'سند صرف'; break;
      case 'settlement': voucherTypeAr = 'قيد عام'; break;
      case 'compound': voucherTypeAr = 'قيد متعدد'; break;
      default: voucherTypeAr = 'سند';
    }

    String formattedDate = dateStr;
    try { final dt = DateTime.parse(dateStr); formattedDate = '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'; } catch (_) {}

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: arabicFont ?? pw.Font.helvetica(), bold: arabicFont ?? pw.Font.helveticaBold()),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Text(businessName, style: pw.TextStyle(font: arabicFont, fontSize: 18, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.12, 0.42, 0.14))),
              if (businessPhone.isNotEmpty) pw.Text('هاتف: $businessPhone', style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Divider(thickness: 2, color: const PdfColor(0.12, 0.42, 0.14)),
              pw.SizedBox(height: 12),
              // Title
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: pw.BoxDecoration(color: PdfColor(0.12, 0.42, 0.14), borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text(voucherTypeAr, style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor(1, 1, 1))),
                ),
              ),
              pw.SizedBox(height: 16),
              // Info
              _pdfInfoRow('رقم السند', voucherNumber, arabicFont),
              _pdfInfoRow('التاريخ', formattedDate, arabicFont),
              _pdfInfoRow('العميل', customerName, arabicFont),
              _pdfInfoRow('العملة', currency, arabicFont),
              if (description.isNotEmpty) _pdfInfoRow('البيان', description, arabicFont),
              pw.SizedBox(height: 16),
              // Items table
              pw.Table(
                border: pw.TableBorder.all(color: const PdfColor(0.8, 0.8, 0.8), width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor(0.12, 0.42, 0.14)),
                    children: [
                      _pdfCell('الحساب', arabicFont, bold: true, textColor: const PdfColor(1, 1, 1)),
                      _pdfCell('مدين', arabicFont, bold: true, textColor: const PdfColor(1, 1, 1)),
                      _pdfCell('دائن', arabicFont, bold: true, textColor: const PdfColor(1, 1, 1)),
                    ],
                  ),
                  ...items.map((item) => pw.TableRow(children: [
                    _pdfCell(item['account_name']?.toString() ?? item['account_id']?.toString() ?? '', arabicFont),
                    _pdfCell(MoneyHelper.readMoney(item['debit']) > 0 ? '$currencySymbol ${CurrencyFormatter.formatValue(MoneyHelper.readMoney(item['debit']))}' : '', arabicFont),
                    _pdfCell(MoneyHelper.readMoney(item['credit']) > 0 ? '$currencySymbol ${CurrencyFormatter.formatValue(MoneyHelper.readMoney(item['credit']))}' : '', arabicFont),
                  ])),
                ],
              ),
              pw.SizedBox(height: 16),
              // Total
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85)), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الإجمالي', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('$currencySymbol ${CurrencyFormatter.formatValue(totalAmount)}', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.12, 0.42, 0.14))),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),
              // Signature fields
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: ['المدير', 'المحاسب', 'المستلم'].map((label) => pw.Expanded(
                  child: pw.Column(children: [
                    pw.Container(height: 40, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor(0.5, 0.5, 0.5))))),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: pw.TextStyle(font: arabicFont, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ]),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  /// Generate a PDF for a single transaction (opening balance, etc.).
  Future<Uint8List> _generateSingleTransactionPdf(
    Map<String, dynamic> m,
    String customerName,
  ) async {
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      arabicFont = pw.Font.ttf(fontData);
    } catch (_) {}

    final businessName = await locator<ReferenceDataRepository>().getSetting('business_name') ?? 'الأول برو المحاسبي';
    final businessPhone = await locator<ReferenceDataRepository>().getSetting('business_phone') ?? '';

    final typeAr = m['type_ar'] as String? ?? '';
    final description = m['description'] as String? ?? '';
    final debit = MoneyHelper.readMoney(m['debit']);
    final credit = MoneyHelper.readMoney(m['credit']);
    final currency = m['currency'] as String? ?? 'YER';
    final currencySymbol = currency == 'USD' ? r'$' : (currency == 'SAR' ? 'ر.س' : 'ر.ي');
    final dateStr = m['date'] as String? ?? '';

    String formattedDate = dateStr;
    try { final dt = DateTime.parse(dateStr); formattedDate = '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'; } catch (_) {}

    final amount = debit > 0 ? debit : credit;
    final direction = debit > 0 ? 'عليه' : 'له';

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: arabicFont ?? pw.Font.helvetica(), bold: arabicFont ?? pw.Font.helveticaBold()),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Text(businessName, style: pw.TextStyle(font: arabicFont, fontSize: 18, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.12, 0.42, 0.14))),
              if (businessPhone.isNotEmpty) pw.Text('هاتف: $businessPhone', style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Divider(thickness: 2, color: const PdfColor(0.12, 0.42, 0.14)),
              pw.SizedBox(height: 12),
              // Title
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: pw.BoxDecoration(color: PdfColor(0.12, 0.42, 0.14), borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text(typeAr, style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor(1, 1, 1))),
                ),
              ),
              pw.SizedBox(height: 16),
              // Info
              _pdfInfoRow('العميل', customerName, arabicFont),
              _pdfInfoRow('التاريخ', formattedDate, arabicFont),
              _pdfInfoRow('العملة', currency, arabicFont),
              if (description.isNotEmpty) _pdfInfoRow('البيان', description, arabicFont),
              pw.SizedBox(height: 20),
              // Amount box
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: const PdfColor(0.85, 0.85, 0.85)),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('المبلغ', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text('$currencySymbol ${CurrencyFormatter.formatValue(amount)}', style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.12, 0.42, 0.14))),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: debit > 0 ? const PdfColor(0.8, 0, 0) : const PdfColor(0.12, 0.42, 0.14),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(direction, style: pw.TextStyle(font: arabicFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor(1, 1, 1))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),
              // Signature fields
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: ['المدير', 'المحاسب', 'المستلم'].map((label) => pw.Expanded(
                  child: pw.Column(children: [
                    pw.Container(height: 40, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor(0.5, 0.5, 0.5))))),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: pw.TextStyle(font: arabicFont, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ]),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  // PDF helper methods
  static pw.Widget _pdfInfoRow(String label, String value, pw.Font? font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 11, color: const PdfColor(0.4, 0.4, 0.4))),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 11, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }

  static pw.Widget _pdfCell(String text, pw.Font? font, {bool bold = false, PdfColor? textColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: textColor)),
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
