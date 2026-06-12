import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

class OrderRepository {
  final DatabaseHelper _dbHelper;
  OrderRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  static const Map<String, String> _orderByWhitelist = {
    'created_at DESC': 'created_at DESC',
    'created_at ASC': 'created_at ASC',
    'updated_at DESC': 'updated_at DESC',
    'updated_at ASC': 'updated_at ASC',
    'status ASC': 'status ASC',
    'total DESC': 'total DESC',
    'total ASC': 'total ASC',
  };

  String _safeAliasedOrderBy(String alias, String orderBy) {
    final safe = _orderByWhitelist[orderBy] ?? _orderByWhitelist['created_at DESC']!;
    final parts = safe.split(' ');
    return '$alias.${parts.first} ${parts.last}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Quotation CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertQuotationWithItems(Map<String, dynamic> quotationMap,
      List<Map<String, dynamic>> items) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('quotations',
          MoneyHelper.toCentsMap(quotationMap, MoneyHelper.orderMoneyFields));
      for (final item in items) {
        await txn.insert('quotation_items',
            MoneyHelper.toCentsMap(item, MoneyHelper.orderItemMoneyFields));
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllQuotations(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT q.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM quotations q
      LEFT JOIN customers c ON q.customer_id = c.id
      ORDER BY ${_safeAliasedOrderBy('q', orderBy)}
    ''');
  }

  Future<List<Map<String, dynamic>>> getQuotationsByStatus(
      String status) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT q.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM quotations q
      LEFT JOIN customers c ON q.customer_id = c.id
      WHERE q.status = ?
      ORDER BY q.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getQuotationById(String id) async {
    final db = await _db;
    final results = await db.query('quotations',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getQuotationItems(
      String quotationId) async {
    final db = await _db;
    return await db.query('quotation_items',
        where: 'quotation_id = ?', whereArgs: [quotationId]);
  }

  Future<int> updateQuotation(
      String id, Map<String, dynamic> quotationMap) async {
    final db = await _db;
    return await db.update('quotations',
        MoneyHelper.toCentsMap(quotationMap, MoneyHelper.orderMoneyFields),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteQuotation(String id) async {
    final db = await _db;
    await db
        .delete('quotation_items', where: 'quotation_id = ?', whereArgs: [id]);
    return await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextQuotationNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'QT-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(quotation_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM quotations WHERE quotation_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Purchase Order CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertPurchaseOrderWithItems(
      Map<String, dynamic> poMap, List<Map<String, dynamic>> items) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('purchase_orders',
          MoneyHelper.toCentsMap(poMap, MoneyHelper.orderMoneyFields));
      for (final item in items) {
        await txn.insert('purchase_order_items',
            MoneyHelper.toCentsMap(item, MoneyHelper.orderItemMoneyFields));
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllPurchaseOrders(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT po.*, COALESCE(s.name, 'بدون مورد') AS supplier_name
      FROM purchase_orders po
      LEFT JOIN suppliers s ON po.supplier_id = s.id
      ORDER BY ${_safeAliasedOrderBy('po', orderBy)}
    ''');
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrdersByStatus(
      String status) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT po.*, COALESCE(s.name, 'بدون مورد') AS supplier_name
      FROM purchase_orders po
      LEFT JOIN suppliers s ON po.supplier_id = s.id
      WHERE po.status = ?
      ORDER BY po.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getPurchaseOrderById(String id) async {
    final db = await _db;
    final results = await db.query('purchase_orders',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrderItems(String poId) async {
    final db = await _db;
    return await db.query('purchase_order_items',
        where: 'purchase_order_id = ?', whereArgs: [poId]);
  }

  Future<int> updatePurchaseOrder(String id, Map<String, dynamic> poMap) async {
    final db = await _db;
    return await db.update('purchase_orders',
        MoneyHelper.toCentsMap(poMap, MoneyHelper.orderMoneyFields),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePurchaseOrder(String id) async {
    final db = await _db;
    await db.delete('purchase_order_items',
        where: 'purchase_order_id = ?', whereArgs: [id]);
    return await db.delete('purchase_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextPurchaseOrderNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM purchase_orders WHERE order_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Sales Order CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertSalesOrderWithItems(
      Map<String, dynamic> soMap, List<Map<String, dynamic>> items) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('sales_orders',
          MoneyHelper.toCentsMap(soMap, MoneyHelper.orderMoneyFields));
      for (final item in items) {
        await txn.insert('sales_order_items',
            MoneyHelper.toCentsMap(item, MoneyHelper.orderItemMoneyFields));
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllSalesOrders(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT so.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM sales_orders so
      LEFT JOIN customers c ON so.customer_id = c.id
      ORDER BY ${_safeAliasedOrderBy('so', orderBy)}
    ''');
  }

  Future<List<Map<String, dynamic>>> getSalesOrdersByStatus(
      String status) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT so.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM sales_orders so
      LEFT JOIN customers c ON so.customer_id = c.id
      WHERE so.status = ?
      ORDER BY so.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getSalesOrderById(String id) async {
    final db = await _db;
    final results = await db.query('sales_orders',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getSalesOrderItems(String soId) async {
    final db = await _db;
    return await db.query('sales_order_items',
        where: 'sales_order_id = ?', whereArgs: [soId]);
  }

  Future<int> updateSalesOrder(String id, Map<String, dynamic> soMap) async {
    final db = await _db;
    return await db.update('sales_orders',
        MoneyHelper.toCentsMap(soMap, MoneyHelper.orderMoneyFields),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSalesOrder(String id) async {
    final db = await _db;
    await db.delete('sales_order_items',
        where: 'sales_order_id = ?', whereArgs: [id]);
    return await db.delete('sales_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextSalesOrderNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'SO-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM sales_orders WHERE order_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }
}
