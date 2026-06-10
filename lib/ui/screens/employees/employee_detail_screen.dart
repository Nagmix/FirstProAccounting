import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/utils/movement_sorter.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/employee_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:firstpro/data/datasources/services/voucher_auto_mapping_service.dart';
import 'package:firstpro/ui/widgets/entity_detail/entity_detail_state.dart';

/// Employee Detail / Ledger Screen — Modern Professional Design
/// Displays all financial movements for a specific employee with
/// filtering, search, statistics, and voucher creation capabilities.
class EmployeeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState
    extends EntityDetailState<EmployeeDetailScreen> {
  // Employee data (refreshable)
  Map<String, dynamic>? _freshEmployee;

  // ─── Abstract Method Implementations ─────────────────────────────────

  @override
  List<FilterTab> get filterTabs => const [
        FilterTab(key: 'all', label: 'الكل'),
        FilterTab(key: 'payment_voucher', label: 'سند صرف'),
        FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
      ];

  @override
  String get entityName =>
      (_freshEmployee ?? widget.employee)['name'] as String? ?? '';

  @override
  String get entityPhone =>
      (_freshEmployee ?? widget.employee)['phone'] as String? ?? '';

  @override
  String get entitySubtitle =>
      (_freshEmployee ?? widget.employee)['job_title'] as String? ?? '';

  @override
  String get entityTypeName => VoucherAutoMappingService.entityEmployee;

  @override
  int? get entityId => (_freshEmployee ?? widget.employee)['id'] as int?;

  @override
  IconData get entityIcon => Icons.badge;

  @override
  String get entityLabel => 'الموظف';

  @override
  IconData get entityLabelIcon => Icons.person;

  @override
  String get entityTypeAr => 'موظف';

  @override
  String get entityTypePdf => 'employee';

  // ─── Lifecycle ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freshEmployee = widget.employee;
    loadData();
  }

  // ─── Data Loading ────────────────────────────────────────────────────

  @override
  Future<void> loadData() async {
    isLoading = true;

    try {
      // Refresh employee data
      final employeeMap = await locator<ReferenceDataRepository>()
          .getEmployeeById(widget.employee['id'] as int);
      if (employeeMap != null) {
        _freshEmployee = employeeMap;
      }
    } catch (e) {
      debugPrint('EmployeeDetailScreen.loadData [refreshEmployee]: $e');
    }

    try {
      cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
    } catch (e) {
      debugPrint('EmployeeDetailScreen.loadData [cashBoxes]: $e');
    }

    try {
      await loadMovements();
    } catch (e) {
      debugPrint('EmployeeDetailScreen.loadData [movements]: $e');
    }

    isLoading = false;
  }

  @override
  Future<void> loadMovements() async {
    final employee = _freshEmployee ?? widget.employee;
    final employeeId = employee['id'] as int;
    final accountId = employee['account_id'] as int?;
    final movements = <Map<String, dynamic>>[];

    // 1. Load transactions for this employee's account
    if (accountId != null) {
      try {
        final transactions = await locator<EmployeeRepository>()
            .getEmployeeTransactions(accountId);

        for (final txn in transactions) {
          final debit = MoneyHelper.readMoney(txn['debit']);
          final credit = MoneyHelper.readMoney(txn['credit']);
          final description = txn['description'] as String? ?? '';
          final dateStr = txn['date'] as String? ??
              txn['created_at'] as String? ??
              DateTime.now().toIso8601String();
          final refType = txn['reference_type'] as String?;
          final currency = txn['account_currency'] as String? ??
              employee['currency'] as String? ??
              'YER';

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
        debugPrint('EmployeeDetailScreen.loadMovements [transactions]: $e');
      }
    }

    // 2. Load vouchers linked to this employee
    try {
      final voucherRows =
          await locator<EmployeeRepository>().getEmployeeVouchers(employeeId);

      for (final v in voucherRows) {
        final voucherType = v['voucher_type'] as String? ?? '';
        final totalAmount = MoneyHelper.readMoney(v['total_amount']);
        final currency = v['currency'] as String? ?? 'YER';
        final dateStr = v['date'] as String? ??
            v['created_at'] as String? ??
            DateTime.now().toIso8601String();

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
            typeAr = 'سند قبض';
            icon = Icons.assignment_turned_in;
            color = AppColors.error;
            debit = totalAmount;
            filterKey = 'receipt_voucher';
            break;
          case 'payment':
            typeAr = 'سند صرف';
            icon = Icons.assignment_return;
            color = AppColors.success;
            credit = totalAmount;
            filterKey = 'payment_voucher';
            break;
          case 'settlement':
            typeAr = 'قيد عام';
            icon = Icons.balance;
            color = AppColors.info;
            credit = totalAmount;
            filterKey = 'general_entry';
            break;
          case 'compound':
            typeAr = 'قيد متعدد';
            icon = Icons.dynamic_feed;
            color = AppColors.accentBlue;
            debit = totalAmount;
            filterKey = 'compound_entry';
            break;
          default:
            typeAr = 'سند';
            icon = Icons.description;
            color = AppColors.textSecondary;
            debit = totalAmount;
            filterKey = 'all';
        }

        final description = v['description'] as String? ??
            '$typeAr - ${v['voucher_number'] ?? ''}';

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
      debugPrint('EmployeeDetailScreen.loadMovements [vouchers]: $e');
    }

    // 3. Opening balance transactions
    try {
      final obTransactions = await locator<EmployeeRepository>()
          .getEmployeeOpeningBalanceTransactions(employeeId);

      for (final ob in obTransactions) {
        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ??
            ob['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';
        final obCurrency = ob['account_currency'] as String? ??
            employee['currency'] as String? ??
            'YER';

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
      debugPrint('EmployeeDetailScreen.loadMovements [opening_balance]: $e');
    }

    // Sort chronologically (oldest first) via the unified sorter —
    // handles mixed date formats (day-only vs full timestamp). B-1 fix.
    MovementSorter.sortChronologically(movements);

    // Calculate running balance for ALL movements chronologically, per currency
    final currencyRunBal = <String, double>{};
    for (final m in movements) {
      final currency = m['currency'] as String? ?? 'YER';
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      currencyRunBal[currency] =
          (currencyRunBal[currency] ?? 0.0) + credit - debit;
      m['running_balance'] = currencyRunBal[currency];
    }

    allMovements = movements;
    applyFilters();
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: buildAppBarActions()),
      body: buildBody(),
      bottomNavigationBar: buildBottomBar(),
    );
  }
}
