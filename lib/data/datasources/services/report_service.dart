import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class ReportService {
  final DatabaseHelper _dbHelper;
  ReportService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  العمليات اليومية والتقارير الإضافية
  //  Daily Operations & Additional Reports
  // ══════════════════════════════════════════════════════════════

  /// جلب العمليات اليومية المجمعة لتاريخ محدد
  /// Returns combined list of all daily transactions for a specific date.
  Future<List<Map<String, dynamic>>> getDailyOperations(DateTime date) async {
    final db = await _db;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final startStr = dayStart.toIso8601String();
    final endStr = dayEnd.toIso8601String();

    final List<Map<String, dynamic>> operations = [];

    // فواتير المبيعات
    final saleInvoices = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.created_at, i.currency, "
      "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') "
      "ELSE 'بدون عميل' END AS entity_name "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id "
      "WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 "
      "AND i.created_at >= ? AND i.created_at < ? "
      "ORDER BY i.created_at DESC",
      [startStr, endStr],
    );
    for (final row in saleInvoices) {
      operations.add({
        'type': 'sale_invoice',
        'type_label': 'فاتورة مبيعات',
        'id': row['id'],
        'entity_name': row['entity_name'],
        'amount': MoneyHelper.readCalculatedMoney(row['total']),
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // فواتير المشتريات
    final purchaseInvoices = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.created_at, i.currency, "
      "CASE WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') "
      "ELSE 'بدون مورد' END AS entity_name "
      "FROM invoices i LEFT JOIN suppliers s ON i.supplier_id = s.id "
      "WHERE i.type = 'purchase' AND i.is_return = 0 "
      "AND i.created_at >= ? AND i.created_at < ? "
      "ORDER BY i.created_at DESC",
      [startStr, endStr],
    );
    for (final row in purchaseInvoices) {
      operations.add({
        'type': 'purchase_invoice',
        'type_label': 'فاتورة مشتريات',
        'id': row['id'],
        'entity_name': row['entity_name'],
        'amount': MoneyHelper.readCalculatedMoney(row['total']),
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // سندات القبض والصرف (باستخدام try/catch لأن الجدول قد لا يكون موجوداً)
    try {
      final vouchers = await db.rawQuery(
        "SELECT id, voucher_number, voucher_type, total_amount, date, currency, description "
        "FROM vouchers "
        "WHERE date >= ? AND date < ? "
        "ORDER BY date DESC",
        [dayStart.toIso8601String().substring(0, 10), dayEnd.toIso8601String().substring(0, 10)],
      );
      for (final row in vouchers) {
        final voucherType = row['voucher_type'] as String? ?? '';
        final isReceipt = voucherType.contains('receipt') || voucherType.contains('قبض');
        operations.add({
          'type': isReceipt ? 'receipt_voucher' : 'payment_voucher',
          'type_label': isReceipt ? 'سند قبض' : 'سند صرف',
          'id': row['id'],
          'entity_name': row['description'] ?? row['voucher_number'] ?? '',
          'amount': MoneyHelper.readCalculatedMoney(row['total_amount']),
          'currency': row['currency'] ?? 'YER',
          'time': row['date'] ?? '',
        });
      }
    } catch (e) {
      DatabaseHelper.logMigrationError("alter", e);
      // جدول السندات غير موجود بعد
    }

    // المصروفات
    final expenses = await db.rawQuery(
      "SELECT id, title, amount, expense_date, currency, category "
      "FROM expenses "
      "WHERE expense_date >= ? AND expense_date < ? "
      "ORDER BY expense_date DESC",
      [startStr, endStr],
    );
    for (final row in expenses) {
      operations.add({
        'type': 'expense',
        'type_label': 'مصروف',
        'id': row['id'],
        'entity_name': row['title'] ?? (row['category'] ?? ''),
        'amount': MoneyHelper.readCalculatedMoney(row['amount']),
        'currency': row['currency'] ?? 'YER',
        'time': row['expense_date'] ?? '',
      });
    }

    // التحويلات النقدية
    final transfers = await db.rawQuery(
      "SELECT ct.id, ct.transfer_number, ct.amount, ct.currency, ct.created_at, "
      "cb_from.name AS from_name, cb_to.name AS to_name "
      "FROM cash_transfers ct "
      "LEFT JOIN cash_boxes cb_from ON ct.from_cash_box_id = cb_from.id "
      "LEFT JOIN cash_boxes cb_to ON ct.to_cash_box_id = cb_to.id "
      "WHERE ct.created_at >= ? AND ct.created_at < ? "
      "ORDER BY ct.created_at DESC",
      [startStr, endStr],
    );
    for (final row in transfers) {
      operations.add({
        'type': 'cash_transfer',
        'type_label': 'تحويل نقدي',
        'id': row['id'],
        'entity_name': '${row['from_name'] ?? ''} ← ${row['to_name'] ?? ''}',
        'amount': MoneyHelper.readCalculatedMoney(row['amount']),
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // صرافة العملات
    try {
      final exchanges = await db.rawQuery(
        "SELECT ce.id, ce.exchange_number, ce.from_amount, ce.to_amount, ce.from_currency, "
        "ce.to_currency, ce.exchange_rate, ce.created_at, "
        "cb_from.name AS from_box_name, cb_to.name AS to_box_name "
        "FROM currency_exchanges ce "
        "LEFT JOIN cash_boxes cb_from ON ce.from_cash_box_id = cb_from.id "
        "LEFT JOIN cash_boxes cb_to ON ce.to_cash_box_id = cb_to.id "
        "WHERE ce.created_at >= ? AND ce.created_at < ? "
        "ORDER BY ce.created_at DESC",
        [startStr, endStr],
      );
      for (final row in exchanges) {
        operations.add({
          'type': 'currency_exchange',
          'type_label': 'صرافة عملات',
          'id': row['id'],
          'entity_name': '${row['from_currency'] ?? ''} → ${row['to_currency'] ?? ''}',
          'amount': MoneyHelper.readCalculatedMoney(row['from_amount']),
          'currency': row['from_currency'] ?? 'YER',
          'time': row['created_at'] ?? '',
        });
      }
    } catch (e) {
      DatabaseHelper.logMigrationError("alter", e);
      // جدول صرافة العملات غير موجود بعد
    }

    // ترتيب حسب الوقت تنازلياً
    operations.sort((a, b) {
      final timeA = (a['time'] as String?) ?? '';
      final timeB = (b['time'] as String?) ?? '';
      return timeB.compareTo(timeA);
    });

    return operations;
  }

  /// جلب ملخص العمليات اليومية لتاريخ محدد
  /// Returns daily summary totals by category.
  Future<Map<String, double>> getDailySummary(DateTime date) async {
    final db = await _db;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final startStr = dayStart.toIso8601String();
    final endStr = dayEnd.toIso8601String();

    final Map<String, double> summary = {
      'total_sales': 0.0,
      'total_purchases': 0.0,
      'total_receipts': 0.0,
      'total_payments': 0.0,
      'total_expenses': 0.0,
      'total_transfers': 0.0,
    };

    // إجمالي المبيعات
    final salesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices "
      "WHERE type IN ('sale', 'pos') AND is_return = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_sales'] = MoneyHelper.readCalculatedMoney(salesResult.first['total']);

    // إجمالي المشتريات
    final purchasesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices "
      "WHERE type = 'purchase' AND is_return = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_purchases'] = MoneyHelper.readCalculatedMoney(purchasesResult.first['total']);

    // سندات القبض
    try {
      final receiptsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE (voucher_type LIKE '%receipt%' OR voucher_type LIKE '%قبض%') "
        "AND date >= ? AND date < ?",
        [startStr, endStr],
      );
      summary['total_receipts'] = MoneyHelper.readCalculatedMoney(receiptsResult.first['total']);
    } catch (e) { DatabaseHelper.logMigrationError("migration", e); }

    // سندات الصرف
    try {
      final paymentsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE (voucher_type LIKE '%payment%' OR voucher_type LIKE '%صرف%') "
        "AND date >= ? AND date < ?",
        [startStr, endStr],
      );
      summary['total_payments'] = MoneyHelper.readCalculatedMoney(paymentsResult.first['total']);
    } catch (e) { DatabaseHelper.logMigrationError("migration", e); }

    // المصروفات
    final expensesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses "
      "WHERE expense_date >= ? AND expense_date < ?",
      [startStr, endStr],
    );
    summary['total_expenses'] = MoneyHelper.readCalculatedMoney(expensesResult.first['total']);

    // التحويلات
    final transfersResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM cash_transfers "
      "WHERE created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_transfers'] = MoneyHelper.readCalculatedMoney(transfersResult.first['total']);

    return summary;
  }

  /// جلب تقرير أرباح الفواتير
  /// Returns profit per invoice (sale price - cost price).
  Future<List<Map<String, dynamic>>> getInvoiceProfitReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db;
    String dateFilter = '';
    List<dynamic> args = [];
    if (startDate != null) {
      dateFilter += ' AND i.created_at >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final toDate = endDate.add(const Duration(days: 1));
      dateFilter += ' AND i.created_at < ?';
      args.add(toDate.toIso8601String());
    }

    // Use ii.unit_cost (stored at time of sale) for accurate COGS,
    // falling back to p.cost_price only if unit_cost is 0 (legacy items)
    // FIX: CAST to INTEGER so MoneyHelper.readMoney() correctly divides by 100.
    // Without CAST, SQLite returns REAL (because base_quantity is REAL),
    // causing readMoney to treat it as a legacy double and skip the ÷100 conversion.
    return await db.rawQuery(
      "SELECT i.id AS invoice_id, i.type, i.total AS sale_total, i.currency, i.created_at, "
      "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') "
      "WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') "
      "ELSE 'بدون عميل' END AS entity_name, "
      "CAST(COALESCE(SUM("
      "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
      "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
      "), 0) AS INTEGER) AS cost_total, "
      "CAST(i.total - COALESCE(SUM("
      "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
      "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
      "), 0) AS INTEGER) AS profit "
      "FROM invoices i "
      "LEFT JOIN customers c ON i.customer_id = c.id "
      "LEFT JOIN suppliers s ON i.supplier_id = s.id "
      "LEFT JOIN invoice_items ii ON ii.invoice_id = i.id "
      "LEFT JOIN products p ON ii.product_id = p.id "
      "WHERE i.is_return = 0 AND i.type IN ('sale', 'pos') "
      "$dateFilter "
      "GROUP BY i.id "
      "ORDER BY i.created_at DESC",
      args,
    );
  }

  /// جلب تقرير حركة المخزون
  /// Returns stock in/out movements per product.
  Future<List<Map<String, dynamic>>> getInventoryMovementReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db;
    String dateFilter = '';
    List<dynamic> args = [];
    if (startDate != null) {
      dateFilter += ' AND i.created_at >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final toDate = endDate.add(const Duration(days: 1));
      dateFilter += ' AND i.created_at < ?';
      args.add(toDate.toIso8601String());
    }

    return await db.rawQuery(
      "SELECT p.id AS product_id, p.name_ar, p.item_code, p.current_stock, "
      "COALESCE(sales_data.qty_out, 0) AS qty_out, "
      "CAST(COALESCE(sales_data.revenue, 0) AS INTEGER) AS total_revenue, "
      "COALESCE(purchase_data.qty_in, 0) AS qty_in, "
      "CAST(COALESCE(purchase_data.cost, 0) AS INTEGER) AS total_cost "
      "FROM products p "
      "LEFT JOIN ("
      "  SELECT ii.product_id, SUM(ii.quantity) AS qty_out, SUM(ii.total_price) AS revenue "
      "  FROM invoice_items ii "
      "  INNER JOIN invoices i ON ii.invoice_id = i.id "
      "  WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 $dateFilter "
      "  GROUP BY ii.product_id"
      ") sales_data ON p.id = sales_data.product_id "
      "LEFT JOIN ("
      "  SELECT ii.product_id, SUM(ii.quantity) AS qty_in, SUM(ii.total_price) AS cost "
      "  FROM invoice_items ii "
      "  INNER JOIN invoices i ON ii.invoice_id = i.id "
      "  WHERE i.type = 'purchase' AND i.is_return = 0 $dateFilter "
      "  GROUP BY ii.product_id"
      ") purchase_data ON p.id = purchase_data.product_id "
      "WHERE p.is_active = 1 AND (sales_data.qty_out IS NOT NULL OR purchase_data.qty_in IS NOT NULL) "
      "ORDER BY p.name_ar",
      [...args, ...args],
    );
  }

  /// جلب تقرير تكلفة المخزون
  /// Returns cost value of current stock per product.
  Future<List<Map<String, dynamic>>> getInventoryCostReport() async {
    final db = await _db;
    return await db.rawQuery(
      // FIX: Use COALESCE(average_cost, cost_price) instead of cost_price alone.
      // average_cost reflects the weighted average after multiple purchases at different prices,
      // while cost_price may be outdated. This ensures accurate inventory valuation.
      "SELECT p.id, p.name_ar, p.item_code, p.barcode, "
      "p.current_stock, COALESCE(NULLIF(p.average_cost, 0), p.cost_price) AS cost_price, p.sell_price, "
      "CAST(ROUND(p.current_stock * COALESCE(NULLIF(p.average_cost, 0), p.cost_price)) AS INTEGER) AS stock_cost_value, "
      "CAST(ROUND(p.current_stock * p.sell_price) AS INTEGER) AS stock_sell_value, "
      "c.name AS category_name, w.name AS warehouse_name "
      "FROM products p "
      "LEFT JOIN categories c ON p.category_id = c.id "
      "LEFT JOIN warehouses w ON p.warehouse_id = w.id "
      "WHERE p.is_active = 1 AND p.current_stock > 0 "
      "ORDER BY stock_cost_value DESC",
    );
  }

  /// جلب جميع الحركات المحاسبية للتصدير مع اسم الحساب
  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT t.*, a.name_ar AS account_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      ORDER BY t.date DESC
    ''');
  }

  // ══════════════════════════════════════════════════════════════
  //  Advanced Statistics / Charts query methods
  // ══════════════════════════════════════════════════════════════

  /// Monthly sales vs purchases for a given [year].
  /// Returns 12 rows (one per month) with `month`, `sales`, `purchases` columns.
  Future<List<Map<String, dynamic>>> getMonthlySalesVsPurchases(int year, {String? currency}) async {
    final db = await _db;
    final yearStr = year.toString();
    List<dynamic> args = [yearStr];
    String currencyFilter = '';
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND i.currency = ?';
      args.add(currency);
    }
    // Need separate sub-queries with separate arg lists
    final salesArgs = [yearStr, if (currency != null && currency.isNotEmpty) currency];
    final purchasesArgs = [yearStr, if (currency != null && currency.isNotEmpty) currency];
    final salesCurrencyFilter = currency != null && currency.isNotEmpty ? ' AND currency = ?' : '';
    final purchasesCurrencyFilter = currency != null && currency.isNotEmpty ? ' AND currency = ?' : '';

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
        WHERE type = 'sale' AND is_return = 0
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
  Future<List<Map<String, dynamic>>> getRevenueExpenseBreakdown(int year, {String? currency}) async {
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
          WHEN type = 'sale' AND is_return = 0 THEN 'مبيعات'
          WHEN type = 'purchase' AND is_return = 1 THEN 'مرتجع مشتريات'
          ELSE 'أخرى'
        END AS category,
        SUM(total) AS total,
        'إيرادات' AS type
      FROM invoices
      WHERE (type = 'sale' AND is_return = 0 OR type = 'purchase' AND is_return = 1)
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
  Future<List<Map<String, dynamic>>> getDailySalesTrend(int days, {String? currency}) async {
    final db = await _db;
    String currencyFilter = '';
    List<dynamic> args = [];
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND currency = ?';
      args.add(currency);
    }
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type = 'sale' AND is_return = 0
        AND date(created_at) >= ?
        $currencyFilter
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr, ...args]);
  }

  /// Top products by sales amount.
  /// Returns rows with `product_name`, `total_quantity`, `total_amount` columns.
  Future<List<Map<String, dynamic>>> getTopProducts(int limit, {String? currency}) async {
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
      WHERE i.type = 'sale' AND i.is_return = 0
        $currencyFilter
      GROUP BY ii.product_name
      ORDER BY total_amount DESC
      LIMIT ?
    ''', [...args, limit]);
  }

  /// Top customer balances.
  /// Returns rows with `name`, `balance`, `balance_type`, `currency` columns.
  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) => _dbHelper.customers.getTopCustomerBalances(limit);

  /// Monthly cash flow (inflow vs outflow) for a given [year].
  /// Returns 12 rows with `month`, `inflow`, `outflow` columns.
  /// Fix #6: Include purchase payments and voucher payments in outflow.
  Future<List<Map<String, dynamic>>> getMonthlyCashFlow(int year, {String? currency}) async {
    final db = await _db;
    final yearStr = year.toString();
    String currencyFilter = '';
    List<dynamic> inflowArgs = [yearStr];
    List<dynamic> outflowArgs = [yearStr];
    List<dynamic> purchaseOutflowArgs = [yearStr];
    List<dynamic> voucherOutflowArgs = [yearStr];
    if (currency != null && currency.isNotEmpty) {
      currencyFilter = ' AND currency = ?';
      inflowArgs.add(currency);
      outflowArgs.add(currency);
      purchaseOutflowArgs.add(currency);
      voucherOutflowArgs.add(currency);
    }
    return await db.rawQuery('''
      SELECT m.month,
        COALESCE(i.inflow, 0.0) AS inflow,
        COALESCE(o.outflow, 0.0) + COALESCE(p.purchase_outflow, 0.0) + COALESCE(v.voucher_outflow, 0.0) AS outflow
      FROM (
        SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION
        SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION
        SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
      ) m
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(paid_amount) AS inflow
        FROM invoices
        WHERE type = 'sale' AND is_return = 0 AND paid_amount > 0
          AND strftime('%Y', created_at) = ?
          $currencyFilter
        GROUP BY month
      ) i ON m.month = i.month
      LEFT JOIN (
        SELECT CAST(strftime('%m', expense_date) AS INTEGER) AS month,
               SUM(total) AS outflow
        FROM expenses
        WHERE strftime('%Y', expense_date) = ?
          $currencyFilter
        GROUP BY month
      ) o ON m.month = o.month
      LEFT JOIN (
        -- Fix #6: Include cash purchase payments in outflow
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(paid_amount) AS purchase_outflow
        FROM invoices
        WHERE type = 'purchase' AND is_return = 0 AND payment_mechanism = 'cash' AND paid_amount > 0
          AND strftime('%Y', created_at) = ?
          $currencyFilter
        GROUP BY month
      ) p ON m.month = p.month
      LEFT JOIN (
        -- Fix #6: Include payment voucher outflows (سندات صرف)
        SELECT CAST(strftime('%m', v.date) AS INTEGER) AS month,
               SUM(v.total_amount) AS voucher_outflow
        FROM vouchers v
        WHERE v.voucher_type = 'payment'
          AND strftime('%Y', v.date) = ?
          $currencyFilter
        GROUP BY month
      ) v ON m.month = v.month
      ORDER BY m.month
    ''', [...inflowArgs, ...outflowArgs, ...purchaseOutflowArgs, ...voucherOutflowArgs]);
  }

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
      dateFrom: dateFrom, dateTo: dateTo, column: 'expense_date',
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
          cogsRetArgs.add(dateTo.add(const Duration(days: 1)).toIso8601String());
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

    return [
      {'item': 'revenue', 'amount': revRes.first['revenue']},
      {'item': 'purchases', 'amount': purRes.first['purchases']},
      {'item': 'sales_returns', 'amount': retSaleRes.first['sales_returns']},
      {'item': 'purchase_returns', 'amount': retPurRes.first['purchase_returns']},
      {'item': 'expenses', 'amount': expRes.first['expenses']},
      {'item': 'cogs', 'amount': cogs},
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
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'i.created_at');
    args.addAll(dateArgs);
    final (cf, curArgs) = buildCurrencyFilter(currency: currency, column: 'i.currency');
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
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'i.created_at');
    args.addAll(dateArgs);
    final (cf, curArgs) = buildCurrencyFilter(currency: currency, column: 'i.currency');
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
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'date');
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
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    return rows.isNotEmpty ? (rows.first['balance_type'] as String? ?? 'credit') : 'credit';
  }

  // ── 5. Supplier Movement (Supplier Statement) ─────────────────

  /// كشف حساب مورد — finds the supplier's payable account and returns
  /// its transactions. Returns empty list if no linked account is found.
  /// The `supplierName` and `supplierCurrency` must be provided by the
  /// caller (typically from `getAllSuppliers()`).
  Future<List<Map<String, dynamic>>> getSupplierMovementReport({
    required int supplierId,
    required String supplierName,
    required String supplierCurrency,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;

    // Try exact name match first, then LIKE fallback
    var acctRes = await db.rawQuery(
      "SELECT id FROM accounts WHERE name_ar=? AND currency=? LIMIT 1",
      [supplierName, supplierCurrency],
    );
    if (acctRes.isEmpty && supplierName.isNotEmpty) {
      acctRes = await db.rawQuery(
        "SELECT id FROM accounts WHERE (name_ar LIKE ? OR name_ar LIKE ?) AND currency=? LIMIT 1",
        ['%$supplierName%', '%$supplierName%', supplierCurrency],
      );
    }
    if (acctRes.isEmpty) return [];

    final accountId = acctRes.first['id'] as int;
    final args = <dynamic>[accountId];
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 't.created_at');
    args.addAll(dateArgs);

    return await db.rawQuery(
      "SELECT t.date, t.description, t.debit, t.credit, t.created_at "
      "FROM transactions t WHERE t.account_id=?$df ORDER BY t.date ASC, t.created_at ASC",
      args,
    );
  }

  // ── 6. Customer Balances ──────────────────────────────────────

  /// ديون العملاء — returns all customers with positive balances.
  /// Values are raw DB integers (cents).
  Future<List<Map<String, dynamic>>> getCustomerBalancesReport() async {
    final customers = await _dbHelper.getAllCustomers();
    return customers
        .where((c) => (c['balance'] as num?)?.toInt() != 0)
        .map((c) => {
              'name': c['name'],
              'balance': c['balance'],
              'balance_type': c['balance_type'],
              'currency': c['currency'],
              'phone': c['phone'],
              'debt_ceiling': c['debt_ceiling'],
            })
        .toList();
  }

  // ── 7. Supplier Balances ──────────────────────────────────────

  /// ديون الموردين — returns all suppliers with positive balances.
  /// Values are raw DB integers (cents).
  Future<List<Map<String, dynamic>>> getSupplierBalancesReport() async {
    final suppliers = await _dbHelper.getAllSuppliers();
    return suppliers
        .where((s) => (s['balance'] as num?)?.toInt() != 0)
        .map((s) => {
              'name': s['name'],
              'balance': s['balance'],
              'balance_type': s['balance_type'],
              'currency': s['currency'],
              'phone': s['phone'],
              'debt_ceiling': s['debt_ceiling'],
            })
        .toList();
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
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'expense_date');
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
  /// totals. The caller iterates cash boxes, filters by currency/cashBoxId,
  /// and adds per‑box invoice aggregates.
  Future<List<Map<String, dynamic>>> getCashBoxesReport({
    String? currency,
    int? cashBoxId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final cashBoxes = await _dbHelper.getAllCashBoxes();
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo);

    final results = <Map<String, dynamic>>[];
    for (final cb in cashBoxes) {
      if (currency != null && currency.isNotEmpty && cb['currency'] != currency) continue;
      if (cashBoxId != null && cb['id'] != cashBoxId) continue;

      final cbId = cb['id'] as int;

      // Invoice aggregates for this cash box
      final invRes = await db.rawQuery(
        "SELECT type, CAST(COALESCE(SUM(total), 0) AS INTEGER) as total "
        "FROM invoices WHERE cash_box_id=? AND is_return=0$df GROUP BY type",
        [cbId, ...dateArgs],
      );

      int salesTotal = 0;
      int purchaseTotal = 0;
      for (final inv in invRes) {
        final t = inv['type'] as String? ?? '';
        final tot = inv['total'] as int? ?? 0;
        if (t == 'sale' || t == 'pos') {
          salesTotal = tot;
        } else if (t == 'purchase') {
          purchaseTotal = tot;
        }
      }

      results.add({
        'id': cbId,
        'name': cb['name'],
        'type': cb['type'],
        'currency': cb['currency'],
        'balance': cb['balance'],
        'balance_type': cb['balance_type'],
        'sales_total': salesTotal,
        'purchase_total': purchaseTotal,
      });
    }
    return results;
  }

  // ── 10. Currency Exchanges ────────────────────────────────────

  /// صرافة العملات — returns currency exchange rows with box names.
  Future<List<Map<String, dynamic>>> getCurrencyExchangesReport({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await _db;
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'ce.created_at');

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
    final (df, dateArgs) = buildDateFilter(dateFrom: dateFrom, dateTo: dateTo, column: 'v.created_at');

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
    return await _dbHelper.getAllShifts(orderBy: 'opened_at DESC');
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
  Future<List<Map<String, dynamic>>> getTopCustomersBySales(String monthStart, {int limit = 5}) async {
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
  Future<List<Map<String, dynamic>>> getInvoiceCurrencyBreakdown(String monthStart) async {
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
  Future<List<Map<String, dynamic>>> getTopSellersToday(String todayStr, {int limit = 5}) async {
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
}
