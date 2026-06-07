import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/money_helper.dart';
import '../../../../data/datasources/repositories/customer_repository.dart';
import '../../../../data/datasources/repositories/supplier_repository.dart';
import '../../../../data/datasources/services/report_service.dart';
import 'report_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Data Loading for Reports
//  All report query methods extracted from ReportsScreenState.
//  Each method takes the needed parameters and returns a result
//  with rows and totals — no direct state mutation.
// ═══════════════════════════════════════════════════════════════════

class ReportLoadResult {
  final List<Map<String, dynamic>> rows;
  final Map<String, double> totals;

  const ReportLoadResult({required this.rows, required this.totals});
}

class ReportDataLoader {
  ReportDataLoader._();

  // ── Main dispatch ────────────────────────────────────────────

  static Future<ReportLoadResult> load({
    required String reportKey,
    required ReportFilterParams params,
  }) async {
    switch (reportKey) {
      // ── SALES & PURCHASES ──
      case 'sales':
        return _loadSalesReport(
          typeFilter: "i.type IN ('sale','pos') AND i.is_return=0",
          params: params,
        );
      case 'purchases':
        return _loadSalesReport(
          typeFilter: "i.type='purchase' AND i.is_return=0",
          params: params,
        );
      case 'sales_returns':
        return _loadSalesReport(
          typeFilter: "i.type IN ('sale','pos') AND i.is_return=1",
          params: params,
        );
      case 'purchase_returns':
        return _loadSalesReport(
          typeFilter: "i.type='purchase' AND i.is_return=1",
          params: params,
        );
      case 'profit_loss':
        return _loadProfitLossReport(params: params);
      case 'invoice_profit':
        return _loadInvoiceProfitReport(params: params);
      case 'sales_by_product':
        return _loadSalesByProductReport(params: params);
      case 'sales_by_customer':
        return _loadSalesByCustomerReport(params: params);

      // ── ACCOUNTING ──
      case 'account_movement':
        return _loadAccountMovementReport(params: params);
      case 'all_account_movement':
        return _loadAllAccountMovementReport(params: params);
      case 'trial_balance':
        return _loadTrialBalanceReport(params: params);
      case 'cash_box':
        return _loadCashBoxReport(params: params);
      case 'accounts_no_movement':
        return _loadAccountsWithoutMovementReport(params: params);
      case 'customer_statement':
        return _loadCustomerStatementReport(params: params);
      case 'supplier_statement':
        return _loadSupplierStatementReport(params: params);
      case 'expenses':
        return _loadExpensesReport(params: params);

      // ── INVENTORY ──
      case 'inventory':
        return _loadInventoryReport(params: params);
      case 'inventory_movement':
        return _loadInventoryMovementReport(params: params);
      case 'inventory_cost':
        return _loadInventoryCostReport();
      case 'out_of_stock':
        return _loadOutOfStockReport(params: params);
      case 'low_stock':
        return _loadLowStockReport(params: params);

      // ── DEBTS ──
      case 'customer_debts':
        return _loadDebtReport(isCustomer: true);
      case 'supplier_debts':
        return _loadDebtReport(isCustomer: false);

      // ── OPERATIONS ──
      case 'cash_transfers':
        return _loadCashTransfersReport(params: params);
      case 'currency_exchanges':
        return _loadCurrencyExchangesReport(params: params);
      case 'vouchers':
        return _loadVouchersReport(params: params);
      case 'shifts':
        return _loadShiftsReport();

      default:
        return const ReportLoadResult(rows: [], totals: {});
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Individual Report Queries
  // ══════════════════════════════════════════════════════════════

  static Future<ReportLoadResult> _loadSalesReport({
    required String typeFilter,
    required ReportFilterParams params,
  }) async {
    final results = await locator<ReportService>().getSalesReport(
      typeFilter: typeFilter,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
      cashBoxId: params.selectedCashBoxId,
    );

    double totalAmount = 0, totalPaid = 0, totalRemaining = 0;
    final rows = results.map((r) {
      final total = MoneyHelper.readMoney(r['total']);
      final paid = MoneyHelper.readMoney(r['paid_amount']);
      final remaining = MoneyHelper.readMoney(r['remaining']);
      totalAmount += total;
      totalPaid += paid;
      totalRemaining += remaining;
      return {
        'رقم الفاتورة': () { final idStr = (r['id'] as String?) ?? ''; return idStr.length > 12 ? idStr.substring(0, 12) : idStr; }(),
        'النوع': invoiceTypeAr(r['type'] as String? ?? '', isReturn: r['is_return'] as int?),
        'الجهة': r['entity_name'] as String? ?? '',
        'الإجمالي': total,
        'المدفوع': paid,
        'المتبقي': remaining,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['created_at'] as String? ?? '',
      };
    }).toList();
    final totals = {'الإجمالي': totalAmount, 'المدفوع': totalPaid, 'المتبقي': totalRemaining, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadProfitLossReport({required ReportFilterParams params}) async {
    final reportData = await locator<ReportService>().getProfitLossReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
    );
    final dataMap = <String, dynamic>{};
    for (final row in reportData) {
      dataMap[row['item'] as String] = row['amount'];
    }
    final revenue = MoneyHelper.readCalculatedMoney(dataMap['revenue']);
    final purchases = MoneyHelper.readCalculatedMoney(dataMap['purchases']);
    final salesReturns = MoneyHelper.readCalculatedMoney(dataMap['sales_returns']);
    final purchaseReturns = MoneyHelper.readCalculatedMoney(dataMap['purchase_returns']);
    final expenses = MoneyHelper.readCalculatedMoney(dataMap['expenses']);
    final cogs = MoneyHelper.readCalculatedMoney(dataMap['cogs']);

    final netSales = revenue - salesReturns;
    // ignore: unused_local_variable
    final netPurchases = purchases - purchaseReturns;

    final grossProfit = netSales - cogs;
    final netProfit = grossProfit - expenses;

    final rows = [
      {'البند': 'إجمالي المبيعات', 'المبلغ': revenue, 'ملاحظة': 'فواتير البيع'},
      {'البند': 'مرتجعات المبيعات', 'المبلغ': -salesReturns, 'ملاحظة': 'فواتير المرتجع'},
      {'البند': 'صافي المبيعات', 'المبلغ': netSales, 'ملاحظة': ''},
      {'البند': 'تكلفة البضاعة المباعة', 'المبلغ': cogs, 'ملاحظة': 'محسوبة من تكلفة الأصناف المباعة'},
      {'البند': 'مجمل الربح', 'المبلغ': grossProfit, 'ملاحظة': 'صافي المبيعات - تكلفة البضاعة'},
      {'البند': 'المصاريف التشغيلية', 'المبلغ': -expenses, 'ملاحظة': ''},
      {'البند': 'صافي الربح', 'المبلغ': netProfit, 'ملاحظة': 'مجمل الربح - المصاريف'},
    ];
    final totals = {'صافي المبيعات': netSales, 'تكلفة البضاعة': cogs, 'صافي الربح': netProfit};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadInvoiceProfitReport({required ReportFilterParams params}) async {
    final items = await locator<ReportService>().getInvoiceProfitReport(startDate: params.dateFrom, endDate: params.dateTo);
    double totalProfit = 0, totalRevenue = 0, totalCost = 0;
    final rows = items.map((item) {
      final profit = MoneyHelper.readCalculatedMoney(item['profit']);
      final total = MoneyHelper.readCalculatedMoney(item['sale_total']);
      final cost = MoneyHelper.readCalculatedMoney(item['cost_total']);
      totalProfit += profit;
      totalRevenue += total;
      totalCost += cost;
      final idStr = (item['invoice_id']?.toString() ?? '');
      return {
        'رقم الفاتورة': idStr.length > 12 ? idStr.substring(0, 12) : idStr,
        'الجهة': item['entity_name'] as String? ?? '',
        'إجمالي الفاتورة': total,
        'تكلفة الفاتورة': cost,
        'الربح': profit,
        'هامش الربح': total > 0 ? (profit / total * 100) : 0.0,
        'العملة': item['currency'] as String? ?? 'YER',
        'التاريخ': item['created_at'] as String? ?? '',
      };
    }).toList();
    final totals = {'إجمالي الإيرادات': totalRevenue, 'إجمالي التكلفة': totalCost, 'إجمالي الربح': totalProfit, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadSalesByProductReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getSalesByProductReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
      categoryId: params.selectedCategoryId,
    );
    double totalRevenue = 0, totalCost = 0, totalProfit = 0;
    int totalQty = 0;
    final rows = results.map((r) {
      final rev = MoneyHelper.readCalculatedMoney(r['revenue']);
      final cost = MoneyHelper.readCalculatedMoney(r['cost_total']);
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      final profit = rev - cost;
      totalRevenue += rev;
      totalCost += cost;
      totalProfit += profit;
      totalQty += qty.toInt();
      return {
        'المنتج': r['product_name'] as String? ?? '',
        'الكمية المباعة': qty,
        'إجمالي المبيعات': rev,
        'تكلفة المبيعات': cost,
        'الربح': profit,
        'هامش الربح': rev > 0 ? (profit / rev * 100) : 0.0,
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
    final totals = {'إجمالي المبيعات': totalRevenue, 'إجمالي التكلفة': totalCost, 'إجمالي الربح': totalProfit, 'إجمالي الكمية': totalQty.toDouble(), 'عدد الأصناف': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadSalesByCustomerReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getSalesByCustomerReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
    );
    double totalSales = 0;
    final rows = results.map((r) {
      final sales = MoneyHelper.readCalculatedMoney(r['total_sales']);
      totalSales += sales;
      return {
        'العميل': r['customer_name'] as String? ?? 'بدون عميل',
        'العملة': r['currency'] as String? ?? 'YER',
        'عدد الفواتير': (r['inv_count'] as num?)?.toInt() ?? 0,
        'إجمالي المبيعات': sales,
        'المدفوع': MoneyHelper.readCalculatedMoney(r['total_paid']),
        'المتبقي': MoneyHelper.readCalculatedMoney(r['total_remaining']),
      };
    }).toList();
    final totals = {'إجمالي المبيعات': totalSales, 'عدد العملاء': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadAccountMovementReport({required ReportFilterParams params}) async {
    if (params.selectedAccountId == null) return const ReportLoadResult(rows: [], totals: {});
    final transactions = await locator<ReportService>().getAccountMovementReport(
      accountId: params.selectedAccountId!,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    final balanceType = await locator<ReportService>().getAccountBalanceType(params.selectedAccountId!);
    final isDebitNature = balanceType == 'debit';

    double running = 0;
    double totalDebit = 0, totalCredit = 0;
    final rows = <Map<String, dynamic>>[];
    for (final tx in transactions) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
      if (isDebitNature) {
        running += (debit - credit);
      } else {
        running += (credit - debit);
      }
      totalDebit += debit;
      totalCredit += credit;
      rows.add({
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'مدين': debit,
        'دائن': credit,
        'الرصيد': running,
      });
    }
    final totals = {'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadAllAccountMovementReport({required ReportFilterParams params}) async {
    String? typeCode;
    if (params.selectedAccountType != 'الكل') {
      typeCode = accountTypes.firstWhere((e) => e.key == params.selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
      if (typeCode == 'الكل') typeCode = null;
    }
    final allTx = await locator<ReportService>().getAllAccountMovementReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
      accountType: typeCode,
    );
    double totalDebit = 0, totalCredit = 0;
    final rows = allTx.map((tx) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'كود الحساب': tx['account_code'] as String? ?? '',
        'اسم الحساب': tx['account_name'] as String? ?? 'غير معروف',
        'البيان': tx['description'] as String? ?? '',
        'مدين': debit,
        'دائن': credit,
        'العملة': tx['currency'] as String? ?? 'YER',
      };
    }).toList();
    final totals = {'مدين': totalDebit, 'دائن': totalCredit, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadTrialBalanceReport({required ReportFilterParams params}) async {
    String? typeCode;
    if (params.selectedAccountType != 'الكل') {
      typeCode = accountTypes.firstWhere((e) => e.key == params.selectedAccountType, orElse: () => const MapEntry('الكل', 'الكل')).value;
      if (typeCode == 'الكل') typeCode = null;
    }
    final results = await locator<ReportService>().getTrialBalanceReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
      accountType: typeCode,
    );
    double totalDebit = 0, totalCredit = 0;
    final rows = results.map((r) {
      final debit = MoneyHelper.readCalculatedMoney(r['debit']);
      final credit = MoneyHelper.readCalculatedMoney(r['credit']);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'كود الحساب': r['account_code'] as String? ?? '',
        'اسم الحساب': r['name_ar'] as String? ?? '',
        'نوع الحساب': accountTypeAr(r['account_type'] as String? ?? ''),
        'العملة': r['currency'] as String? ?? 'YER',
        'مدين': debit,
        'دائن': credit,
      };
    }).toList();
    final totals = {'مدين': totalDebit, 'دائن': totalCredit, 'الفرق': (totalDebit - totalCredit).abs(), 'عدد الحسابات': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadCashBoxReport({required ReportFilterParams params}) async {
    final cashBoxes = await locator<ReportService>().getCashBoxesReport(
      currency: currencyCode(params.selectedCurrency),
      cashBoxId: params.selectedCashBoxId,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    double totalBalance = 0;
    final rows = <Map<String, dynamic>>[];
    for (final cb in cashBoxes) {
      final balance = MoneyHelper.readMoney(cb['balance']);
      final isCredit = (cb['balance_type'] as String? ?? 'credit') == 'credit';
      final signedBalance = isCredit ? balance : -balance;
      totalBalance += signedBalance;
      final salesTotal = MoneyHelper.readCalculatedMoney(cb['sales_total']);
      final purchaseTotal = MoneyHelper.readCalculatedMoney(cb['purchase_total']);
      rows.add({
        'الصندوق': cb['name'] as String? ?? '',
        'النوع': cb['type'] == 'bank' ? 'بنك' : 'صندوق',
        'العملة': cb['currency'] as String? ?? 'YER',
        'الرصيد': balance,
        'حالة الرصيد': isCredit ? 'له' : 'عليه',
        'المبيعات': salesTotal,
        'المشتريات': purchaseTotal,
      });
    }
    final totals = {'إجمالي الأرصدة': totalBalance.abs(), 'عدد الصناديق': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadAccountsWithoutMovementReport({required ReportFilterParams params}) async {
    final accounts = await locator<ReportService>().getAccountsWithoutMovementReport(
      currency: currencyCode(params.selectedCurrency),
      accountType: params.selectedAccountType != 'الكل' ? params.selectedAccountType : null,
    );
    final rows = accounts.map((a) => {
      'كود الحساب': a['account_code'] as String? ?? '',
      'اسم الحساب': a['name_ar'] as String? ?? '',
      'نوع الحساب': accountTypeAr(a['account_type'] as String? ?? ''),
      'العملة': a['currency'] as String? ?? 'YER',
    }).toList();
    final totals = {'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadCustomerStatementReport({required ReportFilterParams params}) async {
    if (params.selectedCustomerId == null) return const ReportLoadResult(rows: [], totals: {});
    final customer = await locator<CustomerRepository>().getAllCustomers();
    final cust = customer.firstWhere((c) => c['id'] == params.selectedCustomerId, orElse: () => <String, dynamic>{});
    final custName = cust['name'] as String? ?? '';
    final custCurrency = cust['currency'] as String? ?? 'YER';

    final txs = await locator<ReportService>().getCustomerStatementReport(
      customerId: params.selectedCustomerId!,
      customerName: custName,
      customerCurrency: custCurrency,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    double running = 0, totalDebit = 0, totalCredit = 0;
    final rows = txs.map((tx) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
      running += (debit - credit);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'عليه (مدين)': debit,
        'له (دائن)': credit,
        'الرصيد': running,
      };
    }).toList();
    final totals = <String, double>{'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'العميل': 0};
    if (custName.isNotEmpty) {
      totals['اسم العميل'] = 0;
    }
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadSupplierStatementReport({required ReportFilterParams params}) async {
    if (params.selectedSupplierId == null) return const ReportLoadResult(rows: [], totals: {});
    final suppliers = await locator<SupplierRepository>().getAllSuppliers();
    final sup = suppliers.firstWhere((s) => s['id'] == params.selectedSupplierId, orElse: () => <String, dynamic>{});
    final supName = sup['name'] as String? ?? '';
    final supCurrency = sup['currency'] as String? ?? 'YER';

    final txs = await locator<ReportService>().getSupplierMovementReport(
      supplierId: params.selectedSupplierId!,
      supplierName: supName,
      supplierCurrency: supCurrency,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    if (txs.isEmpty) return const ReportLoadResult(rows: [], totals: {});
    double running = 0, totalDebit = 0, totalCredit = 0;
    final rows = txs.map((tx) {
      final debit = MoneyHelper.readMoney(tx['debit']);
      final credit = MoneyHelper.readMoney(tx['credit']);
      running += (debit - credit);
      totalDebit += debit;
      totalCredit += credit;
      return {
        'التاريخ': tx['date'] as String? ?? '',
        'البيان': tx['description'] as String? ?? '',
        'عليه (مدين)': debit,
        'له (دائن)': credit,
        'الرصيد': running,
      };
    }).toList();
    final totals = <String, double>{'مدين': totalDebit, 'دائن': totalCredit, 'الرصيد': running, 'المورد': 0};
    if (supName.isNotEmpty) {
      totals['اسم المورد'] = 0;
    }
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadExpensesReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getExpensesReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
      currency: currencyCode(params.selectedCurrency),
    );
    double totalAmount = 0;
    final rows = results.map((r) {
      final amount = MoneyHelper.readMoney(r['amount']);
      totalAmount += amount;
      return {
        'العنوان': r['title'] as String? ?? '',
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['expense_date'] as String? ?? '',
        'الفئة': r['category'] as String? ?? '',
        'طريقة الدفع': r['payment_method'] as String? ?? '',
        'المستفيد': r['beneficiary'] as String? ?? '',
      };
    }).toList();
    final totals = {'إجمالي المصروفات': totalAmount, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadInventoryReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getInventoryReport(
      warehouseId: params.selectedWarehouseId,
      categoryId: params.selectedCategoryId,
    );
    double totalValue = 0;
    final rows = results.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final cost = MoneyHelper.readCalculatedMoney(p['cost_price']);
      final value = stock * cost;
      totalValue += value;
      return {
        'الصنف': p['name_ar'] as String? ?? '',
        'الباركود': p['barcode'] as String? ?? '',
        'الكمية': stock,
        'سعر التكلفة': cost,
        'سعر البيع': MoneyHelper.readCalculatedMoney(p['sell_price']),
        'قيمة المخزون': value,
        'العملة': p['currency'] as String? ?? 'YER',
        'المخزن': p['warehouse_name'] as String? ?? '',
        'الفئة': p['category_name'] as String? ?? '',
      };
    }).toList();
    final totals = {'قيمة المخزون': totalValue, 'عدد الأصناف': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadInventoryMovementReport({required ReportFilterParams params}) async {
    final items = await locator<ReportService>().getInventoryMovementReport(startDate: params.dateFrom, endDate: params.dateTo);
    final rows = items.map((item) {
      final qtyIn = (item['qty_in'] as num?)?.toDouble() ?? 0.0;
      final qtyOut = (item['qty_out'] as num?)?.toDouble() ?? 0.0;
      final revenue = MoneyHelper.readCalculatedMoney(item['total_revenue']);
      final cost = MoneyHelper.readCalculatedMoney(item['total_cost']);
      return {
        'الصنف': (item['name_ar'] ?? item['product_name']) as String? ?? '',
        'الوارد': qtyIn,
        'الصادر': qtyOut,
        'الصافي': qtyIn - qtyOut,
        'إجمالي المبيعات': revenue,
        'إجمالي المشتريات': cost,
      };
    }).toList();
    final totalIn = rows.fold(0.0, (s, r) => s + ((r['الوارد'] as num?)?.toDouble() ?? 0.0));
    final totalOut = rows.fold(0.0, (s, r) => s + ((r['الصادر'] as num?)?.toDouble() ?? 0.0));
    final totalRevenue = rows.fold(0.0, (s, r) => s + ((r['إجمالي المبيعات'] as num?)?.toDouble() ?? 0.0));
    final totalCost = rows.fold(0.0, (s, r) => s + ((r['إجمالي المشتريات'] as num?)?.toDouble() ?? 0.0));
    final totals = {'إجمالي الوارد': totalIn, 'إجمالي الصادر': totalOut, 'الصافي': totalIn - totalOut, 'إجمالي المبيعات': totalRevenue, 'إجمالي المشتريات': totalCost};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadInventoryCostReport() async {
    final items = await locator<ReportService>().getInventoryCostReport();
    double totalCost = 0, totalSell = 0;
    final rows = items.map((item) {
      final costVal = MoneyHelper.readCalculatedMoney(item['stock_cost_value']);
      final sellVal = MoneyHelper.readCalculatedMoney(item['stock_sell_value']);
      totalCost += costVal;
      totalSell += sellVal;
      return {
        'الصنف': (item['name_ar'] ?? item['product_name']) as String? ?? '',
        'الباركود': item['barcode'] as String? ?? '',
        'الكمية': (item['current_stock'] as num?)?.toDouble() ?? 0,
        'سعر التكلفة': MoneyHelper.readCalculatedMoney(item['cost_price']),
        'سعر البيع': MoneyHelper.readCalculatedMoney(item['sell_price']),
        'تكلفة المخزون': costVal,
        'قيمة البيع': sellVal,
        'الفئة': item['category_name'] as String? ?? '',
        'المخزن': item['warehouse_name'] as String? ?? '',
      };
    }).toList();
    final totals = {'تكلفة المخزون': totalCost, 'قيمة البيع': totalSell, 'الربح المتوقع': totalSell - totalCost};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadOutOfStockReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getOutOfStockReport(
      warehouseId: params.selectedWarehouseId,
      categoryId: params.selectedCategoryId,
    );
    final rows = results.map((p) => {
      'الصنف': p['name_ar'] as String? ?? '',
      'الباركود': p['barcode'] as String? ?? '',
      'سعر التكلفة': MoneyHelper.readCalculatedMoney(p['cost_price']),
      'سعر البيع': MoneyHelper.readCalculatedMoney(p['sell_price']),
      'المخزن': p['warehouse_name'] as String? ?? '',
      'الفئة': p['category_name'] as String? ?? '',
    }).toList();
    final totals = {'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadLowStockReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getLowStockReport(
      warehouseId: params.selectedWarehouseId,
      categoryId: params.selectedCategoryId,
    );
    final rows = results.map((p) {
      final stock = (p['current_stock'] as num?)?.toDouble() ?? 0;
      final min = (p['min_stock'] as num?)?.toDouble() ?? 0;
      return {
        'الصنف': p['name_ar'] as String? ?? '',
        'الباركود': p['barcode'] as String? ?? '',
        'الكمية الحالية': stock,
        'الحد الأدنى': min,
        'سعر التكلفة': MoneyHelper.readCalculatedMoney(p['cost_price']),
        'سعر البيع': MoneyHelper.readCalculatedMoney(p['sell_price']),
        'المخزن': p['warehouse_name'] as String? ?? '',
        'الفئة': p['category_name'] as String? ?? '',
      };
    }).toList();
    final totals = {'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadDebtReport({required bool isCustomer}) async {
    final rows = <Map<String, dynamic>>[];
    double totalBalance = 0;
    if (isCustomer) {
      final customers = await locator<CustomerRepository>().getAllCustomers();
      for (final c in customers) {
        final balance = MoneyHelper.readMoney(c['balance']);
        if (balance > 0) {
          totalBalance += balance;
          rows.add({
            'الاسم': c['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (c['balance_type'] as String? ?? 'credit') == 'credit' ? 'له (علينا)' : 'عليه (لنا)',
            'العملة': c['currency'] as String? ?? 'YER',
            'الهاتف': c['phone'] as String? ?? '',
            'سقف الدين': MoneyHelper.readMoney(c['debt_ceiling']),
          });
        }
      }
    } else {
      final suppliers = await locator<SupplierRepository>().getAllSuppliers();
      for (final s in suppliers) {
        final balance = MoneyHelper.readMoney(s['balance']);
        if (balance > 0) {
          totalBalance += balance;
          rows.add({
            'الاسم': s['name'] as String? ?? '',
            'الرصيد': balance,
            'نوع الرصيد': (s['balance_type'] as String? ?? 'debit') == 'debit' ? 'عليه (لنا)' : 'له (علينا)',
            'العملة': s['currency'] as String? ?? 'YER',
            'الهاتف': s['phone'] as String? ?? '',
            'سقف الدين': MoneyHelper.readMoney(s['debt_ceiling']),
          });
        }
      }
    }
    final totals = {'إجمالي الديون': totalBalance, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadCashTransfersReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getCashTransfersReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    double totalAmount = 0;
    final rows = results.map((r) {
      final amount = MoneyHelper.readMoney(r['amount']);
      totalAmount += amount;
      return {
        'من صندوق': r['from_name'] as String? ?? '',
        'إلى صندوق': r['to_name'] as String? ?? '',
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'التاريخ': r['created_at'] as String? ?? '',
        'ملاحظات': r['notes'] as String? ?? '',
      };
    }).toList();
    final totals = {'إجمالي المبالغ': totalAmount, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadCurrencyExchangesReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getCurrencyExchangesReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    final rows = results.map((r) => {
      'من عملة': r['from_currency'] as String? ?? '',
      'إلى عملة': r['to_currency'] as String? ?? '',
      'المبلغ المصروف': MoneyHelper.readMoney(r['from_amount']),
      'المبلغ المستلم': MoneyHelper.readMoney(r['to_amount']),
      'سعر الصرف': (r['exchange_rate'] as num?)?.toDouble() ?? 0,
      'من صندوق': r['from_name'] as String? ?? '',
      'إلى صندوق': r['to_name'] as String? ?? '',
      'التاريخ': r['created_at'] as String? ?? '',
    }).toList();
    final totals = {'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadVouchersReport({required ReportFilterParams params}) async {
    final results = await locator<ReportService>().getVouchersReport(
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    double totalAmount = 0;
    final rows = results.map((r) {
      final amount = MoneyHelper.readMoney(r['total_amount']);
      totalAmount += amount;
      final vType = r['voucher_type'] as String? ?? '';
      String typeAr;
      switch (vType) {
        case 'receipt': typeAr = 'سند قبض'; break;
        case 'payment': typeAr = 'سند صرف'; break;
        default: typeAr = vType;
      }
      return {
        'رقم السند': r['voucher_number'] as String? ?? '',
        'النوع': typeAr,
        'المبلغ': amount,
        'العملة': r['currency'] as String? ?? 'YER',
        'الصندوق': r['cash_box_name'] as String? ?? '',
        'الوصف': r['description'] as String? ?? '',
        'التاريخ': r['date'] as String? ?? '',
      };
    }).toList();
    final totals = {'إجمالي المبالغ': totalAmount, 'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }

  static Future<ReportLoadResult> _loadShiftsReport() async {
    final results = await locator<ReportService>().getShiftsReport();
    final rows = results.map((r) => {
      'رقم الوردية': r['shift_number'] as String? ?? '',
      'الكاشير': r['cashier_name'] as String? ?? '',
      'الصندوق': r['cash_box_name'] as String? ?? '',
      'المبيعات': MoneyHelper.readMoney(r['total_sales']),
      'المرتجعات': MoneyHelper.readMoney(r['total_returns']),
      'الخصومات': MoneyHelper.readMoney(r['total_discounts']),
      'الحالة': (r['status'] as String? ?? '') == 'open' ? 'مفتوحة' : 'مغلقة',
      'تاريخ الفتح': r['opened_at'] as String? ?? '',
      'تاريخ الإغلاق': r['closed_at'] as String? ?? '',
    }).toList();
    final totals = {'العدد': rows.length.toDouble()};
    return ReportLoadResult(rows: rows, totals: totals);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Filter Parameters – passed to data loader
// ═══════════════════════════════════════════════════════════════════

class ReportFilterParams {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String selectedCurrency;
  final int? selectedAccountId;
  final int? selectedCustomerId;
  final int? selectedSupplierId;
  final int? selectedCashBoxId;
  final int? selectedWarehouseId;
  final int? selectedCategoryId;
  final String selectedAccountType;

  const ReportFilterParams({
    this.dateFrom,
    this.dateTo,
    this.selectedCurrency = 'ر.ي',
    this.selectedAccountId,
    this.selectedCustomerId,
    this.selectedSupplierId,
    this.selectedCashBoxId,
    this.selectedWarehouseId,
    this.selectedCategoryId,
    this.selectedAccountType = 'الكل',
  });
}
