import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات طرق تسعير المخزون — FIFO, LIFO, Weighted Average
///
/// Inventory costing method tests:
///   1. FIFO costing calculation
///   2. LIFO costing calculation
///   3. Weighted Average costing calculation
///   4. Cost layer consumption and reversal
///
/// These tests simulate the costing engine logic using an in-memory
/// database, verifying that cost layers are consumed in the correct
/// order and that COGS is computed accurately.
/// ══════════════════════════════════════════════════════════════════

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 49,
      onCreate: (database, version) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper: insert a product with a specific costing method.
  Future<int> _insertProduct({
    required String costingMethod,
    double currentStock = 0.0,
    double costPrice = 0.0,
    double averageCost = 0.0,
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('products', {
      'name_ar': 'منتج اختبار',
      'name_en': 'Test Product',
      'item_code': 'TEST-${DateTime.now().microsecondsSinceEpoch}',
      'costing_method': costingMethod,
      'current_stock': currentStock,
      'cost_price': MoneyHelper.toCents(costPrice),
      'average_cost': MoneyHelper.toCents(averageCost),
      'sell_price': MoneyHelper.toCents(costPrice * 1.5),
      'is_active': 1,
      'track_stock': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Helper: insert a cost layer.
  Future<int> _insertCostLayer({
    required int productId,
    required double quantityOriginal,
    required double quantityRemaining,
    required double unitCost,
    String? referenceType,
    String? referenceId,
  }) async {
    final now = DateTime.now().toIso8601String();
    return await db.insert('inventory_cost_layers', {
      'product_id': productId,
      'quantity_original': quantityOriginal,
      'quantity_remaining': quantityRemaining,
      'unit_cost': MoneyHelper.toCents(unitCost),
      'acquisition_date': now,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'is_fully_consumed': quantityRemaining < 0.001 ? 1 : 0,
      'created_at': now,
    });
  }

  /// Simulate FIFO COGS calculation.
  /// Consumes layers in acquisition_date ASC order.
  Future<double> _calculateFIFOCOGS({
    required int productId,
    required double baseQuantity,
    required String invoiceId,
  }) async {
    if (baseQuantity <= 0.001) return 0.0;

    final layers = await db.query('inventory_cost_layers',
        where: 'product_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0',
        whereArgs: [productId],
        orderBy: 'acquisition_date ASC, id ASC');

    if (layers.isEmpty) {
      // Fallback to average cost
      final product = await db.query('products',
          where: 'id = ?', whereArgs: [productId], limit: 1);
      if (product.isEmpty) return 0.0;
      final avgCost = MoneyHelper.readMoney(product.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(product.first['cost_price']);
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

      final qtyToConsume = remainingQty > qtyRemaining ? qtyRemaining : remainingQty;
      final layerCogs = unitCost * qtyToConsume;
      totalCogs += layerCogs;
      remainingQty -= qtyToConsume;

      final newQtyRemaining = qtyRemaining - qtyToConsume;
      final isConsumed = newQtyRemaining < 0.001;

      await db.update('inventory_cost_layers', {
        'quantity_remaining': newQtyRemaining,
        'is_fully_consumed': isConsumed ? 1 : 0,
      }, where: 'id = ?', whereArgs: [layerId]);

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

    // If still remaining qty, use average cost for remainder
    if (remainingQty > 0.001) {
      final product = await db.query('products',
          where: 'id = ?', whereArgs: [productId], limit: 1);
      final avgCost = MoneyHelper.readMoney(product.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(product.first['cost_price']);
      totalCogs += effectiveCost * remainingQty;
    }

    return totalCogs;
  }

  /// Simulate LIFO COGS calculation.
  /// Consumes layers in acquisition_date DESC order.
  Future<double> _calculateLIFOCOGS({
    required int productId,
    required double baseQuantity,
    required String invoiceId,
  }) async {
    if (baseQuantity <= 0.001) return 0.0;

    final layers = await db.query('inventory_cost_layers',
        where: 'product_id = ? AND is_fully_consumed = 0 AND quantity_remaining > 0',
        whereArgs: [productId],
        orderBy: 'acquisition_date DESC, id DESC');

    if (layers.isEmpty) {
      final product = await db.query('products',
          where: 'id = ?', whereArgs: [productId], limit: 1);
      if (product.isEmpty) return 0.0;
      final avgCost = MoneyHelper.readMoney(product.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(product.first['cost_price']);
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

      final qtyToConsume = remainingQty > qtyRemaining ? qtyRemaining : remainingQty;
      final layerCogs = unitCost * qtyToConsume;
      totalCogs += layerCogs;
      remainingQty -= qtyToConsume;

      final newQtyRemaining = qtyRemaining - qtyToConsume;
      final isConsumed = newQtyRemaining < 0.001;

      await db.update('inventory_cost_layers', {
        'quantity_remaining': newQtyRemaining,
        'is_fully_consumed': isConsumed ? 1 : 0,
      }, where: 'id = ?', whereArgs: [layerId]);

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

    if (remainingQty > 0.001) {
      final product = await db.query('products',
          where: 'id = ?', whereArgs: [productId], limit: 1);
      final avgCost = MoneyHelper.readMoney(product.first['average_cost']);
      final effectiveCost = avgCost > 0
          ? avgCost
          : MoneyHelper.readMoney(product.first['cost_price']);
      totalCogs += effectiveCost * remainingQty;
    }

    return totalCogs;
  }

  /// Simulate Weighted Average COGS calculation.
  Future<double> _calculateWeightedAverageCOGS({
    required int productId,
    required double baseQuantity,
  }) async {
    if (baseQuantity <= 0.001) return 0.0;

    final product = await db.query('products',
        columns: ['costing_method', 'average_cost', 'cost_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (product.isEmpty) return 0.0;

    final avgCost = MoneyHelper.readMoney(product.first['average_cost']);
    final effectiveCost = avgCost > 0
        ? avgCost
        : MoneyHelper.readMoney(product.first['cost_price']);
    return effectiveCost * baseQuantity;
  }

  /// Simulate COGS reversal (as used for invoice returns).
  Future<void> _reverseCOGSAllocations(String invoiceId) async {
    final allocations = await db.query('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);

    for (final alloc in allocations) {
      final layerId = alloc['cost_layer_id'] as int;
      final qtyUsed = (alloc['quantity_used'] as num).toDouble();

      await db.rawUpdate(
        'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining + ?, is_fully_consumed = 0 WHERE id = ?',
        [qtyUsed, layerId],
      );
    }

    await db.delete('movement_cost_allocations',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Test: FIFO costing calculation
  // ══════════════════════════════════════════════════════════════

  group('FIFO costing — المتقدم أولاً', () {
    test('Single layer: FIFO COGS = quantity * unit_cost', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 100.0,
        averageCost: 10.0,
      );
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
      );

      final cogs = await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 30.0,
        invoiceId: 'INV-FIFO-001',
      );

      expect(cogs, 300.0,
          reason: 'FIFO: 30 units @ 10 = 300');
    });

    test('Multiple layers: FIFO consumes oldest first / FIFO يستهلك الأقدم أولاً', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 200.0,
        averageCost: 12.0,
      );

      // Layer 1: 100 units @ 10 (oldest)
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-001',
      );
      // Layer 2: 100 units @ 15 (newer)
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 15.0,
        referenceType: 'purchase',
        referenceId: 'PO-002',
      );

      // Sell 120 units: FIFO takes 100 from Layer1 + 20 from Layer2
      final cogs = await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 120.0,
        invoiceId: 'INV-FIFO-002',
      );

      // COGS = (100 * 10) + (20 * 15) = 1000 + 300 = 1300
      expect(cogs, 1300.0,
          reason: 'FIFO: 100@10 + 20@15 = 1300');

      // Verify Layer1 is fully consumed
      final layer1 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-001']);
      expect(layer1.first['is_fully_consumed'], 1,
          reason: 'Layer1 should be fully consumed');
      expect((layer1.first['quantity_remaining'] as num).toDouble(), lessThan(0.001));

      // Verify Layer2 is partially consumed
      final layer2 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-002']);
      expect(layer2.first['is_fully_consumed'], 0,
          reason: 'Layer2 should not be fully consumed');
      expect((layer2.first['quantity_remaining'] as num).toDouble(), closeTo(80.0, 0.01));
    });

    test('Three layers: FIFO cascading consumption / استهلاك متتالي عبر ثلاث طبقات', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 300.0,
        averageCost: 15.0,
      );

      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 10.0);
      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 12.0);
      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 15.0);

      // Sell 250 units: 100@10 + 100@12 + 50@15
      final cogs = await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 250.0,
        invoiceId: 'INV-FIFO-003',
      );

      // COGS = 1000 + 1200 + 750 = 2950
      expect(cogs, 2950.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: LIFO costing calculation
  // ══════════════════════════════════════════════════════════════

  group('LIFO costing — المتأخر أولاً', () {
    test('Single layer: LIFO COGS = quantity * unit_cost', () async {
      final productId = await _insertProduct(
        costingMethod: 'lifo',
        currentStock: 100.0,
        averageCost: 10.0,
      );
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
      );

      final cogs = await _calculateLIFOCOGS(
        productId: productId,
        baseQuantity: 30.0,
        invoiceId: 'INV-LIFO-001',
      );

      expect(cogs, 300.0);
    });

    test('Multiple layers: LIFO consumes newest first / LIFO يستهلك الأحدث أولاً', () async {
      final productId = await _insertProduct(
        costingMethod: 'lifo',
        currentStock: 200.0,
        averageCost: 12.0,
      );

      // Layer 1: 100 units @ 10 (oldest)
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-LIFO-001',
      );
      // Layer 2: 100 units @ 15 (newer)
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 15.0,
        referenceType: 'purchase',
        referenceId: 'PO-LIFO-002',
      );

      // Sell 120 units: LIFO takes 100 from Layer2 + 20 from Layer1
      final cogs = await _calculateLIFOCOGS(
        productId: productId,
        baseQuantity: 120.0,
        invoiceId: 'INV-LIFO-002',
      );

      // COGS = (100 * 15) + (20 * 10) = 1500 + 200 = 1700
      expect(cogs, 1700.0,
          reason: 'LIFO: 100@15 + 20@10 = 1700');

      // Verify Layer2 (newer) is fully consumed
      final layer2 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-LIFO-002']);
      expect(layer2.first['is_fully_consumed'], 1,
          reason: 'Newer layer should be fully consumed in LIFO');

      // Verify Layer1 (older) is partially consumed
      final layer1 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-LIFO-001']);
      expect(layer1.first['is_fully_consumed'], 0);
      expect((layer1.first['quantity_remaining'] as num).toDouble(), closeTo(80.0, 0.01));
    });

    test('Three layers: LIFO cascading from newest / استهلاك من الأحدث عبر ثلاث طبقات', () async {
      final productId = await _insertProduct(
        costingMethod: 'lifo',
        currentStock: 300.0,
        averageCost: 15.0,
      );

      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 10.0);
      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 12.0);
      await _insertCostLayer(productId: productId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 15.0);

      // Sell 250 units: 100@15 + 100@12 + 50@10
      final cogs = await _calculateLIFOCOGS(
        productId: productId,
        baseQuantity: 250.0,
        invoiceId: 'INV-LIFO-003',
      );

      // COGS = 1500 + 1200 + 500 = 3200
      expect(cogs, 3200.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: Weighted Average costing calculation
  // ══════════════════════════════════════════════════════════════

  group('Weighted Average costing — المتوسط المرجح', () {
    test('Weighted average COGS uses average_cost / التكلفة المتوسطة تستخدم average_cost', () async {
      final productId = await _insertProduct(
        costingMethod: 'weighted_average',
        currentStock: 200.0,
        averageCost: 12.5,
        costPrice: 10.0,
      );

      final cogs = await _calculateWeightedAverageCOGS(
        productId: productId,
        baseQuantity: 50.0,
      );

      // COGS = 50 * 12.5 = 625
      expect(cogs, 625.0,
          reason: 'Weighted Average: 50 @ 12.5 = 625');
    });

    test('Weighted average falls back to cost_price when average_cost is 0 / المتوسط يلجأ لسعر التكلفة عند صفر average_cost', () async {
      final productId = await _insertProduct(
        costingMethod: 'weighted_average',
        currentStock: 100.0,
        averageCost: 0.0,
        costPrice: 15.0,
      );

      final cogs = await _calculateWeightedAverageCOGS(
        productId: productId,
        baseQuantity: 20.0,
      );

      // COGS = 20 * 15 = 300 (fallback to cost_price)
      expect(cogs, 300.0,
          reason: 'Weighted Average fallback: 20 @ 15 = 300');
    });

    test('Weighted average: selling all stock / بيع المخزون بالكامل', () async {
      final productId = await _insertProduct(
        costingMethod: 'weighted_average',
        currentStock: 500.0,
        averageCost: 8.0,
      );

      final cogs = await _calculateWeightedAverageCOGS(
        productId: productId,
        baseQuantity: 500.0,
      );

      expect(cogs, 4000.0,
          reason: 'Weighted Average: 500 @ 8 = 4000');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: Cost layer consumption and reversal
  // ══════════════════════════════════════════════════════════════

  group('Cost layer consumption and reversal — استهلاك وعكس طبقات التكلفة', () {
    test('Allocation records are created during consumption / إنشاء سجلات التخصيص أثناء الاستهلاك', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 100.0,
        averageCost: 10.0,
      );

      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
      );

      await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 30.0,
        invoiceId: 'INV-ALLOC-001',
      );

      final allocations = await db.query('movement_cost_allocations',
          where: 'invoice_id = ?', whereArgs: ['INV-ALLOC-001']);
      expect(allocations.length, 1,
          reason: 'One allocation should be created for single-layer consumption');
      expect(allocations.first['quantity_used'], 30.0);
      expect(MoneyHelper.readMoney(allocations.first['unit_cost']), 10.0);
      expect(MoneyHelper.readMoney(allocations.first['total_cost']), 300.0);
    });

    test('Multi-layer consumption creates multiple allocations / الاستهلاك متعدد الطبقات ينشئ تخصيصات متعددة', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 200.0,
        averageCost: 12.0,
      );

      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-ALLOC-001',
      );
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 15.0,
        referenceType: 'purchase',
        referenceId: 'PO-ALLOC-002',
      );

      await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 120.0,
        invoiceId: 'INV-ALLOC-002',
      );

      final allocations = await db.query('movement_cost_allocations',
          where: 'invoice_id = ?', whereArgs: ['INV-ALLOC-002']);
      expect(allocations.length, 2,
          reason: 'Two allocations for two-layer consumption');

      // First allocation: 100 from Layer1
      expect(allocations[0]['quantity_used'], 100.0);
      expect(MoneyHelper.readMoney(allocations[0]['unit_cost']), 10.0);

      // Second allocation: 20 from Layer2
      expect(allocations[1]['quantity_used'], 20.0);
      expect(MoneyHelper.readMoney(allocations[1]['unit_cost']), 15.0);
    });

    test('Reversal restores consumed layers / عكس القيد يستعيد الطبقات المستهلكة', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 100.0,
        averageCost: 10.0,
      );

      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-REV-001',
      );

      // Consume 30 units
      await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 30.0,
        invoiceId: 'INV-REV-001',
      );

      // Verify layer is partially consumed
      var layer = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-REV-001']);
      expect((layer.first['quantity_remaining'] as num).toDouble(), closeTo(70.0, 0.01));
      expect(layer.first['is_fully_consumed'], 0);

      // Verify allocation exists
      var allocations = await db.query('movement_cost_allocations',
          where: 'invoice_id = ?', whereArgs: ['INV-REV-001']);
      expect(allocations.length, 1);

      // Reverse the COGS allocation
      await _reverseCOGSAllocations('INV-REV-001');

      // Verify layer is restored
      layer = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-REV-001']);
      expect((layer.first['quantity_remaining'] as num).toDouble(), closeTo(100.0, 0.01),
          reason: 'After reversal, quantity_remaining should be restored to 100');
      expect(layer.first['is_fully_consumed'], 0,
          reason: 'After reversal, is_fully_consumed should be 0');

      // Verify allocations are deleted
      allocations = await db.query('movement_cost_allocations',
          where: 'invoice_id = ?', whereArgs: ['INV-REV-001']);
      expect(allocations.length, 0,
          reason: 'After reversal, allocations should be deleted');
    });

    test('Reversal of fully consumed layer restores it / عكس طبقة مستهلكة بالكامل يعيدها', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 50.0,
        averageCost: 10.0,
      );

      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 50.0,
        quantityRemaining: 50.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-REV-002',
      );

      // Consume all 50 units
      await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 50.0,
        invoiceId: 'INV-REV-002',
      );

      // Verify layer is fully consumed
      var layer = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-REV-002']);
      expect(layer.first['is_fully_consumed'], 1,
          reason: 'Layer should be fully consumed');

      // Reverse
      await _reverseCOGSAllocations('INV-REV-002');

      // Verify layer is restored
      layer = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-REV-002']);
      expect((layer.first['quantity_remaining'] as num).toDouble(), closeTo(50.0, 0.01),
          reason: 'After reversal, quantity should be restored');
      expect(layer.first['is_fully_consumed'], 0,
          reason: 'After reversal, is_fully_consumed should be reset to 0');
    });

    test('Multi-layer reversal restores all layers / عكس متعدد الطبقات يستعيد الكل', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 200.0,
        averageCost: 12.0,
      );

      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
        referenceType: 'purchase',
        referenceId: 'PO-MREV-001',
      );
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 15.0,
        referenceType: 'purchase',
        referenceId: 'PO-MREV-002',
      );

      // Consume 120 units: 100 from L1 + 20 from L2
      await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 120.0,
        invoiceId: 'INV-MREV-001',
      );

      // Verify Layer1 fully consumed, Layer2 partially
      var l1 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-MREV-001']);
      var l2 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-MREV-002']);
      expect(l1.first['is_fully_consumed'], 1);
      expect((l2.first['quantity_remaining'] as num).toDouble(), closeTo(80.0, 0.01));

      // Reverse
      await _reverseCOGSAllocations('INV-MREV-001');

      // Verify both layers are restored
      l1 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-MREV-001']);
      l2 = await db.query('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: ['PO-MREV-002']);

      expect((l1.first['quantity_remaining'] as num).toDouble(), closeTo(100.0, 0.01),
          reason: 'Layer1 restored to 100');
      expect(l1.first['is_fully_consumed'], 0);

      expect((l2.first['quantity_remaining'] as num).toDouble(), closeTo(100.0, 0.01),
          reason: 'Layer2 restored to 100');
      expect(l2.first['is_fully_consumed'], 0);
    });

    test('No cost layers: FIFO falls back to average_cost / بدون طبقات: FIFO يلجأ للمتوسط المرجح', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 100.0,
        averageCost: 12.0,
        costPrice: 10.0,
      );

      // No cost layers inserted
      final cogs = await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 50.0,
        invoiceId: 'INV-FALLBACK-001',
      );

      expect(cogs, 600.0,
          reason: 'FIFO fallback: 50 @ 12 = 600');
    });

    test('Selling more than available layers uses fallback for remainder / البيع أكثر من المتاح يستخدم الاحتياطي للباقي', () async {
      final productId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 150.0,
        averageCost: 12.0,
        costPrice: 10.0,
      );

      // Only 100 units in layers
      await _insertCostLayer(
        productId: productId,
        quantityOriginal: 100.0,
        quantityRemaining: 100.0,
        unitCost: 10.0,
      );

      // Sell 120: 100 from layer + 20 from average_cost fallback
      final cogs = await _calculateFIFOCOGS(
        productId: productId,
        baseQuantity: 120.0,
        invoiceId: 'INV-PARTIAL-001',
      );

      // COGS = (100 * 10) + (20 * 12) = 1000 + 240 = 1240
      expect(cogs, 1240.0,
          reason: 'FIFO partial: 100@10 + 20@12avg = 1240');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Test: FIFO vs LIFO produces different COGS in rising market
  // ══════════════════════════════════════════════════════════════

  group('FIFO vs LIFO comparison — مقارنة المتقدم والمتأخر أولاً', () {
    test('In rising prices: FIFO COGS < LIFO COGS / أسعار متصاعدة: تكلفة FIFO أقل من LIFO', () async {
      // FIFO product
      final fifoProductId = await _insertProduct(
        costingMethod: 'fifo',
        currentStock: 200.0,
        averageCost: 12.5,
      );
      await _insertCostLayer(productId: fifoProductId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 10.0);
      await _insertCostLayer(productId: fifoProductId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 15.0);

      // LIFO product (same cost layers)
      final lifoProductId = await _insertProduct(
        costingMethod: 'lifo',
        currentStock: 200.0,
        averageCost: 12.5,
      );
      await _insertCostLayer(productId: lifoProductId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 10.0);
      await _insertCostLayer(productId: lifoProductId, quantityOriginal: 100.0, quantityRemaining: 100.0, unitCost: 15.0);

      final fifoCogs = await _calculateFIFOCOGS(
        productId: fifoProductId,
        baseQuantity: 100.0,
        invoiceId: 'INV-COMP-FIFO',
      );

      final lifoCogs = await _calculateLIFOCOGS(
        productId: lifoProductId,
        baseQuantity: 100.0,
        invoiceId: 'INV-COMP-LIFO',
      );

      // FIFO: 100 @ 10 = 1000
      // LIFO: 100 @ 15 = 1500
      expect(fifoCogs, 1000.0);
      expect(lifoCogs, 1500.0);
      expect(fifoCogs, lessThan(lifoCogs),
          reason: 'In rising prices, FIFO COGS should be less than LIFO COGS');
    });
  });
}
