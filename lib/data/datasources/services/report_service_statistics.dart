part of 'report_service.dart';

extension ReportServiceStatisticsReports on ReportService {
  // ══════════════════════════════════════════════════════════════
  //  Advanced Statistics / Charts query methods
  // ══════════════════════════════════════════════════════════════

  /// Monthly sales vs purchases for a given [year].
  /// Returns 12 rows (one per month) with `month`, `sales`, `purchases` columns.
  Future<List<Map<String, dynamic>>> getMonthlySalesVsPurchases(int year,
      {String? currency}) async {
    final db = await _db;
    final yearStr = year.toString();
    List<dynamic> args = [yearStr];
    // ignore: unused_local_variable
    String currencyFilter = '';
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND i.currency = ?';
      args.add(currency);
    }
    // Need separate sub-queries with separate arg lists
    final salesArgs = [
      yearStr,
      if (currency != null && currency.isNotEmpty) currency
    ];
    final purchasesArgs = [
      yearStr,
      if (currency != null && currency.isNotEmpty) currency
    ];
    final salesCurrencyFilter =
        currency != null && currency.isNotEmpty ? ' AND currency = ?' : '';
    final purchasesCurrencyFilter =
        currency != null && currency.isNotEmpty ? ' AND currency = ?' : '';

