import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

class ReferenceDataRepository {
  final DatabaseHelper _dbHelper;
  ReferenceDataRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Currency CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrency(Map<String, dynamic> currencyMap) async {
    final db = await _db;
    return await db.insert('currencies', currencyMap);
  }

  Future<List<Map<String, dynamic>>> getAllCurrencies(
      {String orderBy = 'is_default DESC, code ASC'}) async {
    final db = await _db;
    return await db.query('currencies', orderBy: orderBy);
  }

  Future<Map<String, dynamic>?> getDefaultCurrency() async {
    final db = await _db;
    final results = await db.query('currencies',
        where: 'is_default = ?', whereArgs: [1], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCurrency(int id, Map<String, dynamic> currencyMap) async {
    final db = await _db;
    return await db
        .update('currencies', currencyMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCurrency(int id) async {
    final db = await _db;
    return await db.delete('currencies', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setDefaultCurrency(int id) async {
    final db = await _db;
    await db.update('currencies', {'is_default': 0});
    await db.update('currencies', {'is_default': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Units Master (CRUD)
  // ══════════════════════════════════════════════════════════════

  Future<int> insertUnit(Map<String, dynamic> unitMap) async {
    final db = await _db;
    return await db.insert('units', unitMap);
  }

  Future<int> updateUnit(int id, Map<String, dynamic> unitMap) async {
    final db = await _db;
    return await db.update('units', unitMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteUnit(int id) async {
    final db = await _db;
    // Check if unit is used by any product
    final productsWithUnit = await db.query(
      'products',
      where:
          'base_unit_id = ? OR purchase_unit_id = ? OR sale_unit_id = ? OR unit_id = ?',
      whereArgs: [id, id, id, id],
      limit: 1,
    );
    if (productsWithUnit.isNotEmpty) {
      throw Exception('لا يمكن حذف الوحدة لأنها مستخدمة في أصناف موجودة');
    }
    return await db.delete('units', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllUnits(
      {String? unitType, bool activeOnly = false}) async {
    final db = await _db;
    String? where;
    List<Object>? whereArgs;
    if (unitType != null && activeOnly) {
      where = 'unit_type = ? AND is_active = 1';
      whereArgs = [unitType];
    } else if (unitType != null) {
      where = 'unit_type = ?';
      whereArgs = [unitType];
    } else if (activeOnly) {
      where = 'is_active = 1';
    }
    return await db.query('units',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'display_order ASC, id ASC');
  }

  Future<Map<String, dynamic>?> getUnitById(int id) async {
    final db = await _db;
    final results =
        await db.query('units', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Get unit name by ID from the units table
  Future<String> getUnitNameById(int unitId) async {
    final db = await _db;
    final results =
        await db.query('units', where: 'id = ?', whereArgs: [unitId], limit: 1);
    if (results.isNotEmpty) {
      return results.first['name_ar'] as String? ?? '';
    }
    // Fallback to old static mapping for backward compat
    return _getUnitName(unitId);
  }

  // ══════════════════════════════════════════════════════════════
  //  Unit Conversions (Multi-Unit support)
  // ══════════════════════════════════════════════════════════════

  /// Insert a unit conversion for a product (e.g., 1 carton = 24 pieces)
  Future<int> insertUnitConversion(Map<String, dynamic> conversionMap) async {
    final db = await _db;
    return await db.insert('unit_conversions',
        MoneyHelper.toCentsMap(conversionMap, ['sell_price', 'cost_price']));
  }

  /// Get all unit conversions for a product
  Future<List<Map<String, dynamic>>> getUnitConversions(int productId) async {
    final db = await _db;
    return await db.query(
      'unit_conversions',
      where: 'product_id = ? AND is_active = 1',
      whereArgs: [productId],
      orderBy: 'id ASC',
    );
  }

  /// Update a unit conversion
  Future<int> updateUnitConversion(
      int id, Map<String, dynamic> conversionMap) async {
    final db = await _db;
    return await db.update('unit_conversions',
        MoneyHelper.toCentsMap(conversionMap, ['sell_price', 'cost_price']),
        where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a unit conversion
  Future<int> deleteUnitConversion(int id) async {
    final db = await _db;
    return await db
        .delete('unit_conversions', where: 'id = ?', whereArgs: [id]);
  }

  /// Find unit conversion by barcode (for POS barcode scanning)
  Future<Map<String, dynamic>?> findUnitConversionByBarcode(
      String barcode) async {
    final db = await _db;
    final results = await db.query(
      'unit_conversions',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all available units for a product (base unit + conversions)
  /// Returns a list of maps with: {unit_name, conversion_factor, sell_price, barcode, unit_id, is_base}
  Future<List<Map<String, dynamic>>> getAvailableUnitsForProduct(
      int productId) async {
    final db = await _db;
    // Get base product info
    final product = await db.query('products',
        where: 'id = ?', whereArgs: [productId], limit: 1);
    if (product.isEmpty) return [];

    // Resolve base unit name from units table (fallback to static mapping)
    final baseUnitId = product.first['base_unit_id'] as int? ??
        product.first['unit_id'] as int? ??
        1;
    String baseUnitName;
    final unitRow = await db.query('units',
        where: 'id = ?', whereArgs: [baseUnitId], limit: 1);
    if (unitRow.isNotEmpty) {
      baseUnitName = unitRow.first['name_ar'] as String? ?? '';
    } else {
      baseUnitName = _getUnitName(baseUnitId);
    }
    final baseSellPrice = MoneyHelper.readMoney(product.first['sell_price']);
    final baseCostPrice = MoneyHelper.readMoney(product.first['cost_price']);

    // Start with base unit (factor = 1.0)
    final units = <Map<String, dynamic>>[
      {
        'unit_name': baseUnitName,
        'conversion_factor': 1.0,
        'sell_price': baseSellPrice,
        'cost_price': baseCostPrice,
        'barcode': product.first['barcode'] as String? ?? '',
        'is_base': 1,
        'unit_id': baseUnitId,
      },
    ];

    // Add converted units
    final conversions = await db.query(
      'unit_conversions',
      where: 'product_id = ? AND is_active = 1',
      whereArgs: [productId],
    );
    for (final conv in conversions) {
      final fromUnit = conv['from_unit'] as String? ?? '';
      final factor = (conv['conversion_factor'] as num?)?.toDouble() ?? 1.0;
      final convSellPrice = MoneyHelper.readMoney(conv['sell_price']) != 0.0
          ? MoneyHelper.readMoney(conv['sell_price'])
          : (baseSellPrice * factor);
      final convCostPrice = MoneyHelper.readMoney(conv['cost_price']) != 0.0
          ? MoneyHelper.readMoney(conv['cost_price'])
          : (baseCostPrice * factor);
      // Resolve unit_id from the conversion if available
      final fromUnitId = conv['from_unit_id'] as int?;
      units.add({
        'unit_name': fromUnit,
        'conversion_factor': factor,
        'sell_price': convSellPrice,
        'cost_price': convCostPrice,
        'barcode': conv['barcode'] as String? ?? '',
        'is_base': 0,
        'conversion_id': conv['id'],
        if (fromUnitId != null) 'unit_id': fromUnitId,
      });
    }
    return units;
  }

  // ══════════════════════════════════════════════════════════════
  //  Category CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllCategories() async {
    final db = await _db;
    return await db.query('categories',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
  }

  Future<int> insertCategory(Map<String, dynamic> categoryMap) async {
    final db = await _db;
    return await db.insert('categories', categoryMap);
  }

  Future<int> deleteCategory(int id) async {
    final db = await _db;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateCategory(int id, Map<String, dynamic> categoryMap) async {
    final db = await _db;
    return await db
        .update('categories', categoryMap, where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Warehouse methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllWarehouses() async {
    final db = await _db;
    return await db.query('warehouses',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
  }

  Future<int> insertWarehouse(Map<String, dynamic> warehouseMap) async {
    final db = await _db;
    return await db.insert('warehouses', warehouseMap);
  }

  Future<int> updateWarehouse(int id, Map<String, dynamic> warehouseMap) async {
    final db = await _db;
    return await db
        .update('warehouses', warehouseMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWarehouse(int id) async {
    final db = await _db;
    return await db.delete('warehouses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchWarehouses(String query) async {
    final db = await _db;
    final likeQuery = '%$query%';
    return await db.query(
      'warehouses',
      where: 'is_active = ? AND (name LIKE ? OR location LIKE ?)',
      whereArgs: [1, likeQuery, likeQuery],
      orderBy: 'name ASC',
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Employee CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertEmployee(Map<String, dynamic> employeeMap) async {
    final db = await _db;
    return await db.insert(
        'employees', MoneyHelper.toCentsMap(employeeMap, ['balance']));
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await _db;
    return await db.query('employees', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getEmployeeById(int id) async {
    final db = await _db;
    final results =
        await db.query('employees', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateEmployee(int id, Map<String, dynamic> employeeMap) async {
    final db = await _db;
    return await db.update(
        'employees', MoneyHelper.toCentsMap(employeeMap, ['balance']),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteEmployee(int id) async {
    final db = await _db;
    return await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  /// Alias for getAllEmployees - used by some screens
  Future<List<Map<String, dynamic>>> getEmployees() async {
    return getAllEmployees();
  }

  // ══════════════════════════════════════════════════════════════
  //  Fiscal Year methods
  // ══════════════════════════════════════════════════════════════

  /// Insert a new fiscal year record.
  Future<int> insertFiscalYear(Map<String, dynamic> fiscalYearMap) async {
    final db = await _db;
    return await db.insert('fiscal_years', fiscalYearMap);
  }

  // ══════════════════════════════════════════════════════════════
  //  Settings methods
  // ══════════════════════════════════════════════════════════════

  Future<String?> getSetting(String key) async {
    final db = await _db;
    final results = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _db;
    await db.insert(
        'settings',
        {
          'key': key,
          'value': value,
          'updated_at': DateTime.now().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSetting(String key) async {
    final db = await _db;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Notification CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertNotification(Map<String, dynamic> notificationMap) async {
    final db = await _db;
    return await db.insert('notifications', notificationMap);
  }

  Future<List<Map<String, dynamic>>> getAllNotifications(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.query('notifications', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> getNotificationsByType(String type,
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.query('notifications',
        where: 'type = ?', whereArgs: [type], orderBy: orderBy);
  }

  Future<int> markNotificationAsRead(int id) async {
    final db = await _db;
    return await db.update('notifications', {'is_read': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> markAllNotificationsAsRead() async {
    final db = await _db;
    return await db.update('notifications', {'is_read': 1},
        where: 'is_read = ?', whereArgs: [0]);
  }

  Future<int> deleteNotification(int id) async {
    final db = await _db;
    return await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Private helpers
  // ══════════════════════════════════════════════════════════════

  /// Helper: Get unit name from unit_id (matches static list in add_product_sheet)
  String _getUnitName(int unitId) {
    const units = {
      1: 'قطعة',
      2: 'كيلو',
      3: 'لتر',
      4: 'متر',
      5: 'علبة',
      6: 'كرتون',
      7: 'طن',
      8: 'جرام',
    };
    return units[unitId] ?? 'قطعة';
  }
}
