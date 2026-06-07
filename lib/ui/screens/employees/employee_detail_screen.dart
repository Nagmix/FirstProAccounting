import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/employee_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import 'employees_screen.dart' show AddEmployeeSheet;

/// Employee Detail / Ledger Screen
/// Displays all financial movements for a specific employee with
/// filtering, statistics, and transaction creation capabilities.
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
  DateTimeRange? _dateRange;

  // Statistics
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  // Employee data (refreshable)
  Map<String, dynamic>? _freshEmployee;

  // Cash boxes for transaction dialog
  List<Map<String, dynamic>> _cashBoxes = [];

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'الكل'),
    _FilterTab(key: 'credit', label: 'له'),
    _FilterTab(key: 'debit', label: 'عليه'),
  ];

  @override
  void initState() {
    super.initState();
    _freshEmployee = widget.employee;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Refresh employee data
    final employeeMap = await locator<ReferenceDataRepository>().getEmployeeById(widget.employee['id'] as int);
    if (employeeMap != null) {
      _freshEmployee = employeeMap;
    }

    // Load cash boxes
    _cashBoxes = await locator<CashBoxService>().getAllCashBoxes();

    // Load all movements
    await _loadMovements();

    setState(() => _isLoading = false);
  }

  Future<void> _loadMovements() async {
    final employee = _freshEmployee ?? widget.employee;
    final employeeId = employee['id'] as int;
    final accountId = employee['account_id'] as int?;
    final movements = <Map<String, dynamic>>[];

    // 1. Load transactions for this employee's account
    if (accountId != null) {
      final transactions = await locator<EmployeeRepository>().getEmployeeTransactions(accountId);

      for (final txn in transactions) {
        final debit = MoneyHelper.readMoney(txn['debit']);
        final credit = MoneyHelper.readMoney(txn['credit']);
        final description = txn['description'] as String? ?? '';
        final dateStr = txn['date'] as String? ?? txn['created_at'] as String? ?? DateTime.now().toIso8601String();
        final refType = txn['reference_type'] as String?;
        final currency = employee['currency'] as String? ?? 'YER';

        // Employee account 5100 is an EXPENSE account (debit nature).
        // From the employee's perspective:
        //   Accounting debit on 5100 = expense increased = employee earned money = له
        //   Accounting credit on 5100 = expense decreased = employee owes money = عليه
        // So we must swap for display:
        //   accounting debit → display credit (له)
        //   accounting credit → display debit (عليه)
        final displayDebit = credit > 0 ? credit : 0.0;  // credit on expense = عليه
        final displayCredit = debit > 0 ? debit : 0.0;  // debit on expense = له

        String typeAr;
        String filterKey;
        if (displayDebit > 0) {
          typeAr = 'عليه';
          filterKey = 'debit';
        } else if (displayCredit > 0) {
          typeAr = 'له';
          filterKey = 'credit';
        } else {
          typeAr = 'قيد';
          filterKey = 'all';
        }

        // Skip opening balance transactions here — they're loaded separately below
        if (refType == 'opening_balance') continue;

        movements.add({
          'id': 't_${txn['id']}',
          'date': dateStr,
          'type': 'transaction',
          'type_ar': typeAr,
          'filter_key': filterKey,
          'description': description,
          'debit': displayDebit,
          'credit': displayCredit,
          'currency': currency,
          'source': 'transaction',
        });
      }
    }

    // 2. Load vouchers linked to this employee
    final voucherRows = await locator<EmployeeRepository>().getEmployeeVouchers(employeeId);

    for (final v in voucherRows) {
      final voucherType = v['voucher_type'] as String? ?? '';
      final totalAmount = MoneyHelper.readMoney(v['total_amount']);
      final currency = v['currency'] as String? ?? 'YER';
      final dateStr = v['date'] as String? ?? v['created_at'] as String? ?? DateTime.now().toIso8601String();

      String typeAr;
      double debit = 0.0;
      double credit = 0.0;
      String filterKey;

      switch (voucherType) {
        case 'receipt':
          typeAr = 'سند قبض';
          credit = totalAmount;
          filterKey = 'credit';
          break;
        case 'payment':
          typeAr = 'سند صرف';
          debit = totalAmount;
          filterKey = 'debit';
          break;
        case 'settlement':
          typeAr = 'قيد عام';
          credit = totalAmount;
          filterKey = 'credit';
          break;
        case 'compound':
          typeAr = 'قيد متعدد';
          debit = totalAmount;
          filterKey = 'debit';
          break;
        default:
          typeAr = 'سند';
          debit = totalAmount;
          filterKey = 'all';
      }

      final description = v['description'] as String? ?? '$typeAr - ${v['voucher_number'] ?? ''}';

      movements.add({
        'id': 'v_${v['id']}',
        'date': dateStr,
        'type': voucherType,
        'type_ar': typeAr,
        'filter_key': filterKey,
        'description': description,
        'debit': debit,
        'credit': credit,
        'currency': currency,
        'source': 'voucher',
      });
    }

    // ── Add Opening Balance as a movement ──
    // Query the transactions table for opening balance entries linked to this employee
    final obTransactions = await locator<EmployeeRepository>().getEmployeeOpeningBalanceTransactions(employeeId);
    
    for (final ob in obTransactions) {
      final debit = MoneyHelper.readMoney(ob['debit']);
      final credit = MoneyHelper.readMoney(ob['credit']);
      final dateStr = ob['date'] as String? ?? ob['created_at'] as String? ?? DateTime.now().toIso8601String();
      final description = ob['description'] as String? ?? 'رصيد افتتاحي';
      final obCurrency = ob['account_currency'] as String? ?? 'YER';

      // Employee account 5100 is EXPENSE (debit nature): swap for display
      // accounting debit → display credit (له), accounting credit → display debit (عليه)
      movements.add({
        'id': 'ob_${ob['id']}',
        'date': dateStr,
        'type': 'opening_balance',
        'type_ar': 'رصيد افتتاحي',
        'filter_key': 'all',
        'description': description,
        'debit': credit > 0 ? credit : 0.0,  // credit on expense = عليه
        'credit': debit > 0 ? debit : 0.0,   // debit on expense = له
        'currency': obCurrency,
        'source': 'opening_balance',
      });
    }

    // Sort by date ascending for running balance
    movements.sort((a, b) {
      final dateA = a['date'] as String;
      final dateB = b['date'] as String;
      return dateA.compareTo(dateB);
    });

    _allMovements = movements;
    _applyFilters();
  }

  void _applyFilters() {
    // Deep copy maps to avoid mutating _allMovements when setting running_balance
    var filtered = _allMovements.map((m) => Map<String, dynamic>.from(m)).toList();

    // Apply tab filter
    final filterKey = _filterTabs[_selectedFilterIndex].key;
    if (filterKey == 'debit') {
      filtered = filtered.where((m) => MoneyHelper.readMoney(m['debit']) > 0).toList();
    } else if (filterKey == 'credit') {
      filtered = filtered.where((m) => MoneyHelper.readMoney(m['credit']) > 0).toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String;
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_dateRange!.start) && !date.isAfter(_dateRange!.end.add(const Duration(days: 1)));
        } catch (e) {
          return true;
        }
      }).toList();
    }

    // Calculate running balance and totals
    // Opening balance is now included as a movement, so start from 0
    double runningBalance = 0.0;
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final m in filtered) {
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      runningBalance += credit - debit; // positive = له, negative = عليه
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
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _applyFilters();
  }

  // ── Add Transaction Dialog ───────────────────────────────────
  Future<void> _showAddTransactionDialog(String operationType) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int? selectedCashBoxId;
    bool isSaving = false;

    final employee = _freshEmployee ?? widget.employee;
    final employeeCurrency = employee['currency'] as String? ?? 'YER';

    // Cash boxes are currency-agnostic — show all, user picks the one they want
    final filteredCashBoxes = _cashBoxes;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    operationType == 'credit' ? Icons.trending_up : Icons.trending_down,
                    color: operationType == 'credit' ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Text(operationType == 'credit' ? 'إضافة له' : 'إضافة عليه'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Employee name (read-only)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'الموظف',
                        prefixIcon: Icon(Icons.person),
                      ),
                      child: Text(employee['name'] as String? ?? ''),
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: _currencySymbol(employeeCurrency),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Cash Box
                    DropdownButtonFormField<int?>(
                      value: selectedCashBoxId,
                      decoration: const InputDecoration(
                        labelText: 'الصندوق',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                      ),
                      items: filteredCashBoxes.map((cb) {
                        return DropdownMenuItem<int?>(
                          value: cb['id'] as int?,
                          child: Text('${cb['name']}'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setDialogState(() => selectedCashBoxId = v);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Description
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: operationType == 'credit' ? 'بيان عملية (له)' : 'بيان عملية (عليه)',
                        prefixIcon: const Icon(Icons.description),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: operationType == 'credit' ? AppColors.success : AppColors.error,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount = double.tryParse(amountController.text);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('يرجى إدخال مبلغ صالح'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);

                          try {
                            await locator<EmployeeRepository>().recordEmployeeTransaction(
                              employeeId: employee['id'] as int,
                              amount: amount,
                              balanceType: operationType,
                              currency: employeeCurrency,
                              cashBoxId: selectedCashBoxId,
                              description: descriptionController.text.trim(),
                            );

                            if (context.mounted) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(operationType == 'credit'
                                      ? 'تم تسجيل العملية (له) بنجاح'
                                      : 'تم تسجيل العملية (عليه) بنجاح'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              _loadData();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('حدث خطأ: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(operationType == 'credit' ? 'تسجيل له' : 'تسجيل عليه'),
                ),
              ],
            );
          },
        );
      },
    );
    amountController.dispose();
    descriptionController.dispose();
  }

  // ── Helper Methods ────────────────────────────────────────────
  String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormatter.formatDate(date);
    } catch (e) {
      return dateStr;
    }
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
    final balanceDisplay = balance.abs().toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          // Edit button
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل',
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => AddEmployeeSheet(employee: employee),
              );
              _loadData();
            },
          ),
          // Toggle active/inactive
          IconButton(
            icon: Icon(
              (employee['is_active'] as int?) == 1 ? Icons.block : Icons.check_circle,
            ),
            tooltip: (employee['is_active'] as int?) == 1 ? 'تعطيل' : 'تفعيل',
            onPressed: () async {
              final isActive = (employee['is_active'] as int?) == 1;
              await locator<ReferenceDataRepository>().updateEmployee(employee['id'] as int, {
                'is_active': isActive ? 0 : 1,
                'updated_at': DateTime.now().toIso8601String(),
              });
              _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Header Card ────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              child: Text(
                                name.isNotEmpty ? name[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (jobTitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.work, size: 14, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Text(
                                          jobTitle,
                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (phone.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone, size: 14, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Text(
                                          phone,
                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$balanceDisplay ${_currencySymbol(currency)}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDebit ? AppColors.error.withOpacity(0.9) : AppColors.success.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isDebit ? 'عليه' : (balance > 0 ? 'له' : 'متساوي'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Action buttons row
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddTransactionDialog('credit'),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('له'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddTransactionDialog('debit'),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('عليه'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Filter Tabs ─────────────────────────────────────
                Container(
                  height: 44,
                  color: isLight ? AppColors.surface : AppColors.darkSurface,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: _filterTabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedFilterIndex == index;
                      return ChoiceChip(
                        label: Text(_filterTabs[index].label),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedFilterIndex = index);
                          _applyFilters();
                        },
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                        backgroundColor: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                        selectedColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),

                // ── Date Filter ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isLight ? AppColors.surface : AppColors.darkSurface,
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDateRange,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _dateRange != null
                                        ? '${_formatDate(_dateRange!.start.toIso8601String())} - ${_formatDate(_dateRange!.end.toIso8601String())}'
                                        : 'كل الفترات',
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_dateRange != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _clearDateRange,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(height: 1),

                // ── Transaction List ────────────────────────────────
                Expanded(
                  child: _filteredMovements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long, size: 48, color: AppColors.textHint),
                              const SizedBox(height: 12),
                              Text('لا توجد حركات', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                              const SizedBox(height: 4),
                              Text('اضغط على له أو عليه لإضافة حركة', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _filteredMovements.length,
                          itemBuilder: (context, index) {
                            return _buildMovementCard(_filteredMovements[index], theme, isLight);
                          },
                        ),
                ),

                // ── Summary Row ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isLight ? AppColors.surface : AppColors.darkSurface,
                    border: Border(top: BorderSide(color: isLight ? AppColors.border : AppColors.darkBorder)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Total له
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('له', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                            Text(
                              CurrencyFormatter.formatValue(_totalCredit),
                              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      // Total عليه
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('عليه', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
                            Text(
                              CurrencyFormatter.formatValue(_totalDebit),
                              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      // Net balance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('الرصيد', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                            Text(
                              '${CurrencyFormatter.formatValue(_netBalance.abs())} ${_netBalance >= 0 ? 'له' : 'عليه'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMovementCard(Map<String, dynamic> movement, ThemeData theme, bool isLight) {
    final dateStr = movement['date'] as String;
    final description = movement['description'] as String? ?? '';
    final debit = MoneyHelper.readMoney(movement['debit']);
    final credit = MoneyHelper.readMoney(movement['credit']);
    final runningBalance = movement['running_balance'] as double? ?? 0.0;
    final typeAr = movement['type_ar'] as String? ?? '';
    final isCredit = credit > 0;

    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isCredit ? AppColors.success : AppColors.error).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCredit ? Icons.trending_up : Icons.trending_down,
                color: isCredit ? AppColors.success : AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Date + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description.isNotEmpty ? description : typeAr,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(dateStr),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Amount + running balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.formatValue(isCredit ? credit : debit),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isCredit ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${runningBalance.abs().toStringAsFixed(2)} ${runningBalance >= 0 ? 'له' : 'عليه'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: runningBalance >= 0 ? AppColors.success : AppColors.error,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

