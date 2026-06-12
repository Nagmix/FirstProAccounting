import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';

part 'report_service_daily_inventory.dart';
part 'report_service_statistics.dart';

class ReportService {
  final DatabaseHelper _dbHelper;
  ReportService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Report screen query methods
  //  Extracted from reports_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB integers (cents).
  //  The caller is responsible for converting using
  //  MoneyHelper.readMoney / readCalculatedMoney.
  // ══════════════════════════════════════════════════════════════

  // ── Private filter helpers ────────────────────────────────────

  /// Convenience: builds date filter string and args list.
  static (String, List<dynamic>) buildDateFilter({
    DateTime? dateFrom,
    DateTime? dateTo,
    String column = 'created_at',
  }) {
    String f = '';
    final args = <dynamic>[];
    if (dateFrom != null) {
      f += ' AND $column >= ?';
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      f += ' AND $column < ?';
      args.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }
    return (f, args);
  }

  /// Convenience: builds currency filter string and args list.
  static (String, List<dynamic>) buildCurrencyFilter({
    String? currency,
    String column = 'currency',
  }) {
    if (currency != null && currency.isNotEmpty) {
      return (' AND $column = ?', [currency]);
    }
    return ('', <dynamic>[]);
  }

  // ── 1. Profit / Loss ──────────────────────────────────────────