    return await db.rawQuery('''
      SELECT m.month,
        COALESCE(s.total, 0.0) AS sales,
        COALESCE(p.total, 0.0) AS purchases
      FROM (
        SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION
        SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION
        SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
      ) m
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(total) AS total
        FROM invoices
        WHERE type IN ('sale','pos') AND is_return = 0
          AND strftime('%Y', created_at) = ?
          $salesCurrencyFilter
        GROUP BY month
      ) s ON m.month = s.month
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(total) AS total
        FROM invoices
        WHERE type = 'purchase' AND is_return = 0
          AND strftime('%Y', created_at) = ?
          $purchasesCurrencyFilter
        GROUP BY month
      ) p ON m.month = p.month
      ORDER BY m.month
    ''', [...salesArgs, ...purchasesArgs]);
  }

  /// Revenue vs Expense breakdown for a given [year].
  /// Returns rows with `category`, `total`, `type` columns.
  Future<List<Map<String, dynamic>>> getRevenueExpenseBreakdown(int year,
      {String? currency}) async {
    final db = await _db;
    final yearStr = year.toString();
    String currencyFilter = '';
    List<dynamic> currencyArgs = [];
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND currency = ?';
      currencyArgs = [currency];
    }

    final results = <Map<String, dynamic>>[];

    // Revenue by invoice type
    final revenueData = await db.rawQuery('''
      SELECT
        CASE
          WHEN type IN ('sale','pos') AND is_return = 0 THEN 'مبيعات'
          WHEN type = 'purchase' AND is_return = 1 THEN 'مرتجع مشتريات'
          ELSE 'أخرى'
        END AS category,
        SUM(total) AS total,
        'إيرادات' AS type
      FROM invoices
      WHERE (type IN ('sale','pos') AND is_return = 0 OR type = 'purchase' AND is_return = 1)
        AND strftime('%Y', created_at) = ?
        $currencyFilter
      GROUP BY category
    ''', [yearStr, ...currencyArgs]);
    results.addAll(revenueData);

    // Expenses by category
    final expenseData = await db.rawQuery('''
      SELECT
        COALESCE(category, 'مصاريف عامة') AS category,
        SUM(amount) AS total,
        'مصروفات' AS type
      FROM expenses
      WHERE strftime('%Y', expense_date) = ?
        $currencyFilter
      GROUP BY category
    ''', [yearStr, ...currencyArgs]);
    results.addAll(expenseData);

    // ── M-06: إزالة المشتريات من فئة المصروفات ──
    // المشتريات تُرحّل بالكامل إلى المخزون عبر القيود المحاسبية
    // إضافتها كمصاريف يُضاعف المصروفات (COGS محسوب بالفعل من تكلفة الأصناف المباعة)
    // لذا لا نضيف المشتريات كمصاريف مستقلة

    return results;
  }

  /// Daily sales trend for the last [days] days.
  /// Returns rows with `date`, `total` columns.
  Future<List<Map<String, dynamic>>> getDailySalesTrend(int days,
      {String? currency}) async {
    final db = await _db;
    String currencyFilter = '';
    List<dynamic> args = [];
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND currency = ?';
      args.add(currency);
    }
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type IN ('sale','pos') AND is_return = 0
        AND date(created_at) >= ?
        $currencyFilter
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr, ...args]);
  }

  /// Top products by sales amount.
  /// Returns rows with `product_name`, `total_quantity`, `total_amount` columns.
  Future<List<Map<String, dynamic>>> getTopProducts(int limit,
      {String? currency}) async {
    final db = await _db;
    String currencyFilter = '';
    List<dynamic> args = [];
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND i.currency = ?';
      args.add(currency);
    }
    return await db.rawQuery('''
      SELECT ii.product_name,
        SUM(ii.quantity) AS total_quantity,
        SUM(ii.total_price) AS total_amount
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.type IN ('sale','pos') AND i.is_return = 0
        $currencyFilter
      GROUP BY ii.product_name
      ORDER BY total_amount DESC
      LIMIT ?
    ''', [...args, limit]);
  }

  /// Top customer balances.
  /// Returns rows with `name`, `balance`, `balance_type`, `currency` columns.
  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) =>
      _dbHelper.customers.getTopCustomerBalances(limit);

  /// Monthly cash flow (inflow vs outflow) for a given [year].
  /// Returns 12 rows with `month`, `inflow`, `outflow` columns.
  /// Fix #6: Include purchase payments and voucher payments in outflow.
  Future<List<Map<String, dynamic>>> getMonthlyCashFlow(int year,
      {String? currency}) async {
    final db = await _db;
    final yearStr = year.toString();
    final hasCurrencyFilter = currency != null && currency.isNotEmpty;
    final currencyFilter = hasCurrencyFilter ? ' AND currency = ?' : '';
    final invoiceAmountExpr = hasCurrencyFilter
        ? 'paid_amount'
        : 'CAST(ROUND(paid_amount * exchange_rate) AS INTEGER)';
    final expenseAmountExpr = hasCurrencyFilter ? 'amount' : 'amount_base';
    final voucherAmountExpr = hasCurrencyFilter
        ? 'v.total_amount'
        : 'CAST(ROUND(v.total_amount * v.exchange_rate) AS INTEGER)';

    List<dynamic> argsForYearAndOptionalCurrency() => [
          yearStr,
          if (hasCurrencyFilter) currency,
        ];

    return await db.rawQuery('''
      SELECT m.month,
        COALESCE(i.inflow, 0) AS inflow,
        COALESCE(o.outflow, 0) + COALESCE(p.purchase_outflow, 0) + COALESCE(v.voucher_outflow, 0) AS outflow
      FROM (
        SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION
        SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION
        SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
      ) m
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               CAST(COALESCE(SUM($invoiceAmountExpr), 0) AS INTEGER) AS inflow
        FROM invoices
        WHERE type IN ('sale','pos') AND is_return = 0 AND paid_amount > 0
          AND strftime('%Y', created_at) = ?
          $currencyFilter
        GROUP BY month
      ) i ON m.month = i.month
      LEFT JOIN (
        SELECT CAST(strftime('%m', expense_date) AS INTEGER) AS month,
               CAST(COALESCE(SUM($expenseAmountExpr), 0) AS INTEGER) AS outflow
        FROM expenses
        WHERE strftime('%Y', expense_date) = ?
          AND operation_type = 'صرف'
          $currencyFilter
        GROUP BY month
      ) o ON m.month = o.month
      LEFT JOIN (
        -- Fix #6: Include cash purchase payments in outflow
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               CAST(COALESCE(SUM($invoiceAmountExpr), 0) AS INTEGER) AS purchase_outflow
        FROM invoices
        WHERE type = 'purchase' AND is_return = 0 AND payment_mechanism = 'cash' AND paid_amount > 0
          AND strftime('%Y', created_at) = ?
          $currencyFilter
        GROUP BY month
      ) p ON m.month = p.month
      LEFT JOIN (
        -- Fix #6: Include payment voucher outflows (سندات صرف)
        SELECT CAST(strftime('%m', v.date) AS INTEGER) AS month,
               CAST(COALESCE(SUM($voucherAmountExpr), 0) AS INTEGER) AS voucher_outflow
        FROM vouchers v
        WHERE v.voucher_type = 'payment'
          AND strftime('%Y', v.date) = ?
          $currencyFilter
        GROUP BY month
      ) v ON m.month = v.month
      ORDER BY m.month
    ''', [
      ...argsForYearAndOptionalCurrency(),
      ...argsForYearAndOptionalCurrency(),
      ...argsForYearAndOptionalCurrency(),
      ...argsForYearAndOptionalCurrency(),
    ]);
  }

}
