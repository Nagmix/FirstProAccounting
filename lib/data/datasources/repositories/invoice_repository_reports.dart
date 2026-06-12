part of 'invoice_repository.dart';

extension InvoiceRepositoryReports on InvoiceRepository {
  // ══════════════════════════════════════════════════════════════
  //  Invoice query & reporting methods
  // ══════════════════════════════════════════════════════════════

  Future<double> getTotalSalesForDate(DateTime date) async {
    final db = await _db;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) = ?",
        [dateStr]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Get total purchases for a specific date range and currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getTotalPurchasesForDateRange(
      String currency, String startStr, String endStr) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices "
      "WHERE type = 'purchase' AND is_return = 0 AND currency = ? "
      "AND created_at >= ? AND created_at < ?",
      [currency, startStr, endStr],
    );
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Calculate Cost of Goods Sold (COGS) for a specific date range and currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getCOGSForDateRange(
      String currency, String startStr, String endStr) async {
    final db = await _db;
    try {
      final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
        "), 0) AS INTEGER) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = 0 "
        "AND i.currency = ? AND i.created_at >= ? AND i.created_at < ?",
        [currency, startStr, endStr],
      );
      return MoneyHelper.readCalculatedMoney(result.first['total_cogs']);
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> getTotalPurchasesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('purchase', 'purchase_return') AND is_return = 0 AND date(created_at) >= ?",
        [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalSalesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?",
        [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Calculate Cost of Goods Sold (COGS) for the current month.
  /// COGS = SUM(base_quantity * unit_cost) for sale/pos invoice items this month.
  /// FIX: CAST to INTEGER so readMoney divides by 100 correctly.
  Future<double> getCOGSThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    try {
      final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
        "), 0) AS INTEGER) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = 0 "
        "AND date(i.created_at) >= ?",
        [monthStart],
      );
      return MoneyHelper.readCalculatedMoney(result.first['total_cogs']);
    } catch (e) {
      return 0.0;
    }
  }

  Future<int> getInvoiceCountForDate(DateTime date) async {
    final db = await _db;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM invoices WHERE date(created_at) = ?",
        [dateStr]);
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> getCashBalance() async {
    return _dbHelper.cashBoxes.getTotalCashBalance();
  }

  Future<List<Map<String, dynamic>>> getRecentInvoices({int limit = 10}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT i.id, i.type, i.total, i.paid_amount, i.remaining, i.is_return,
             i.status, i.created_at, i.payment_mechanism,
             COALESCE(c.name, s.name, 'بدون عميل') AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getDailySalesTotals({int days = 7}) async {
    final db = await _db;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr]);
  }

  Future<int> getNextInvoiceSequence(
      String datePrefix, String invoiceType) async {
    final db = await _db;
    // البحث عن أكبر رقم تسلسلي موجود لهذا اليوم وهذا النوع
    final result = await db.rawQuery(
      "SELECT id FROM invoices WHERE id LIKE ? AND type = ? ORDER BY id DESC LIMIT 1",
      ['$datePrefix%', invoiceType],
    );
    if (result.isEmpty) return 1;

    final lastId = result.first['id'] as String;
    // استخراج الرقم التسلسلي من المعرف: POS-YYYYMMDD-NNNN → NNNN
    final parts = lastId.split('-');
    if (parts.length >= 3) {
      final lastSeq = int.tryParse(parts.last) ?? 0;
      return lastSeq + 1;
    }
    return 1;
  }

  Future<int> getTodayPosInvoiceCount(String datePrefix) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE id LIKE ?",
      ['POS-$datePrefix%'],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Check return quantity limits against the original invoice.
  /// Returns a map of product_id -> error message for items that exceed original quantities.
  Future<Map<String, String>> checkReturnLimits(
      String originalInvoiceId, List<Map<String, dynamic>> returnItems) async {
    final db = await _db;
    final errors = <String, String>{};

    // Get original invoice items
    final originalItems = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [originalInvoiceId],
    );

    // Get already returned quantities
    final returnInvoices = await db.query(
      'invoices',
      where: 'original_invoice_id = ? AND is_return = 1 AND status != ?',
      whereArgs: [originalInvoiceId, 'cancelled'],
    );

    final returnedQuantities = <int, double>{};
    for (final returnInvoice in returnInvoices) {
      final returnItems2 = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [returnInvoice['id']],
      );
      for (final item in returnItems2) {
        final productId = (item['product_id'] as num?)?.toInt() ?? 0;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        returnedQuantities[productId] =
            (returnedQuantities[productId] ?? 0.0) + qty;
      }
    }

    // Check each return item against original - returned
    for (final item in returnItems) {
      final productId = (item['product_id'] as num?)?.toInt() ?? 0;
      final returnQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;

      // Find original quantity for this product
      double originalQty = 0.0;
      for (final origItem in originalItems) {
        final origProductId = (origItem['product_id'] as num?)?.toInt() ?? 0;
        if (origProductId == productId) {
          originalQty = (origItem['quantity'] as num?)?.toDouble() ?? 0.0;
          break;
        }
      }

      final alreadyReturned = returnedQuantities[productId] ?? 0.0;
      if (returnQty > originalQty - alreadyReturned) {
        errors[productId.toString()] =
            'الكمية المرتجعة ($returnQty) تتجاوز الكمية المتبقية (${originalQty - alreadyReturned})';
      }
    }

    return errors;
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Invoice>> getAllInvoiceObjects(
      {String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final maps =
        await getAllInvoices(orderBy: orderBy, limit: limit, offset: offset);
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getInvoiceObjectsByType(String type) async {
    final maps = await getInvoicesByType(type);
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Invoice?> getInvoiceObjectById(String invoiceId) async {
    final map = await getInvoiceById(invoiceId);
    return map != null ? Invoice.fromMap(map) : null;
  }}
