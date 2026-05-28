import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/utils/money_helper.dart';
import '../../models/product_model.dart';
import '../database_helper.dart';

class ProductRepository {
  final DatabaseHelper _dbHelper;
  ProductRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Product CRUD
  // ══════════════════════════════════════════════════════════════

  Future<int> insertProduct(Map<String, dynamic> productMap) async {
    final db = await _db;
    return await db.insert('products', MoneyHelper.toCentsMap(productMap, MoneyHelper.productMoneyFields));
  }

  Future<List<Map<String, dynamic>>> getAllProducts({bool? activeOnly, String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final db = await _db;
    if (activeOnly == true) {
      return await db.query('products', where: 'is_active = ?', whereArgs: [1], orderBy: orderBy, limit: limit, offset: offset > 0 ? offset : null);
    }
    return await db.query('products', orderBy: orderBy, limit: limit, offset: offset > 0 ? offset : null);
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query, {int? warehouseId}) async {
    final db = await _db;
    final likeQuery = '%$query%';
    if (warehouseId != null) {
      return await db.query(
        'products',
        where: '(name_ar LIKE ? OR name_en LIKE ? OR barcode LIKE ? OR item_code LIKE ?) AND (warehouse_id = ? OR warehouse_id IS NULL) AND is_active = 1',
        whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery, warehouseId],
        orderBy: 'created_at DESC',
      );
    }
    return await db.query(
      'products',
      where: 'name_ar LIKE ? OR name_en LIKE ? OR barcode LIKE ? OR item_code LIKE ?',
      whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getProductById(int id) async {
    final db = await _db;
    final results = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateProduct(int id, Map<String, dynamic> productMap) async {
    final db = await _db;
    return await db.update('products', MoneyHelper.toCentsMap(productMap, MoneyHelper.productMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await _db;
    // Check if product is referenced in invoice_items
    final refs = await db.query('invoice_items', where: 'product_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete: product has history, cannot hard-delete
      return await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    }
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// P-05: [DEPRECATED] Use inline SQL in invoice_repository.dart instead.
  /// This method is kept for reference but should not be called directly.
  /// Stock updates are handled within invoice transactions for atomicity.
  @Deprecated('Use inline SQL in invoice_repository for atomic stock updates within transactions')
  Future<void> decrementProductStock(int productId, double quantity) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    // Check if product allows negative stock
    final productRow = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    final allowNegative = productRow.isNotEmpty ? (productRow.first['allow_negative'] as int?) == 1 : false;
    if (allowNegative) {
      await db.rawUpdate(
        'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
        [quantity, now, productId],
      );
    } else {
      await db.rawUpdate(
        'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
        [quantity, now, productId],
      );
    }
  }

  /// P-05: [DEPRECATED] Use inline SQL in invoice_repository.dart instead.
  /// This method is kept for reference but should not be called directly.
  /// Stock updates are handled within invoice transactions for atomicity.
  @Deprecated('Use inline SQL in invoice_repository for atomic stock updates within transactions')
  Future<void> incrementProductStock(int productId, double quantity) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
      [quantity, now, productId],
    );
  }

  /// P-07: Check if a barcode already exists in the products table.
  /// Optionally exclude a product ID (for edit mode).
  Future<bool> checkBarcodeExists(String barcode, {int? excludeId}) async {
    final db = await _db;
    if (barcode.trim().isEmpty) return false;
    List<Map<String, dynamic>> result;
    if (excludeId != null) {
      result = await db.query(
        'products',
        where: 'barcode = ? AND id != ? AND is_active = 1',
        whereArgs: [barcode.trim(), excludeId],
        limit: 1,
      );
    } else {
      result = await db.query(
        'products',
        where: 'barcode = ? AND is_active = 1',
        whereArgs: [barcode.trim()],
        limit: 1,
      );
    }
    return result.isNotEmpty;
  }

  Future<int> getProductCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM products');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<String> getNextItemCode() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(item_code, 5) AS INTEGER)), 0) + 1 AS next_code FROM products WHERE item_code LIKE 'PRD-%'",
    );
    final nextNum = (result.first['next_code'] as num?)?.toInt() ?? 1;
    return 'PRD-${nextNum.toString().padLeft(5, '0')}';
  }

  /// Check if an item_code already exists in the products table.
  /// Optionally exclude a product ID (for edit mode).
  Future<bool> checkItemCodeExists(String code, {int? excludeId}) async {
    final db = await _db;
    if (code.trim().isEmpty) return false;
    List<Map<String, dynamic>> result;
    if (excludeId != null) {
      result = await db.query(
        'products',
        where: 'item_code = ? AND id != ?',
        whereArgs: [code.trim(), excludeId],
        limit: 1,
      );
    } else {
      result = await db.query(
        'products',
        where: 'item_code = ?',
        whereArgs: [code.trim()],
        limit: 1,
      );
    }
    return result.isNotEmpty;
  }

  Future<int> getProductCountByWarehouse(int warehouseId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM products WHERE warehouse_id = ? AND is_active = 1',
      [warehouseId],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double?> getProductStockInWarehouse(int productId, int warehouseId) async {
    final db = await _db;
    final results = await db.query(
      'products',
      columns: ['current_stock'],
      where: 'id = ? AND warehouse_id = ?',
      whereArgs: [productId, warehouseId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return (results.first['current_stock'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> updateWeightedAverageCost(int productId, double purchasedQty, double purchasedUnitCost) async {
    if (purchasedQty <= 0) return;
    final db = await _db;
    final product = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (product.isEmpty) return;

    final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
    final currentAvgCost = MoneyHelper.readMoney(product.first['average_cost']);

    final newTotalValue = (currentStock * currentAvgCost) + (purchasedQty * purchasedUnitCost);
    final newTotalStock = currentStock + purchasedQty;
    final newAvgCost = newTotalStock > 0 ? newTotalValue / newTotalStock : purchasedUnitCost;

    await db.update(
      'products',
      {
        'average_cost': MoneyHelper.toCents(newAvgCost),
        'cost_price': MoneyHelper.toCents(newAvgCost),  // Keep cost_price in sync for backward compatibility
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Stock Movement Log
  // ══════════════════════════════════════════════════════════════

  /// Log a stock movement for audit trail
  /// movement_type: 'sale', 'purchase', 'return', 'adjustment', 'transfer', 'opening', 'damage'
  Future<int> logStockMovement({
    required int productId,
    required String movementType,
    required double quantity,
    String? referenceType,
    String? referenceId,
    String? notes,
    double unitCost = 0.0,
  }) async {
    final db = await _db;
    return await db.insert('stock_movements', {
      'product_id': productId,
      'movement_type': movementType,
      'quantity': quantity,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'unit_cost': MoneyHelper.toCents(unitCost),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get stock movement history for a product
  Future<List<Map<String, dynamic>>> getStockMovements(int productId, {int limit = 50}) async {
    final db = await _db;
    return await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Get stock movements by type (e.g., all sales today)
  Future<List<Map<String, dynamic>>> getStockMovementsByType(String movementType, {DateTime? since}) async {
    final db = await _db;
    if (since != null) {
      return await db.query(
        'stock_movements',
        where: 'movement_type = ? AND created_at >= ?',
        whereArgs: [movementType, since.toIso8601String()],
        orderBy: 'created_at DESC',
      );
    }
    return await db.query(
      'stock_movements',
      where: 'movement_type = ?',
      whereArgs: [movementType],
      orderBy: 'created_at DESC',
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Product>> getAllProductObjects({bool? activeOnly, String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final maps = await getAllProducts(activeOnly: activeOnly, orderBy: orderBy, limit: limit, offset: offset);
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<List<Product>> searchProductObjects(String query, {int? warehouseId}) async {
    final maps = await searchProducts(query, warehouseId: warehouseId);
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<Product?> getProductObjectById(int id) async {
    final map = await getProductById(id);
    return map != null ? Product.fromMap(map) : null;
  }
}
