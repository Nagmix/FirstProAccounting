import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../settings/bluetooth_printer_settings_screen.dart';

/// Employee Detail / Ledger Screen — Modern Professional Design
/// Displays all financial movements for a specific employee with
/// filtering, search, statistics, and voucher creation capabilities.
class EmployeeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

/// Simple data class for filter tab definitions.
class _FilterTab {
  final String key;
  final String label;
  const _FilterTab({required this.key, required this.label});
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allMovements = [];
  List<Map<String, dynamic>> _filteredMovements = [];

  // Filter state
  int _selectedFilterIndex = 0;
  String? _selectedCurrency = 'YER';
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  // Period filter state: 0=daily, 1=monthly, 2=yearly, 3=all
  int _periodFilter = 3; // default = الجميع

  // Sort order: false=ascending (oldest first), true=descending (newest first)
  bool _sortDescending = false;

  // Search controller
  final TextEditingController _searchController = TextEditingController();

  // Statistics
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  // Employee data (refreshable)
  Map<String, dynamic>? _freshEmployee;

  // Cash boxes for voucher dialog
  List<Map<String, dynamic>> _cashBoxes = [];

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'الكل'),
    _FilterTab(key: 'payment_voucher', label: 'سند صرف'),
    _FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
  ];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  @override
  void initState() {
    super.initState();
    _freshEmployee = widget.employee;
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
      // Refresh employee data
      final employeeMap = await locator<ReferenceDataRepository>().getEmployeeById(widget.employee['id'] as int);
      if (employeeMap != null) {
        _freshEmployee = employeeMap;
      }
    } catch (e) {
      debugPrint('EmployeeDetailScreen._loadData [refreshEmployee]: $e');
    }

    try {
      _cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
    } catch (e) {
      debugPrint('EmployeeDetailScreen._loadData [cashBoxes]: $e');
    }

    try {
      await _loadMovements();
    } catch (e) {
      debugPrint('EmployeeDetailScreen._loadData [movements]: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadMovements() async {
    final employee = _freshEmployee ?? widget.employee;
    final employeeId = employee['id'] as int;
    final accountId = employee['account_id'] as int?;
    final movements = <Map<String, dynamic>>[];

    // 1. Load transactions for this employee's account
    if (accountId != null) {
      try {
        final transactions = await locator<EmployeeRepository>().getEmployeeTransactions(accountId);

        for (final txn in transactions) {
          final debit = MoneyHelper.readMoney(txn['debit']);
          final credit = MoneyHelper.readMoney(txn['credit']);
          final description = txn['description'] as String? ?? '';
          final dateStr = txn['date'] as String? ?? txn['created_at'] as String? ?? DateTime.now().toIso8601String();
          final refType = txn['reference_type'] as String?;
          final currency = txn['account_currency'] as String? ?? employee['currency'] as String? ?? 'YER';

          // Skip opening balance transactions — loaded separately
          if (refType == 'opening_balance') continue;

          final displayDebit = debit > 0 ? debit : 0.0;
          final displayCredit = credit > 0 ? credit : 0.0;

          String typeAr;
          String filterKey;
          IconData icon;
          Color color;

          if (displayDebit > 0) {
            typeAr = 'عليه';
            filterKey = 'debit';
            icon = Icons.trending_down;
            color = AppColors.error;
          } else if (displayCredit > 0) {
            typeAr = 'له';
            filterKey = 'credit';
            icon = Icons.trending_up;
            color = AppColors.success;
          } else {
            typeAr = 'قيد';
            filterKey = 'all';
            icon = Icons.description;
            color = AppColors.textSecondary;
          }

          movements.add({
            'id': 't_${txn['id']}',
            'date': dateStr,
            'type': 'transaction',
            'type_ar': typeAr,
            'filter_key': filterKey,
            'icon': icon,
            'color': color,
            'description': description,
            'debit': displayDebit,
            'credit': displayCredit,
            'currency': currency,
            'source': 'transaction',
            'voucher_type': null,
            'created_at': txn['created_at'] as String? ?? dateStr,
          });
        }
      } catch (e) {
        debugPrint('EmployeeDetailScreen._loadMovements [transactions]: $e');
      }
    }

    // 2. Load vouchers linked to this employee
    try {
      final voucherRows = await locator<EmployeeRepository>().getEmployeeVouchers(employeeId);

      for (final v in voucherRows) {
        final voucherType = v['voucher_type'] as String? ?? '';
        final totalAmount = MoneyHelper.readMoney(v['total_amount']);
        final currency = v['currency'] as String? ?? 'YER';
        final dateStr = v['date'] as String? ?? v['created_at'] as String? ?? DateTime.now().toIso8601String();

        String typeAr, filterKey;
        IconData icon;
        Color color;
        double debit = 0.0, credit = 0.0;

        // Employee voucher direction:
        // - Receipt (سند قبض): Employee pays us back → they OWE us → debit (عليه)
        // - Payment (سند صرف): We pay the employee → they are CREDITED → credit (له)
        // This is OPPOSITE to customer/supplier direction because employees are
        // expense accounts (debit nature) — paying them increases their credit position.
        switch (voucherType) {
          case 'receipt':
            typeAr = 'سند قبض'; icon = Icons.assignment_turned_in; color = AppColors.error;
            debit = totalAmount; filterKey = 'receipt_voucher'; break;
          case 'payment':
            typeAr = 'سند صرف'; icon = Icons.assignment_return; color = AppColors.success;
            credit = totalAmount; filterKey = 'payment_voucher'; break;
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
          'id': 'v_${v['id']}',
          'date': dateStr,
          'type': voucherType,
          'type_ar': typeAr,
          'filter_key': filterKey,
          'icon': icon,
          'color': color,
          'description': description,
          'debit': debit,
          'credit': credit,
          'currency': currency,
          'source': 'voucher',
          'voucher_type': voucherType,
          'created_at': v['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('EmployeeDetailScreen._loadMovements [vouchers]: $e');
    }

    // 3. Opening balance transactions
    try {
      final obTransactions = await locator<EmployeeRepository>().getEmployeeOpeningBalanceTransactions(employeeId);

      for (final ob in obTransactions) {
        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ?? ob['created_at'] as String? ?? DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';
        final obCurrency = ob['account_currency'] as String? ?? employee['currency'] as String? ?? 'YER';

        movements.add({
          'id': 'ob_${ob['id']}',
          'date': dateStr,
          'type': 'opening_balance',
          'type_ar': 'رصيد افتتاحي',
          'filter_key': 'opening_balance',
          'icon': Icons.account_balance_wallet,
          'color': AppColors.accentBlue,
          'description': description,
          'debit': debit > 0 ? debit : 0.0,
          'credit': credit > 0 ? credit : 0.0,
          'currency': obCurrency,
          'source': 'opening_balance',
          'voucher_type': null,
          'created_at': ob['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('EmployeeDetailScreen._loadMovements [opening_balance]: $e');
    }

    // Sort by date+time ascending (oldest first).
    movements.sort((a, b) {
      final cmp = (a['date'] as String).compareTo(b['date'] as String);
      if (cmp != 0) return cmp;
      return ((a['created_at'] as String?) ?? '').compareTo((b['created_at'] as String?) ?? '');
    });

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
    if (filterKey != 'all') {
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
    // _allMovements already has correct running_balance values from _loadMovements().
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

    final employee = _freshEmployee ?? widget.employee;
    final employeeName = employee['name'] as String? ?? '';

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
                  decoration: const InputDecoration(labelText: 'الموظف', prefixIcon: Icon(Icons.person)),
                  child: Text(employeeName),
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
                    entityType: VoucherAutoMappingService.entityEmployee,
                    entityId: employee['id'] as int,
                    cashBoxId: selectedCashBoxId,
                    amount: amount,
                    currency: selectedCurrency,
                    date: dateStr,
                    description: descriptionController.text.trim().isEmpty
                        ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - $employeeName'
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
    final employee = _freshEmployee ?? widget.employee;
    final name = employee['name'] as String? ?? '';
    final phone = employee['phone'] as String?;
    final currency = employee['currency'] as String? ?? 'YER';
    try {
      await AccountStatementPdfGenerator.printAccountStatement(
        entityName: name, entityType: 'employee', movements: _filteredMovements,
        totalDebit: _totalDebit, totalCredit: _totalCredit, netBalance: _netBalance,
        balanceLabel: _netBalance > 0 ? 'له' : (_netBalance < 0 ? 'عليه' : 'متساوي'),
        phone: phone, currency: currency,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء إنشاء كشف الحساب'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _printBluetoothStatement() async {
    final printerService = BluetoothPrinterService.instance;
    final employee = _freshEmployee ?? widget.employee;
    final name = employee['name'] as String? ?? '';
    final balance = MoneyHelper.readMoney(employee['balance']);
    final balanceType = employee['balance_type'] as String? ?? 'credit';
    final currency = employee['currency'] as String? ?? 'YER';

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
      await printerService.printCustomerStatement({'name': name, 'balance': balance, 'balance_type': balanceType, 'currency': currency});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال كشف الحساب للطابعة الحرارية'), backgroundColor: AppColors.success));
    } on PrinterException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error));
    }
  }

  void _exportToExcel() async {
    final employee = _freshEmployee ?? widget.employee;
    final name = employee['name'] as String? ?? '';
    try {
      await ExcelExporter.exportAccountStatementToExcel(
        entityName: name, entityType: 'موظف', movements: _filteredMovements,
        totalDebit: _totalDebit, totalCredit: _totalCredit, netBalance: _netBalance,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء التصدير'), backgroundColor: AppColors.error));
    }
  }

  String _currencySymbol(String? code) {
    switch (code) { case 'SAR': return 'ر.س'; case 'USD': return r'$'; case 'YER': default: return 'ر.ي'; }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final employee = _freshEmployee ?? widget.employee;
    final name = employee['name'] as String? ?? '';
    final phone = employee['phone'] as String? ?? '';
    final jobTitle = employee['job_title'] as String? ?? '';
    final balance = MoneyHelper.readMoney(employee['balance']);
    final balanceType = employee['balance_type'] as String? ?? 'credit';
    final currency = employee['currency'] as String? ?? 'YER';
    final isDebit = balanceType == 'debit';

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
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (jobTitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [const Icon(Icons.work, size: 13, color: Colors.white70), const SizedBox(width: 4), Text(jobTitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70))]),
                        ],
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [const Icon(Icons.phone, size: 13, color: Colors.white70), const SizedBox(width: 4), Text(phone, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70))]),
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
                          '${balance.abs().toStringAsFixed(2)} ${_currencySymbol(currency)}',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDebit ? AppColors.error : AppColors.success).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isDebit ? 'عليه' : (balance > 0 ? 'له' : 'متساوي'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
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
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () {
                      setState(() => _sortDescending = !_sortDescending);
                      _applyFilters();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: _sortDescending ? AppColors.primary : AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                        color: _sortDescending ? AppColors.primary.withOpacity(0.08) : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                            size: 14,
                            color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _sortDescending ? 'تنازلي' : 'تصاعدي',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
}

// ═══════════════════════════════════════════════════════════════════
//  MOVEMENT CARD — Professional Design (matches Customer pattern)
// ═══════════════════════════════════════════════════════════════════
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final String currencySymbol;
  final bool isLight;

  const _MovementCard({required this.movement, required this.currencySymbol, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = movement['icon'] as IconData;
    final color = movement['color'] as Color;
    final typeAr = movement['type_ar'] as String? ?? '';
    final description = movement['description'] as String? ?? '';
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      runningBalance >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 10,
                      color: balanceColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${runningBalance.abs().toStringAsFixed(2)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
