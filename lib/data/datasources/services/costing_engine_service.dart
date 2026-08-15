import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/inventory_cost_layer_model.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

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
      throw Exception(
          'Cannot create cost layer with zero or negative quantity: $quantity');
    }
    if (unitCost <= 0) {
      throw Exception(
          'Cannot create cost layer with zero or negative unit cost: $unitCost');
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
    await db.insert('inventory_cost_layers', MoneyHelper.toCentsMap(layer.toMap(), MoneyHelper.stockMovementMoneyFields));
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
        columns: ['costing_method', 'average_cost', 'cost_price', 'warehouse_id'],
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

    final effectiveWarehouseId = warehouseId ??
        (productRow.first['warehouse_id'] as num?)?.toInt();
    final layerWhere = effectiveWarehouseId == null
        ? 'product_id = ? AND warehouse_id IS NULL AND is_fully_consumed = 0 AND quantity_remaining > 0'
        : 'product_id = ? AND warehouse_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0';
    final layerArgs = effectiveWarehouseId == null
        ? [productId]
        : [productId, effectiveWarehouseId];
    final layers = await db.query('inventory_cost_layers',
        where: layerWhere,
        whereArgs: layerArgs,
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
      required int codeOffset,
      int? warehouseId}) async {
    if (baseQuantity <= 0.001) return 0.0;
    // Get product's costing method
    final productRow = await txn.query('products',
        columns: ['costing_method', 'average_cost', 'cost_price', 'warehouse_id'],
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

    final effectiveWarehouseId = warehouseId ??
        (productRow.first['warehouse_id'] as num?)?.toInt();
    final layerWhere = effectiveWarehouseId == null
        ? 'product_id = ? AND warehouse_id IS NULL AND is_fully_consumed = 0 AND quantity_remaining > 0'
        : 'product_id = ? AND warehouse_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0';
    final layerArgs = effectiveWarehouseId == null
        ? [productId]
        : [productId, effectiveWarehouseId];
    final layers = await txn.query('inventory_cost_layers',
        where: layerWhere,
        whereArgs: layerArgs,
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
      final fallbackCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(productRow.first['cost_price']);
      if (fallbackCost > 0) {
        // Materialize the fallback as a fully-consumed synthetic layer so
        // cancellation/returns can restore exactly this missing allocation.
        final fallbackLayerId = await txn.insert('inventory_cost_layers', {
          'product_id': productId,
          'warehouse_id': effectiveWarehouseId,
          'quantity_original': remainingQty,
          'quantity_remaining': 0.0,
          'unit_cost': MoneyHelper.toCents(fallbackCost),
          'acquisition_date': now,
          'is_fully_consumed': 1,
          'reference_type': 'cogs_fallback',
          'reference_id': invoiceId,
        });
        final fallbackCostTotal = fallbackCost * remainingQty;
        totalCogs += fallbackCostTotal;
        await txn.insert('movement_cost_allocations', {
          'product_id': productId,
          'cost_layer_id': fallbackLayerId,
          'invoice_id': invoiceId,
          'quantity_used': remainingQty,
          'unit_cost': MoneyHelper.toCents(fallbackCost),
          'total_cost': MoneyHelper.toCents(fallbackCostTotal),
          'created_at': now,
        });
      }
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
  Future<double> reverseCOGSAllocationsInTransaction(
    Transaction txn, {
    required String invoiceId,
    Map<int, double>? productQuantities,
    Map<int, double>? restoredCostByProduct,
  }) async {
    final allocations = await txn.query(
      'movement_cost_allocations',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id DESC',
    );
    double restoredCost = 0.0;
    for (final alloc in allocations) {
      final productId = (alloc['product_id'] as num).toInt();
      final layerId = alloc['cost_layer_id'] as int;
      final qtyUsed = (alloc['quantity_used'] as num).toDouble();
      final requested = productQuantities?[productId];
      if (requested != null && requested <= 0.001) continue;
      final qtyToRestore = requested == null
          ? qtyUsed
          : (requested < qtyUsed ? requested : qtyUsed);
      if (qtyToRestore <= 0.001) continue;

      final unitCost = MoneyHelper.readMoney(alloc['unit_cost']);
      final allocationCost = unitCost * qtyToRestore;
      restoredCost += allocationCost;
      if (restoredCostByProduct != null) {
        restoredCostByProduct[productId] =
            (restoredCostByProduct[productId] ?? 0.0) + allocationCost;
      }
      await txn.rawUpdate(
        'UPDATE inventory_cost_layers '
        'SET quantity_remaining = quantity_remaining + ?, is_fully_consumed = 0 '
        'WHERE id = ?',
        [qtyToRestore, layerId],
      );

      if (qtyToRestore + 0.001 < qtyUsed) {
        final remainingQty = qtyUsed - qtyToRestore;
        await txn.update(
          'movement_cost_allocations',
          {
            'quantity_used': remainingQty,
            'total_cost': MoneyHelper.toCents(remainingQty * unitCost),
          },
          where: 'id = ?',
          whereArgs: [alloc['id']],
        );
      } else {
        await txn.delete(
          'movement_cost_allocations',
          where: 'id = ?',
          whereArgs: [alloc['id']],
        );
      }
      if (productQuantities != null && requested != null) {
        productQuantities[productId] = requested - qtyToRestore;
      }
    }
    return restoredCost;
  }

  /// Initialize cost layers for existing products during migration
  Future<void> initializeCostLayersForExistingProducts() async {
    final db = await _db;
    final products = await db.query('products',
        where: 'current_stock > 0 AND track_stock = 1');

    for (final p in products) {
      final productId = p['id'] as int;
      // A product may have one stock row per warehouse. Scope the duplicate
      // check by warehouse, including the legacy NULL warehouse case.
      final warehouseId = (p['warehouse_id'] as num?)?.toInt();
      final existing = warehouseId == null
          ? await db.query(
              'inventory_cost_layers',
              where: 'product_id = ? AND warehouse_id IS NULL',
              whereArgs: [productId],
              limit: 1,
            )
          : await db.query(
              'inventory_cost_layers',
              where: 'product_id = ? AND warehouse_id = ?',
              whereArgs: [productId, warehouseId],
              limit: 1,
            );
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
