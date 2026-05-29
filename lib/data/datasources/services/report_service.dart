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
        'amount': MoneyHelper.readMoney(row['total']),
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
        'amount': MoneyHelper.readMoney(row['total']),
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
          'amount': MoneyHelper.readMoney(row['total_amount']),
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
        'amount': MoneyHelper.readMoney(row['amount']),
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
        'amount': MoneyHelper.readMoney(row['amount']),
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
          'amount': MoneyHelper.readMoney(row['from_amount']),
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
    summary['total_sales'] = MoneyHelper.readMoney(salesResult.first['total']);

    // إجمالي المشتريات
    final purchasesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices "
      "WHERE type = 'purchase' AND is_return = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_purchases'] = MoneyHelper.readMoney(purchasesResult.first['total']);

    // سندات القبض
    try {
      final receiptsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE (voucher_type LIKE '%receipt%' OR voucher_type LIKE '%قبض%') "
        "AND date >= ? AND date < ?",
        [startStr, endStr],
      );
      summary['total_receipts'] = MoneyHelper.readMoney(receiptsResult.first['total']);
    } catch (e) { DatabaseHelper.logMigrationError("migration", e); }

    // سندات الصرف
    try {
      final paymentsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE (voucher_type LIKE '%payment%' OR voucher_type LIKE '%صرف%') "
        "AND date >= ? AND date < ?",
        [startStr, endStr],
      );
      summary['total_payments'] = MoneyHelper.readMoney(paymentsResult.first['total']);
    } catch (e) { DatabaseHelper.logMigrationError("migration", e); }

    // المصروفات
    final expensesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses "
      "WHERE expense_date >= ? AND expense_date < ?",
      [startStr, endStr],
    );
    summary['total_expenses'] = MoneyHelper.readMoney(expensesResult.first['total']);

    // التحويلات
    final transfersResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM cash_transfers "
      "WHERE created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_transfers'] = MoneyHelper.readMoney(transfersResult.first['total']);

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
      "COALESCE(sales_data.qty_out, 0.0) AS qty_out, "
      "COALESCE(sales_data.revenue, 0.0) AS total_revenue, "
      "COALESCE(purchase_data.qty_in, 0.0) AS qty_in, "
      "COALESCE(purchase_data.cost, 0.0) AS total_cost "
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
}