  /// تقرير الأرباح والخسائر — returns multiple aggregate rows.
  /// Each map key is the raw DB column name; monetary values are
  /// stored as INTEGER (cents). The caller converts with
  /// `MoneyHelper.readCalculatedMoney`.
  Future<List<Map<String, dynamic>>> getProfitLossReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
  }) async {
    final db = await _db;
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo);
    final (cf, curArgs) = buildCurrencyFilter(currency: currency);
    final allArgs = [...dateArgs, ...curArgs];

    // Revenue
    final revRes = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS revenue "
      "FROM invoices WHERE type IN ('sale','pos') AND is_return=0$df$cf",
      allArgs,
    );

    // Purchases
    final purRes = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS purchases "
      "FROM invoices WHERE type='purchase' AND is_return=0$df$cf",
      allArgs,
    );

    // Sales returns
    final retSaleRes = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS sales_returns "
      "FROM invoices WHERE type IN ('sale','pos') AND is_return=1$df$cf",
      allArgs,
    );

    // Purchase returns
    final retPurRes = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS purchase_returns "
      "FROM invoices WHERE type='purchase' AND is_return=1$df$cf",
      allArgs,
    );

    // Expenses (uses expense_date column)
    final (expDf, expDateArgs) = buildDateFilter(
      dateFrom: dateFrom,
      dateTo: dateTo,
      column: 'expense_date',
    );
    final expRes = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(amount), 0) AS INTEGER) AS expenses "
      "FROM expenses WHERE 1=1$expDf$cf",
      [...expDateArgs, ...curArgs],
    );

    // COGS from sales
    final cogsSaleArgs = <dynamic>[];
    String cogsDateF = '';
    if (dateFrom != null) {
      cogsDateF += ' AND i.created_at >= ?';
      cogsSaleArgs.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      cogsDateF += ' AND i.created_at < ?';
      cogsSaleArgs.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }
    if (currency != null && currency.isNotEmpty) {
      cogsDateF += ' AND i.currency = ?';
      cogsSaleArgs.add(currency);
    }

    int cogs = 0;
    try {
      final cogsRes = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END "
        "), 0) AS INTEGER) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = 0$cogsDateF",
        cogsSaleArgs,
      );
      cogs = cogsRes.first['total_cogs'] as int? ?? 0;

      // Subtract COGS from sales returns
      final salesReturnsRaw = retSaleRes.first['sales_returns'] as int? ?? 0;
      if (salesReturnsRaw > 0) {
        final cogsRetArgs = <dynamic>[];
        String cogsRetF = '';
        if (dateFrom != null) {
          cogsRetF += ' AND i.created_at >= ?';
          cogsRetArgs.add(dateFrom.toIso8601String());
        }
        if (dateTo != null) {
          cogsRetF += ' AND i.created_at < ?';
          cogsRetArgs
              .add(dateTo.add(const Duration(days: 1)).toIso8601String());
        }
        if (currency != null && currency.isNotEmpty) {
          cogsRetF += ' AND i.currency = ?';
          cogsRetArgs.add(currency);
        }
        final cogsRetRes = await db.rawQuery(
          "SELECT CAST(COALESCE(SUM("
          "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
          "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END "
          "), 0) AS INTEGER) AS total_cogs "
          "FROM invoice_items ii "
          "INNER JOIN invoices i ON ii.invoice_id = i.id "
          "LEFT JOIN products p ON ii.product_id = p.id "
          "WHERE i.type IN ('sale','pos') AND i.is_return = 1$cogsRetF",
          cogsRetArgs,
        );
        cogs -= (cogsRetRes.first['total_cogs'] as int? ?? 0);
      }
    } catch (_) {
      cogs = 0;
    }

    // ── Chart of Accounts supplement ─────────────────────────────
    // FIX: Include manual journal entries posted directly to
    // REVENUE / EXPENSE accounts that are NOT captured by the
    // invoices/expenses tables. This ensures the P&L report reflects
    // the full general ledger, not just operational tables.
    //
    // OPTIMIZED: Replaced N+1 (iterate accounts + per-account query)
    // with a single query per account type using IN (...) subquery,
    // reducing from 3N+3 queries to just 3 queries total.
    int manualRevenue = 0;
    int manualExpenses = 0;
    int manualCogs = 0;
    try {
      final (acctDf, acctDateArgs) = buildDateFilter(
        dateFrom: dateFrom,
        dateTo: dateTo,
        column: 't.date',
      );

      // Revenue accounts (account_type = 'REVENUE') — credit nature
      // Single query with IN (...) instead of per-account loop
      final revCurrencyFilter =
          currency != null && currency.isNotEmpty ? ' AND a.currency = ?' : '';
      final revCurrencyArgs =
          currency != null && currency.isNotEmpty ? [currency] : <dynamic>[];
      final revRes2 = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(t.credit) - SUM(t.debit), 0) AS INTEGER) AS manual_rev "
        "FROM transactions t "
        "WHERE t.account_id IN (SELECT a.id FROM accounts a WHERE a.account_type = 'REVENUE' AND a.is_active = 1$revCurrencyFilter) "
        "$acctDf "
        // Exclude operational invoice reference types to avoid double-counting
        // table-driven revenue. NULL reference types are treated as manual or
        // legacy journal entries and are included in the manual supplement.
        "AND (t.reference_type IS NULL OR t.reference_type NOT IN ('invoice', 'pos_sale', 'sale', 'pos', 'purchase', 'sale_return', 'purchase_return'))",
        [...revCurrencyArgs, ...acctDateArgs],
      );
      manualRevenue = (revRes2.first['manual_rev'] as int? ?? 0);

      // Expense accounts (account_type = 'EXPENSE') — debit nature
      // Single query with IN (...) instead of per-account loop
      final expCurrencyFilter =
          currency != null && currency.isNotEmpty ? ' AND a.currency = ?' : '';
      final expCurrencyArgs =
          currency != null && currency.isNotEmpty ? [currency] : <dynamic>[];
      final expRes2 = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) AS manual_exp "
        "FROM transactions t "
        "WHERE t.account_id IN (SELECT a.id FROM accounts a WHERE a.account_type = 'EXPENSE' AND a.is_active = 1$expCurrencyFilter) "
        "$acctDf "
        "AND (t.reference_type IS NULL OR t.reference_type NOT IN ('expense', 'expense_reversal', 'expense_reversed', 'invoice', 'sale', 'pos', 'purchase', 'sale_return', 'purchase_return'))",
        [...expCurrencyArgs, ...acctDateArgs],
      );
      manualExpenses = (expRes2.first['manual_exp'] as int? ?? 0);

      // COGS accounts are COST accounts whose base code is 3200.
      // Older data may not have base_code populated, so default currency
      // account codes are kept as a compatibility fallback.
      final cogsCurrencyFilter =
          currency != null && currency.isNotEmpty ? ' AND a.currency = ?' : '';
      final cogsCurrencyArgs =
          currency != null && currency.isNotEmpty ? [currency] : <dynamic>[];
      final cogsRes2 = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(t.debit) - SUM(t.credit), 0) AS INTEGER) AS manual_cogs "
        "FROM transactions t "
        "WHERE t.account_id IN ("
        "  SELECT a.id FROM accounts a "
        "  WHERE a.account_type = 'COST' AND a.is_active = 1 "
        "  AND (a.base_code = 3200 OR a.account_code IN ('3200', '3201', '3202'))"
        "  $cogsCurrencyFilter"
        ") "
        "$acctDf "
        "AND (t.reference_type IS NULL OR t.reference_type NOT IN ('invoice', 'pos_sale', 'sale', 'pos', 'purchase', 'sale_return', 'purchase_return'))",
        [...cogsCurrencyArgs, ...acctDateArgs],
      );
      manualCogs = (cogsRes2.first['manual_cogs'] as int? ?? 0);
    } catch (_) {
      // Non-critical: if chart-of-accounts supplement fails, use zero
    }

    return [
      {
        'item': 'revenue',
        'amount': (revRes.first['revenue'] as int? ?? 0) + manualRevenue
      },
      {'item': 'purchases', 'amount': purRes.first['purchases']},
      {'item': 'sales_returns', 'amount': retSaleRes.first['sales_returns']},
      {
        'item': 'purchase_returns',
        'amount': retPurRes.first['purchase_returns']
      },
      {
        'item': 'expenses',
        'amount': (expRes.first['expenses'] as int? ?? 0) + manualExpenses
      },
      {'item': 'cogs', 'amount': cogs + manualCogs},
      {'item': 'manual_revenue_adjustment', 'amount': manualRevenue},
      {'item': 'manual_expense_adjustment', 'amount': manualExpenses},
      {'item': 'manual_cogs_adjustment', 'amount': manualCogs},
    ];
  }

  // ── 2. Sales by Product ───────────────────────────────────────

  /// المبيعات حسب المنتج — grouped by product_id.
  /// Returns `product_name`, `qty`, `revenue`, `cost_total`, `inv_count`.
  Future<List<Map<String, dynamic>>> getSalesByProductReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    int? categoryId,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'i.created_at');
    args.addAll(dateArgs);
    final (cf, curArgs) =
        buildCurrencyFilter(currency: currency, column: 'i.currency');
    args.addAll(curArgs);

    String catJoin = '';
    String catFilter = '';
    if (categoryId != null) {
      catJoin = ' INNER JOIN products p2 ON ii.product_id=p2.id';
      catFilter = ' AND p2.category_id=?';
      args.add(categoryId);
    }

    return await db.rawQuery(
      "SELECT ii.product_name, SUM(ii.quantity) AS qty, "
      "CAST(SUM(ii.total_price) AS INTEGER) AS revenue, "
      "CAST(SUM("
      "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
      "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
      ") AS INTEGER) AS cost_total, "
      "COUNT(DISTINCT ii.invoice_id) AS inv_count "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id=i.id "
      "LEFT JOIN products p ON ii.product_id=p.id $catJoin "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0$df$cf$catFilter "
      "GROUP BY ii.product_id ORDER BY revenue DESC",
      args,
    );
  }

  // ── 3. Sales by Customer ──────────────────────────────────────

  /// المبيعات حسب العميل — grouped by customer_id.
  /// Returns `customer_name`, `currency`, `inv_count`,
  /// `total_sales`, `total_paid`, `total_remaining`.
  Future<List<Map<String, dynamic>>> getSalesByCustomerReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'i.created_at');
    args.addAll(dateArgs);
    final (cf, curArgs) =
        buildCurrencyFilter(currency: currency, column: 'i.currency');
    args.addAll(curArgs);

    return await db.rawQuery(
      "SELECT COALESCE(c.name, 'بدون عميل') AS customer_name, c.currency, "
      "COUNT(i.id) AS inv_count, "
      "CAST(COALESCE(SUM(i.total), 0) AS INTEGER) AS total_sales, "
      "CAST(COALESCE(SUM(i.paid_amount), 0) AS INTEGER) AS total_paid, "
      "CAST(COALESCE(SUM(i.remaining), 0) AS INTEGER) AS total_remaining "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id=c.id "
      "WHERE i.type IN ('sale','pos') AND i.is_return=0$df$cf "
      "GROUP BY i.customer_id ORDER BY total_sales DESC",
      args,
    );
  }

  // ── 4. Account Movement ───────────────────────────────────────

  /// حركة حساب — transactions for a specific account with date filter.
  /// Returns raw transaction rows. The caller computes running balance
  /// using the account's `balance_type` (fetched separately).
  Future<List<Map<String, dynamic>>> getAccountMovementReport({
    required int accountId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final args = <dynamic>[accountId];
    final (df, dateArgs) =
        buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'date');
    args.addAll(dateArgs);

    return await db.rawQuery(
      "SELECT id, account_id, debit, credit, description, date, created_at "
      "FROM transactions "
      "WHERE account_id = ?$df"
      " ORDER BY date ASC, created_at ASC",
      args,
    );
  }

  /// Gets the `balance_type` for an account ('debit' or 'credit').
  Future<String> getAccountBalanceType(int accountId) async {
    final db = await _db;
    final rows = await db.query('accounts',
        where: 'id = ?', whereArgs: [accountId], limit: 1);
    return rows.isNotEmpty
        ? (rows.first['balance_type'] as String? ?? 'credit')
        : 'credit';
  }

  // ── 5. Supplier Movement (Supplier Statement) ─────────────────

  /// كشف حساب مورد — returns transactions for this specific supplier
  /// using reference_type/reference_id linking (same approach as
  /// getSupplierOpeningBalanceTransactions) plus vouchers and invoices
  /// linked by supplier_id. This avoids the old name-based account lookup
  /// which was returning ALL suppliers' transactions because suppliers
  /// share the same general payable account (code 21xx).
  Future<List<Map<String, dynamic>>> getSupplierMovementReport({
    required int supplierId,
    required String supplierName,
    required String supplierCurrency,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final referenceId = 'supplier_$supplierId';
    final args = <dynamic>[];
    final conditions = <String>[];

    // 1. Opening balance transactions linked by reference_id
    conditions.add('(t.reference_type = ? AND t.reference_id = ?)');
    args.addAll(['opening_balance', referenceId]);

    // 2. Opening balance reversal transactions (so they net out)
    conditions.add('(t.reference_type = ? AND t.reference_id = ?)');
    args.addAll(['opening_balance_reversal', referenceId]);

    // 3. Voucher transactions linked by voucher → supplier_id
    conditions.add(
        '(t.reference_type IN (?, ?, ?, ?) AND t.reference_id IN (SELECT ?||v.id FROM vouchers v WHERE v.supplier_id = ?))');
    args.addAll([
      'receipt',
      'payment',
      'settlement',
      'compound',
      'voucher_',
      supplierId
    ]);

    // 4. Purchase/purchase_return invoice transactions linked by
    //    account 21xx (supplier payable) + invoice's supplier_id.
    //    Invoice journal entries use reference_type = 'purchase' or
    //    'purchase_return' with reference_id = invoice UUID, which
    //    cannot be matched by the supplier_$id pattern. Instead, we
    //    join through the invoices table to find transactions affecting
    //    the supplier's payable account for this supplier's invoices.
    conditions.add('''(
      t.reference_type IN ('purchase', 'purchase_return')
      AND t.account_id IN (
        SELECT a2.id FROM accounts a2 WHERE a2.account_code LIKE '21%' AND a2.currency = ?
      )
      AND EXISTS (
        SELECT 1 FROM invoices i
        WHERE i.supplier_id = ?
          AND i.currency = ?
          AND t.reference_id = i.id
      )
    )''');
    args.addAll([supplierCurrency, supplierId, supplierCurrency]);

    // Date filter
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 't.created_at');
    args.addAll(dateArgs);

    // Also filter by supplier's currency through the account
    return await db.rawQuery('''
      SELECT t.date, t.description, t.debit, t.credit, t.created_at, a.currency
      FROM transactions t
      INNER JOIN accounts a ON t.account_id = a.id
      WHERE (${conditions.join(' OR ')})
        AND a.account_code LIKE '21%'
        AND a.currency = ?
        $df
      ORDER BY t.date ASC, t.created_at ASC
    ''', [...args, supplierCurrency]);
  }

  // ── 6. Customer Balances ──────────────────────────────────────

  /// ديون العملاء — returns all customers with positive balances.
  /// Values are raw DB integers (cents).
  ///
  /// OPTIMIZED: Replaced N+1 per-customer getCustomerBalanceForCurrency()
  /// calls with a single SQL query using subqueries for opening balance,
  /// invoices, and voucher items, aggregated per customer.
  Future<List<Map<String, dynamic>>> getCustomerBalancesReport(
      {String? currency}) async {
    final db = await _db;
    // When a specific currency is requested, compute the per-currency
    // balance using a single SQL query with JOIN + GROUP BY instead of
    // iterating all customers and calling getCustomerBalanceForCurrency().
    if (currency != null && currency.isNotEmpty) {
      try {
        return await db.rawQuery('''
          SELECT c.name, c.phone, c.debt_ceiling, ? AS currency,
            ABS(COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0)) AS balance,
            CASE WHEN (COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0)) >= 0
                 THEN 'credit' ELSE 'debit' END AS balance_type
          FROM customers c
          LEFT JOIN (
            SELECT t.reference_id,
              CAST(COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS INTEGER) AS net
            FROM transactions t
            INNER JOIN accounts a ON t.account_id = a.id
            WHERE t.reference_type = 'opening_balance'
              AND a.account_code LIKE '12%'
              AND a.currency = ?
            GROUP BY t.reference_id
          ) ob ON ob.reference_id = 'customer_' || c.id
          LEFT JOIN (
            SELECT customer_id,
              CAST(SUM(CASE
                WHEN type IN ('sale','pos') AND is_return=0 THEN -total
                WHEN type IN ('sale','pos') AND is_return=1 THEN total
                WHEN type='purchase' AND is_return=0 THEN total
                WHEN type='purchase' AND is_return=1 THEN -total
                ELSE 0
              END) AS INTEGER) AS net
            FROM invoices
            WHERE customer_id IS NOT NULL AND currency = ?
            GROUP BY customer_id
          ) inv ON inv.customer_id = c.id
          LEFT JOIN (
            SELECT v.customer_id,
              CAST(COALESCE(SUM(vi.credit), 0) - COALESCE(SUM(vi.debit), 0) AS INTEGER) AS net
            FROM vouchers v
            INNER JOIN voucher_items vi ON v.id = vi.voucher_id
            INNER JOIN accounts a ON vi.account_id = a.id
            WHERE v.currency = ?
              AND a.account_code LIKE '12%'
            GROUP BY v.customer_id
          ) vch ON vch.customer_id = c.id
          WHERE COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0) != 0
        ''', [currency, currency, currency, currency]);
      } catch (_) {
        // Fallback: voucher_items table may not exist in older DBs
        return await db.rawQuery('''
          SELECT c.name, c.phone, c.debt_ceiling, ? AS currency,
            ABS(COALESCE(ob.net, 0) + COALESCE(inv.net, 0)) AS balance,
            CASE WHEN (COALESCE(ob.net, 0) + COALESCE(inv.net, 0)) >= 0
                 THEN 'credit' ELSE 'debit' END AS balance_type
          FROM customers c
          LEFT JOIN (
            SELECT t.reference_id,
              CAST(COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS INTEGER) AS net
            FROM transactions t
            INNER JOIN accounts a ON t.account_id = a.id
            WHERE t.reference_type = 'opening_balance'
              AND a.account_code LIKE '12%'
              AND a.currency = ?
            GROUP BY t.reference_id
          ) ob ON ob.reference_id = 'customer_' || c.id
          LEFT JOIN (
            SELECT customer_id,
              CAST(SUM(CASE
                WHEN type IN ('sale','pos') AND is_return=0 THEN -total
                WHEN type IN ('sale','pos') AND is_return=1 THEN total
                WHEN type='purchase' AND is_return=0 THEN total
                WHEN type='purchase' AND is_return=1 THEN -total
                ELSE 0
              END) AS INTEGER) AS net
            FROM invoices
            WHERE customer_id IS NOT NULL AND currency = ?
            GROUP BY customer_id
          ) inv ON inv.customer_id = c.id
          WHERE COALESCE(ob.net, 0) + COALESCE(inv.net, 0) != 0
        ''', [currency, currency, currency]);
      }
    }
    // No currency filter — query directly from DB with WHERE instead of
    // loading all customers and filtering in Dart.
    return await db.rawQuery(
      "SELECT name, balance, balance_type, currency, phone, debt_ceiling "
      "FROM customers WHERE CAST(balance AS INTEGER) != 0",
    );
  }

  // ── 7. Supplier Balances ──────────────────────────────────────

  /// ديون الموردين — returns all suppliers with positive balances.
  /// Values are raw DB integers (cents).
  ///
  /// OPTIMIZED: Replaced N+1 per-supplier getSupplierBalanceForCurrency()
  /// calls with a single SQL query using subqueries for opening balance,
  /// invoices, and voucher items, aggregated per supplier.
  Future<List<Map<String, dynamic>>> getSupplierBalancesReport(
      {String? currency}) async {
    final db = await _db;
    if (currency != null && currency.isNotEmpty) {
      try {
        return await db.rawQuery('''
          SELECT s.name, s.phone, s.debt_ceiling, ? AS currency,
            ABS(COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0)) AS balance,
            CASE WHEN (COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0)) >= 0
                 THEN 'credit' ELSE 'debit' END AS balance_type
          FROM suppliers s
          LEFT JOIN (
            SELECT t.reference_id,
              CAST(COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS INTEGER) AS net
            FROM transactions t
            INNER JOIN accounts a ON t.account_id = a.id
            WHERE t.reference_type = 'opening_balance'
              AND a.account_code LIKE '21%'
              AND a.currency = ?
            GROUP BY t.reference_id
          ) ob ON ob.reference_id = 'supplier_' || s.id
          LEFT JOIN (
            SELECT supplier_id,
              CAST(SUM(CASE
                WHEN type='purchase' AND is_return=0 THEN total
                WHEN type='purchase' AND is_return=1 THEN -total
                WHEN type IN ('sale','pos') AND is_return=0 THEN -total
                WHEN type IN ('sale','pos') AND is_return=1 THEN total
                ELSE 0
              END) AS INTEGER) AS net
            FROM invoices
            WHERE supplier_id IS NOT NULL AND currency = ?
            GROUP BY supplier_id
          ) inv ON inv.supplier_id = s.id
          LEFT JOIN (
            SELECT v.supplier_id,
              CAST(COALESCE(SUM(vi.credit), 0) - COALESCE(SUM(vi.debit), 0) AS INTEGER) AS net
            FROM vouchers v
            INNER JOIN voucher_items vi ON v.id = vi.voucher_id
            INNER JOIN accounts a ON vi.account_id = a.id
            WHERE v.currency = ?
                AND a.account_code LIKE '21%'
            GROUP BY v.supplier_id
          ) vch ON vch.supplier_id = s.id
          WHERE COALESCE(ob.net, 0) + COALESCE(inv.net, 0) + COALESCE(vch.net, 0) != 0
        ''', [currency, currency, currency, currency]);
      } catch (_) {
        // Fallback: voucher_items table may not exist in older DBs
        return await db.rawQuery('''
          SELECT s.name, s.phone, s.debt_ceiling, ? AS currency,
            ABS(COALESCE(ob.net, 0) + COALESCE(inv.net, 0)) AS balance,
            CASE WHEN (COALESCE(ob.net, 0) + COALESCE(inv.net, 0)) >= 0
                 THEN 'credit' ELSE 'debit' END AS balance_type
          FROM suppliers s
          LEFT JOIN (
            SELECT t.reference_id,
              CAST(COALESCE(SUM(t.credit), 0) - COALESCE(SUM(t.debit), 0) AS INTEGER) AS net
            FROM transactions t
            INNER JOIN accounts a ON t.account_id = a.id
            WHERE t.reference_type = 'opening_balance'
              AND a.account_code LIKE '21%'
              AND a.currency = ?
            GROUP BY t.reference_id
          ) ob ON ob.reference_id = 'supplier_' || s.id
          LEFT JOIN (
            SELECT supplier_id,
              CAST(SUM(CASE
                WHEN type='purchase' AND is_return=0 THEN total
                WHEN type='purchase' AND is_return=1 THEN -total
                WHEN type IN ('sale','pos') AND is_return=0 THEN -total
                WHEN type IN ('sale','pos') AND is_return=1 THEN total
                ELSE 0
              END) AS INTEGER) AS net
            FROM invoices
            WHERE supplier_id IS NOT NULL AND currency = ?
            GROUP BY supplier_id
          ) inv ON inv.supplier_id = s.id
          WHERE COALESCE(ob.net, 0) + COALESCE(inv.net, 0) != 0
        ''', [currency, currency, currency]);
      }
    }
    // No currency filter — query directly from DB with WHERE instead of
    // loading all suppliers and filtering in Dart.
    return await db.rawQuery(
      "SELECT name, balance, balance_type, currency, phone, debt_ceiling "
      "FROM suppliers WHERE CAST(balance AS INTEGER) != 0",
    );
  }

  // ── 8. Expenses ───────────────────────────────────────────────

  /// تقرير المصروفات — returns expense rows filtered by date/currency.
  Future<List<Map<String, dynamic>>> getExpensesReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'expense_date');
    args.addAll(dateArgs);
    final (cf, curArgs) = buildCurrencyFilter(currency: currency);
    args.addAll(curArgs);

    return await db.rawQuery(
      "SELECT title, amount, currency, expense_date, category, payment_method, beneficiary "
      "FROM expenses WHERE 1=1$df$cf ORDER BY expense_date DESC",
      args,
    );
  }

  // ── 9. Cash Boxes ─────────────────────────────────────────────

  /// حركة الصندوق — returns cash box data with per‑box sales/purchase
  /// totals.
  ///
  /// OPTIMIZED: Replaced Dart loop over cash boxes + per-box SQL query
  /// with a single SQL query using LEFT JOIN + conditional aggregation.
  Future<List<Map<String, dynamic>>> getCashBoxesReport({
    String? currency,
    int? cashBoxId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'i.created_at');
    args.addAll(dateArgs);

    String whereExtra = '';
    if (currency != null && currency.isNotEmpty) {
      whereExtra += ' AND cb.currency = ?';
      args.add(currency);
    }
    if (cashBoxId != null) {
      whereExtra += ' AND cb.id = ?';
      args.add(cashBoxId);
    }

    final results = await db.rawQuery('''
      SELECT cb.id, cb.name, cb.type, cb.currency, cb.balance, cb.balance_type,
        CAST(COALESCE(SUM(CASE WHEN i.type IN ('sale','pos') AND i.is_return=0 THEN i.total ELSE 0 END), 0) AS INTEGER) AS sales_total,
        CAST(COALESCE(SUM(CASE WHEN i.type='purchase' AND i.is_return=0 THEN i.total ELSE 0 END), 0) AS INTEGER) AS purchase_total
      FROM cash_boxes cb
      LEFT JOIN invoices i ON i.cash_box_id = cb.id AND i.is_return = 0$df
      WHERE 1=1$whereExtra
      GROUP BY cb.id
    ''', args);

    return results;
  }

  // ── 10. Currency Exchanges ────────────────────────────────────

  /// صرافة العملات — returns currency exchange rows with box names.
  Future<List<Map<String, dynamic>>> getCurrencyExchangesReport({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'ce.created_at');

    return await db.rawQuery(
      "SELECT ce.*, cb1.name AS from_name, cb2.name AS to_name "
      "FROM currency_exchanges ce LEFT JOIN cash_boxes cb1 ON ce.from_cash_box_id=cb1.id "
      "LEFT JOIN cash_boxes cb2 ON ce.to_cash_box_id=cb2.id "
      "WHERE 1=1$df ORDER BY ce.created_at DESC",
      dateArgs,
    );
  }

  // ── 11. Vouchers ──────────────────────────────────────────────

  /// السندات — returns voucher rows with cash box name.
  Future<List<Map<String, dynamic>>> getVouchersReport({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'v.created_at');

    return await db.rawQuery(
      "SELECT v.*, cb.name AS cash_box_name "
      "FROM vouchers v LEFT JOIN cash_boxes cb ON v.cash_box_id=cb.id "
      "WHERE 1=1$df ORDER BY v.created_at DESC",
      dateArgs,
    );
  }

  // ── 12. Shifts ────────────────────────────────────────────────

  /// الورديات — returns shift rows ordered by opened_at DESC.
  Future<List<Map<String, dynamic>>> getShiftsReport() async {
    return await _dbHelper.shifts.getAllShifts(orderBy: 'opened_at DESC');
  }

  // ── 13. Sales Report (invoices with entity names) ─────────────

  static const Map<String, String> _salesReportTypeFilterWhitelist = {
    "i.type IN ('sale','pos') AND i.is_return=0":
        "i.type IN ('sale','pos') AND i.is_return=0",
    "i.type='purchase' AND i.is_return=0":
        "i.type='purchase' AND i.is_return=0",
    "i.type IN ('sale','pos') AND i.is_return=1":
        "i.type IN ('sale','pos') AND i.is_return=1",
    "i.type='purchase' AND i.is_return=1":
        "i.type='purchase' AND i.is_return=1",
  };

  /// تقرير المبيعات/المشتريات/المرتجعات — returns invoice rows
  /// with entity name (customer or supplier).
  /// [typeFilter] must match one of the internal whitelist fragments above.
  Future<List<Map<String, dynamic>>> getSalesReport({
    required String typeFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    int? cashBoxId,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final whitelistedTypeFilter = _salesReportTypeFilterWhitelist[typeFilter];
    if (whitelistedTypeFilter == null) {
      throw ArgumentError.value(
          typeFilter, 'typeFilter', 'فلتر تقرير المبيعات غير مسموح');
    }
    String whereClause = whitelistedTypeFilter;

    if (dateFrom != null) {
      whereClause += ' AND i.created_at >= ?';
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      whereClause += ' AND i.created_at < ?';
      args.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }
    if (currency != null && currency.isNotEmpty) {
      whereClause += ' AND i.currency = ?';
      args.add(currency);
    }
    if (cashBoxId != null) {
      whereClause += ' AND i.cash_box_id = ?';
      args.add(cashBoxId);
    }

    return await db.rawQuery(
      "SELECT i.id, i.type, i.is_return, i.total, i.subtotal, i.discount_amount, i.paid_amount, "
      "i.remaining, i.currency, i.created_at, i.cash_box_id, "
      "COALESCE(c.name, s.name, 'بدون') AS entity_name "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id=c.id "
      "LEFT JOIN suppliers s ON i.supplier_id=s.id "
      "WHERE $whereClause ORDER BY i.created_at DESC",
      args,
    );
  }

  // ── 14. All Account Movement ──────────────────────────────────

  /// حركة جميع الحسابات — returns all transactions with account info.
  Future<List<Map<String, dynamic>>> getAllAccountMovementReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    String? accountType,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 't.created_at');
    args.addAll(dateArgs);
    String cf = '';
    if (currency != null && currency.isNotEmpty) {
      cf = ' AND a.currency = ?';
      args.add(currency);
    }
    if (accountType != null &&
        accountType.isNotEmpty &&
        accountType != 'الكل') {
      cf += ' AND a.account_type = ?';
      args.add(accountType);
    }

    return await db.rawQuery(
      "SELECT t.id, t.account_id, t.debit, t.credit, t.description, t.date, t.created_at, "
      "a.name_ar AS account_name, a.account_code, a.currency "
      "FROM transactions t LEFT JOIN accounts a ON t.account_id=a.id "
      "WHERE 1=1$df$cf "
      "ORDER BY t.date DESC, t.created_at DESC",
      args,
    );
  }

  // ── 15. Trial Balance ─────────────────────────────────────────

  /// ميزان المراجعة — returns accounts with their date-filtered
  /// debit/credit balances. Each row has:
  /// `account_code`, `name_ar`, `account_type`, `currency`,
  /// `debit`, `credit` (raw INTEGER cents).
  ///
  /// OPTIMIZED: Replaced N+1 (iterate accounts + per-account balance query)
  /// with a single SQL using LEFT JOIN transactions + GROUP BY (same
  /// approach as getTrialBalanceData which already does this correctly).
  Future<List<Map<String, dynamic>>> getTrialBalanceReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    String? accountType,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    final (df, dateArgs) =
        buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 't.date');
    args.addAll(dateArgs);

    String cf = '';
    if (currency != null && currency.isNotEmpty) {
      cf = ' AND a.currency = ?';
      args.add(currency);
    }
    if (accountType != null &&
        accountType.isNotEmpty &&
        accountType != 'الكل') {
      cf += ' AND a.account_type = ?';
      args.add(accountType);
    }

    final rawResults = await db.rawQuery(
      "SELECT a.account_code, a.name_ar, a.account_type, a.currency, "
      "CAST(COALESCE(SUM(t.debit), 0) - COALESCE(SUM(t.credit), 0) AS INTEGER) AS net_balance "
      "FROM accounts a "
      "LEFT JOIN transactions t ON t.account_id = a.id$df "
      "WHERE a.is_active = 1$cf "
      "GROUP BY a.id "
      "HAVING net_balance != 0",
      args,
    );

    // Split net balance into debit/credit sides
    return rawResults.map((row) {
      final netBalance = row['net_balance'] as int? ?? 0;
      final isDebit = netBalance > 0;
      return {
        'account_code': row['account_code'],
        'name_ar': row['name_ar'],
        'account_type': row['account_type'],
        'currency': row['currency'],
        'debit': isDebit ? netBalance.abs() : 0,
        'credit': isDebit ? 0 : netBalance.abs(),
      };
    }).toList();
  }

  // ── 15b. Consolidated Trial Balance (base currency) ────────────

  /// ميزان المراجعة التجميعي — converts all currency balances to
  /// the base currency (YER) using the current rate from the currencies
  /// table.
  ///
  /// Returns the same structure as `getTrialBalanceReport` but with
  /// all amounts converted to the base currency, plus `base_currency`
  /// and `total_debit_base` / `total_credit_base` summary fields.
  ///
  /// OPTIMIZED: Replaced N+1 (iterate accounts + per-account balance query)
  /// plus Dart-side currency conversion with a single SQL query using
  /// LEFT JOIN transactions + GROUP BY + currencies table for conversion.
  Future<List<Map<String, dynamic>>> getConsolidatedTrialBalanceReport({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? accountType,
  }) async {
    final String baseCurrency = await locator<BaseCurrencyService>().getBaseCurrencyCode();
    final db = await _db;

    final args = <dynamic>[];
    final (df, dateArgs) =
        buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 't.date');
    args.addAll(dateArgs);

    String atFilter = '';
    if (accountType != null &&
        accountType.isNotEmpty &&
        accountType != 'الكل') {
      atFilter = ' AND a.account_type = ?';
      args.add(accountType);
    }

    // Single query: LEFT JOIN transactions for balance, LEFT JOIN currencies
    // for exchange rate, compute both original and base-currency balances.
    final rawResults = await db.rawQuery('''
      SELECT a.account_code, a.name_ar, a.account_type, a.currency,
        CAST(COALESCE(SUM(t.debit), 0) - COALESCE(SUM(t.credit), 0) AS INTEGER) AS balance_original,
        CASE WHEN a.currency = ? THEN 1.0 ELSE COALESCE(cur.rate, 1.0) END AS exchange_rate_used,
        CAST(ROUND(
          (COALESCE(SUM(t.debit), 0) - COALESCE(SUM(t.credit), 0)) *
          CASE WHEN a.currency = ? THEN 1.0 ELSE COALESCE(cur.rate, 1.0) END
        ) AS INTEGER) AS balance_base
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id$df
      LEFT JOIN (
        SELECT code, MAX(exchange_rate) AS rate FROM currencies WHERE is_active = 1 GROUP BY code
      ) cur ON cur.code = a.currency
      WHERE a.is_active = 1$atFilter
      GROUP BY a.id
      HAVING balance_base != 0
    ''', [baseCurrency, baseCurrency, ...args]);

    // Split balances into debit/credit sides
    return rawResults.map((row) {
      final balanceOriginal = row['balance_original'] as int? ?? 0;
      final balanceBase = row['balance_base'] as int? ?? 0;
      final rateUsed = (row['exchange_rate_used'] as num?)?.toDouble() ?? 1.0;
      final isDebitBase = balanceBase > 0;
      final isDebitOriginal = balanceOriginal > 0;
      return {
        'account_code': row['account_code'],
        'name_ar': row['name_ar'],
        'account_type': row['account_type'],
        'currency': row['currency'],
        'base_currency': baseCurrency,
        'debit': isDebitBase ? balanceBase.abs() : 0,
        'credit': isDebitBase ? 0 : balanceBase.abs(),
        'debit_original': isDebitOriginal ? balanceOriginal.abs() : 0,
        'credit_original': isDebitOriginal ? 0 : balanceOriginal.abs(),
        'exchange_rate_used': rateUsed,
      };
    }).toList();
  }

  // ── 16. Customer Statement ────────────────────────────────────

  /// كشف حساب عميل — finds the customer's receivable account and
  /// returns its transactions. Returns empty list if no linked
  /// account is found.
  Future<List<Map<String, dynamic>>> getCustomerStatementReport({
    required int customerId,
    required String customerName,
    required String customerCurrency,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;

    // Find the customer's receivable account by code (12xx) and currency.
    // This is more reliable than searching by name, which breaks if the
    // account name does not exactly match the customer name.
    final codeOffset = await locator<BaseCurrencyService>().getOffsetForCurrency(customerCurrency);
    final accountCode = '${1200 + codeOffset}';
    var acctRes = await db.rawQuery(
      "SELECT id FROM accounts WHERE account_code=? AND currency=? AND is_active=1 LIMIT 1",
      [accountCode, customerCurrency],
    );

    // Fallback to name-based search for legacy data
    if (acctRes.isEmpty) {
      acctRes = await db.rawQuery(
        "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1",
        [customerName, customerCurrency],
      );
    }
    if (acctRes.isEmpty && customerName.isNotEmpty) {
      acctRes = await db.rawQuery(
        "SELECT id FROM accounts WHERE (name_ar LIKE ? OR name_ar LIKE ?) AND currency=? LIMIT 1",
        ['%$customerName%', '%$customerName%', customerCurrency],
      );
    }
    if (acctRes.isEmpty) return [];

    final accountId = acctRes.first['id'] as int;
    final args = <dynamic>[accountId];
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 't.created_at');
    args.addAll(dateArgs);

    return await db.rawQuery(
      "SELECT t.date, t.description, t.debit, t.credit, t.created_at "
      "FROM transactions t WHERE t.account_id=?$df ORDER BY t.date ASC, t.created_at ASC",
      args,
    );
  }

  // ── 17. Inventory Report ──────────────────────────────────────

  /// تقرير المخزون — returns all active products with stock info.
  Future<List<Map<String, dynamic>>> getInventoryReport({
    int? warehouseId,
    int? categoryId,
  }) async {
    final db = await _db;
    String whereExtra = '';
    final args = <dynamic>[];
    if (warehouseId != null) {
      whereExtra += ' AND p.warehouse_id=?';
      args.add(warehouseId);
    }
    if (categoryId != null) {
      whereExtra += ' AND p.category_id=?';
      args.add(categoryId);
    }

    return await db.rawQuery(
      "SELECT p.name_ar, p.barcode, p.item_code, p.current_stock, "
      "CAST(COALESCE(NULLIF(p.average_cost, 0), p.cost_price) AS INTEGER) AS cost_price, "
      "CAST(p.sell_price AS INTEGER) AS sell_price, "
      "p.min_stock, p.currency, w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1$whereExtra ORDER BY p.name_ar",
      args,
    );
  }

  // ── 18. Out of Stock ──────────────────────────────────────────

  /// الأصناف المنتهية — products with zero or negative stock.
  Future<List<Map<String, dynamic>>> getOutOfStockReport({
    int? warehouseId,
    int? categoryId,
  }) async {
    final db = await _db;
    String whereExtra = '';
    final args = <dynamic>[];
    if (warehouseId != null) {
      whereExtra += ' AND p.warehouse_id=?';
      args.add(warehouseId);
    }
    if (categoryId != null) {
      whereExtra += ' AND p.category_id=?';
      args.add(categoryId);
    }

    return await db.rawQuery(
      "SELECT p.name_ar, p.barcode, p.item_code, p.cost_price, p.sell_price, "
      "w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1 AND p.current_stock <= 0$whereExtra ORDER BY p.name_ar",
      args,
    );
  }

  // ── 19. Low Stock ─────────────────────────────────────────────

  /// الأصناف قاربت على النفاد — products with stock <= min_stock.
  Future<List<Map<String, dynamic>>> getLowStockReport({
    int? warehouseId,
    int? categoryId,
  }) async {
    final db = await _db;
    String whereExtra = '';
    final args = <dynamic>[];
    if (warehouseId != null) {
      whereExtra += ' AND p.warehouse_id=?';
      args.add(warehouseId);
    }
    if (categoryId != null) {
      whereExtra += ' AND p.category_id=?';
      args.add(categoryId);
    }

    return await db.rawQuery(
      "SELECT p.name_ar, p.barcode, p.current_stock, p.min_stock, p.cost_price, p.sell_price, "
      "w.name AS warehouse_name, c.name AS category_name "
      "FROM products p LEFT JOIN warehouses w ON p.warehouse_id=w.id "
      "LEFT JOIN categories c ON p.category_id=c.id "
      "WHERE p.is_active=1 AND p.current_stock > 0 AND p.current_stock <= p.min_stock$whereExtra ORDER BY p.name_ar",
      args,
    );
  }

  // ── 20. Cash Transfers ────────────────────────────────────────

  /// تحويلات الصناديق — returns cash transfer rows with box names.
  Future<List<Map<String, dynamic>>> getCashTransfersReport({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final (df, dateArgs) = buildDateFilter(
        dateFrom: dateFrom, dateTo: dateTo, column: 'ct.created_at');

    return await db.rawQuery(
      "SELECT ct.*, cb1.name AS from_name, cb2.name AS to_name "
      "FROM cash_transfers ct LEFT JOIN cash_boxes cb1 ON ct.from_cash_box_id=cb1.id "
      "LEFT JOIN cash_boxes cb2 ON ct.to_cash_box_id=cb2.id "
      "WHERE 1=1$df ORDER BY ct.created_at DESC",
      dateArgs,
    );
  }

  // ── 21. Accounts Without Movement ─────────────────────────────

  /// حسابات بدون حركة — accounts with zero transaction count.
  Future<List<Map<String, dynamic>>> getAccountsWithoutMovementReport({
    String? currency,
    String? accountType,
  }) async {
    final accounts = await _dbHelper.accounts.getAccountsWithoutMovements();
    // Apply optional filters
    return accounts.where((a) {
      if (currency != null &&
          currency.isNotEmpty &&
          a['currency'] != currency) {
        return false;
      }
      if (accountType != null &&
          accountType.isNotEmpty &&
          accountType != 'الكل') {
        if (a['account_type'] != accountType) return false;
      }
      return true;
    }).toList();
  }

  // ── 22. Trial Balance Data (for trial_balance_screen.dart) ────

  /// Fetches trial balance data with currency and date filters.
  /// Returns raw rows with account info and total_debit/total_credit (INTEGER cents).
  Future<List<Map<String, dynamic>>> getTrialBalanceData({
    String? currency,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final dateArgs = <dynamic>[];
    String dateFilter = '';
    if (dateFrom != null) {
      dateFilter += ' AND t.date >= ?';
      dateArgs.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      dateFilter += ' AND t.date < ?';
      dateArgs.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }

    final currencyArgs = <dynamic>[];
    String currencyFilter = '';
    if (currency != null) {
      currencyFilter = ' AND a.currency = ?';
      currencyArgs.add(currency);
    }

    return await db.rawQuery(
      "SELECT a.id, a.account_code, a.name_ar, a.account_type, a.balance_type, a.currency, "
      "COALESCE(SUM(t.debit), 0) as total_debit, "
      "COALESCE(SUM(t.credit), 0) as total_credit "
      "FROM accounts a "
      "LEFT JOIN transactions t ON t.account_id = a.id$dateFilter "
      "WHERE a.is_active = 1$currencyFilter "
      "GROUP BY a.id "
      "HAVING total_debit > 0 OR total_credit > 0 "
      "ORDER BY a.account_code",
      [...dateArgs, ...currencyArgs],
    );
  }

  // ── 23. Financial Statements Data (for financial_statements_screen.dart) ─

  /// Fetches financial statements data with account type, currency, and date filters.
  /// Returns raw rows with account info and total_debit/total_credit (INTEGER cents).
  Future<List<Map<String, dynamic>>> getFinancialStatementsData({
    required List<String> accountTypes,
    String? currency,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;

    final dateArgs = <dynamic>[];
    String dateFilter = '';
    if (dateFrom != null) {
      dateFilter += ' AND t.date >= ?';
      dateArgs.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      dateFilter += ' AND t.date < ?';
      dateArgs.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }

    final currencyArgs = <dynamic>[];
    String currencyFilter = '';
    if (currency != null) {
      currencyFilter = ' AND a.currency = ?';
      currencyArgs.add(currency);
    }

    return await db.rawQuery(
      "SELECT a.id, a.account_code, a.name_ar, a.account_type, a.balance_type, a.currency, "
      "COALESCE(SUM(t.debit), 0) as total_debit, "
      "COALESCE(SUM(t.credit), 0) as total_credit "
      "FROM accounts a "
      "LEFT JOIN transactions t ON t.account_id = a.id$dateFilter "
      "WHERE a.is_active = 1 AND a.account_type IN (${accountTypes.map((_) => '?').join(',')})$currencyFilter "
      "GROUP BY a.id "
      "HAVING total_debit > 0 OR total_credit > 0 "
      "ORDER BY a.account_code",
      [...dateArgs, ...accountTypes, ...currencyArgs],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Aggregate query methods
  // ══════════════════════════════════════════════════════════════

  /// ملخص الأرباح والخسائر — returns a single map with keys:
  /// `revenue`, `purchases`, `sales_returns`, `purchase_returns`,
  /// `expenses`, `cogs`. All values are raw INTEGER (cents).
  Future<Map<String, dynamic>> getProfitLossSummary({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
  }) async {
    final rows = await getProfitLossReport(
      dateFrom: dateFrom,
      dateTo: dateTo,
      currency: currency,
    );
    final map = <String, dynamic>{};
    for (final row in rows) {
      map[row['item'] as String] = row['amount'];
    }
    return map;
  }

  /// تكلفة البضاعة المباعة (COGS) — returns the COGS amount as raw
  /// INTEGER (cents). Set [isReturn] to true for sales‑return COGS.
  Future<int> getCOGS({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    bool isReturn = false,
  }) async {
    final db = await _db;
    final args = <dynamic>[];
    String df = '';
    if (dateFrom != null) {
      df += ' AND i.created_at >= ?';
      args.add(dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      df += ' AND i.created_at < ?';
      args.add(dateTo.add(const Duration(days: 1)).toIso8601String());
    }
    if (currency != null && currency.isNotEmpty) {
      df += ' AND i.currency = ?';
      args.add(currency);
    }

    final returnFlag = isReturn ? 1 : 0;
    try {
      final res = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END "
        "), 0) AS INTEGER) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = ?$df",
        [returnFlag, ...args],
      );
      return res.first['total_cogs'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Statistics screen query methods
  //  Extracted from statistics_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB values.
  //  The caller is responsible for converting using
  //  MoneyHelper.readMoney / readCalculatedMoney.
  // ══════════════════════════════════════════════════════════════

  /// أفضل العملاء مبيعات — top customers by sales amount since [monthStart].
  /// Returns rows with: id, name, total_sales.
  Future<List<Map<String, dynamic>>> getTopCustomersBySales(String monthStart,
      {int limit = 5}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT c.id, c.name, CAST(COALESCE(SUM(i.total), 0) AS INTEGER) AS total_sales
      FROM customers c
      LEFT JOIN invoices i ON i.customer_id = c.id AND i.type IN ('sale', 'pos') AND i.is_return = 0 AND date(i.created_at) >= ?
      GROUP BY c.id
      HAVING total_sales > 0
      ORDER BY total_sales DESC
      LIMIT ?
    ''', [monthStart, limit]);
  }

  /// توزيع العملات — invoice currency breakdown since [monthStart].
  /// Returns rows with: currency, total.
  Future<List<Map<String, dynamic>>> getInvoiceCurrencyBreakdown(
      String monthStart) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT i.currency, CAST(COALESCE(SUM(i.total), 0) AS INTEGER) AS total
      FROM invoices i
      WHERE i.is_return = 0 AND date(i.created_at) >= ?
      GROUP BY i.currency
      ORDER BY total DESC
    ''', [monthStart]);
  }

  // ══════════════════════════════════════════════════════════════
  //  POS screen query methods
  //  Extracted from pos_screen.dart — raw SQL, no MoneyHelper.
  //  All monetary values are returned as raw DB values.
  // ══════════════════════════════════════════════════════════════

  /// الأكثر مبيعاً اليوم — top selling products for a given day.
  /// [todayStr] should be in 'YYYY-MM-DD' format.
  /// Returns rows with: product_id, product_name, total_qty.
  Future<List<Map<String, dynamic>>> getTopSellersToday(String todayStr,
      {int limit = 5}) async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT ii.product_id, ii.product_name, SUM(ii.quantity) AS total_qty "
      "FROM invoice_items ii INNER JOIN invoices i ON ii.invoice_id = i.id "
      "WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 AND i.created_at LIKE ? "
      "GROUP BY ii.product_id ORDER BY total_qty DESC LIMIT ?",
      ['$todayStr%', limit],
    );
  }

  /// عدد الورديات اليوم — count of shifts opened on a given date.
  /// Used for shift number generation.
  Future<int> getShiftCountForDate(DateTime date) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM shifts WHERE date(opened_at) = date(?)",
      [date.toIso8601String()],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ══════════════════════════════════════════════════════════════
  //  Debt report helpers (used by ReportDataLoader)
  //  OPTIMIZED: Direct SQL with WHERE filter instead of fetching
  //  all entities and filtering in Dart.
  // ══════════════════════════════════════════════════════════════

  /// جلب عملاء لديهم رصيد موجب — returns customers with balance > 0.
  /// Values are raw DB integers (cents).
  Future<List<Map<String, dynamic>>> getCustomerDebts() async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT name, balance, balance_type, currency, phone, debt_ceiling "
      "FROM customers WHERE CAST(balance AS INTEGER) > 0",
    );
  }

  /// جلب موردين علينا دين لهم — returns suppliers with credit balance
  /// (money we owe them). Values are raw DB integers (cents).
  Future<List<Map<String, dynamic>>> getSupplierDebts() async {
    final db = await _db;
    return await db.rawQuery(
      "SELECT name, balance, balance_type, currency, phone, debt_ceiling "
      "FROM suppliers WHERE CAST(balance AS INTEGER) > 0 AND balance_type = 'credit'",
    );
  }
}
