import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../../models/inventory_cost_layer_model.dart';
import '../database_helper.dart';

class CostingEngineService {
  final DatabaseHelper _dbHelper;
  CostingEngineService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Create a new cost layer when inventory is purchased.
  ///
  /// Validates that quantity and unitCost are positive before creating the layer.
  /// Zero or negative values would produce incorrect COGS calculations.
  Future<void> createCostLayer({
    required int productId,
    int? warehouseId,
    required double quantity,
    required double unitCost,
    String? referenceType,
    String? referenceId,
  }) async {
    if (quantity <= 0.001) {
      throw Exception('Cannot create cost layer with zero or negative quantity: $quantity');
    }
    if (unitCost <= 0) {
      throw Exception('Cannot create cost layer with zero or negative unit cost: $unitCost');
    }
    final db = await _db;
    final layer = InventoryCostLayer(
      productId: productId,
      warehouseId: warehouseId,
      quantityOriginal: quantity,
      quantityRemaining: quantity,
      unitCost: unitCost,
      acquisitionDate: DateTime.now(),
      referenceType: referenceType,
      referenceId: referenceId,
    );
    await db.insert('inventory_cost_layers', layer.toMap());
  }

  /// Calculate COGS for a sale, consuming cost layers per the product's costing method.
  /// Returns the total COGS amount and creates movement_cost_allocations.
  ///
  /// ⚠️ This method does NOT wrap its operations in a database transaction.
  /// Prefer [calculateCOGSInTransaction] which accepts an existing [Transaction]
  /// to guarantee atomicity. This method should only be used for read-only
  /// scenarios or when the caller manages the transaction externally.
  Future<double> calculateCOGS({
    required int productId,
    required double baseQuantity,
    required String invoiceId,
    int? warehouseId,
  }) async {
    if (baseQuantity <= 0.001) return 0.0;
    final db = await _db;

    // Get product's costing method
    final productRow = await db.query('products',
        columns: ['costing_method', 'average_cost', 'cost_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (productRow.isEmpty) return 0.0;

    final costingMethodStr =
        productRow.first['costing_method'] as String? ?? 'weighted_average';
    final costingMethod = CostingMethodExt.fromValue(costingMethodStr);

    if (costingMethod == CostingMethod.weightedAverage) {
      // Use existing average_cost logic
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(productRow.first['cost_price']);
      return effectiveCost * baseQuantity;
    }

    // FIFO or LIFO: consume cost layers
    final orderBy = costingMethod == CostingMethod.fifo
        ? 'acquisition_date ASC, id ASC'
        : 'acquisition_date DESC, id DESC';

    final layers = await db.query('inventory_cost_layers',
        where:
            'product_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0',
        whereArgs: [productId],
        orderBy: orderBy);

    if (layers.isEmpty) {
      // Fallback to average cost if no layers
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(productRow.first['cost_price']);
      return effectiveCost * baseQuantity;
    }

    double remainingQty = baseQuantity;
    double totalCogs = 0.0;
    final now = DateTime.now().toIso8601String();

    for (final layerMap in layers) {
      if (remainingQty <= 0.001) break;

      final layerId = layerMap['id'] as int;
      final qtyRemaining = (layerMap['quantity_remaining'] as num).toDouble();
      final unitCost = MoneyHelper.readMoney(layerMap['unit_cost']);

      final qtyToConsume =
          remainingQty > qtyRemaining ? qtyRemaining : remainingQty;
      final layerCogs = unitCost * qtyToConsume;
      totalCogs += layerCogs;
      remainingQty -= qtyToConsume;

      final newQtyRemaining = qtyRemaining - qtyToConsume;
      final isConsumed = newQtyRemaining < 0.001;

      // Update the layer
      await db.update(
          'inventory_cost_layers',
          {
            'quantity_remaining': newQtyRemaining,
            'is_fully_consumed': isConsumed ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [layerId]);

      // Create allocation record
      await db.insert('movement_cost_allocations', {
        'product_id': productId,
        'cost_layer_id': layerId,
        'invoice_id': invoiceId,
        'quantity_used': qtyToConsume,
        'unit_cost': MoneyHelper.toCents(unitCost),
        'total_cost': MoneyHelper.toCents(layerCogs),
        'created_at': now,
      });
    }

    // If still remaining qty (not enough layers), use average cost for remainder
    if (remainingQty > 0.001) {
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(productRow.first['cost_price']);
      totalCogs += effectiveCost * remainingQty;
    }

    return totalCogs;
  }

  /// Calculate COGS within an existing database transaction (for shift posting)
  Future<double> calculateCOGSInTransaction(Transaction txn,
      {required int productId,
      required double baseQuantity,
      required String invoiceId,
      required int codeOffset}) async {
    if (baseQuantity <= 0.001) return 0.0;
    // Get product's costing method
    final productRow = await txn.query('products',
        columns: ['costing_method', 'average_cost', 'cost_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (productRow.isEmpty) return 0.0;

    final costingMethodStr =
        productRow.first['costing_method'] as String? ?? 'weighted_average';
    final costingMethod = CostingMethodExt.fromValue(costingMethodStr);

    if (costingMethod == CostingMethod.weightedAverage) {
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      return (avgCost > 0
              ? avgCost
              : MoneyHelper.readMoney(productRow.first['cost_price'])) *
          baseQuantity;
    }

    // FIFO or LIFO
    final orderBy = costingMethod == CostingMethod.fifo
        ? 'acquisition_date ASC, id ASC'
        : 'acquisition_date DESC, id DESC';

    final layers = await txn.query('inventory_cost_layers',
        where:
            'product_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0',
        whereArgs: [productId],
        orderBy: orderBy);

    if (layers.isEmpty) {
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      return (avgCost > 0
              ? avgCost
              : MoneyHelper.readMoney(productRow.first['cost_price'])) *
          baseQuantity;
    }

    double remainingQty = baseQuantity;
    double totalCogs = 0.0;
    final now = DateTime.now().toIso8601String();

    for (final layerMap in layers) {
      if (remainingQty <= 0.001) break;
      final layerId = layerMap['id'] as int;
      final qtyRemaining = (layerMap['quantity_remaining'] as num).toDouble();
      final unitCost = MoneyHelper.readMoney(layerMap['unit_cost']);
      final qtyToConsume =
          remainingQty > qtyRemaining ? qtyRemaining : remainingQty;
      final layerCogs = unitCost * qtyToConsume;
      totalCogs += layerCogs;
      remainingQty -= qtyToConsume;
      final newQtyRemaining = qtyRemaining - qtyToConsume;
      await txn.update(
          'inventory_cost_layers',
          {
            'quantity_remaining': newQtyRemaining,
            'is_fully_consumed': newQtyRemaining < 0.001 ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [layerId]);
      await txn.insert('movement_cost_allocations', {
        'product_id': productId,
        'cost_layer_id': layerId,
        'invoice_id': invoiceId,
        'quantity_used': qtyToConsume,
        'unit_cost': MoneyHelper.toCents(unitCost),
        'total_cost': MoneyHelper.toCents(layerCogs),
        'created_at': now,
      });
    }

    if (remainingQty > 0.001) {
      final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
      totalCogs += (avgCost > 0
              ? avgCost
              : MoneyHelper.readMoney(productRow.first['cost_price'])) *
          remainingQty;
    }

    return totalCogs;
  }

  /// Reverse COGS allocations for a cancelled/returned invoice
  Future<void> reverseCOGSAllocations(String invoiceId) async {
    final db = await _db;
    final allocations = await db.query('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);

    for (final alloc in allocations) {
      final layerId = alloc['cost_layer_id'] as int;
      final qtyUsed = (alloc['quantity_used'] as num).toDouble();

      // Restore the layer quantity
      await db.rawUpdate(
          'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining + ?, is_fully_consumed = 0 WHERE id = ?',
          [qtyUsed, layerId]);
    }

    // Delete the allocation records
    await db.delete('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  /// Reverse COGS allocations within an existing transaction (M-08 fix)
  /// Used for sale returns to restore original cost layer allocations
  /// instead of consuming new layers via calculateCOGSInTransaction.
  Future<void> reverseCOGSAllocationsInTransaction(Transaction txn, {required String invoiceId}) async {
    final allocations = await txn.query('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
    for (final alloc in allocations) {
      final layerId = alloc['cost_layer_id'] as int;
      final qtyUsed = (alloc['quantity_used'] as num).toDouble();
      await txn.rawUpdate(
          'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining + ?, is_fully_consumed = 0 WHERE id = ?',
          [qtyUsed, layerId]);
    }
    await txn.delete('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  /// Initialize cost layers for existing products during migration
  Future<void> initializeCostLayersForExistingProducts() async {
    final db = await _db;
    final products = await db
        .query('products', where: 'current_stock > 0 AND track_stock = 1');

    for (final p in products) {
      final productId = p['id'] as int;
      // Check if layer already exists
      final existing = await db.query('inventory_cost_layers',
          where: 'product_id = ?',
          whereArgs: [productId],
          limit: 1);
      if (existing.isNotEmpty) continue;

      final currentStock = (p['current_stock'] as num).toDouble();
      final avgCost = MoneyHelper.readMoney(p['average_cost']);
      final effectiveCost =
          avgCost > 0 ? avgCost : MoneyHelper.readMoney(p['cost_price']);

      if (currentStock > 0 && effectiveCost > 0) {
        await createCostLayer(
          productId: productId,
          warehouseId: p['warehouse_id'] as int?,
          quantity: currentStock,
          unitCost: effectiveCost,
          referenceType: 'migration',
          referenceId: 'v38_init',
        );
      }
    }
  }

  /// Get cost layers for a product (for UI display)
  Future<List<InventoryCostLayer>> getCostLayers(int productId) async {
    final db = await _db;
    final rows = await db.query('inventory_cost_layers',
        where: 'product_id = ? AND is_fully_consumed = 0',
        whereArgs: [productId],
        orderBy: 'acquisition_date ASC');
    return rows.map((r) => InventoryCostLayer.fromMap(r)).toList();
  }

  /// Get costing method for a product
  Future<CostingMethod> getProductCostingMethod(int productId) async {
    final db = await _db;
    final row = await db.query('products',
        columns: ['costing_method'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (row.isEmpty) return CostingMethod.weightedAverage;
    return CostingMethodExt.fromValue(
        row.first['costing_method'] as String? ?? 'weighted_average');
  }
}
