import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/datasources/services/costing_engine_service.dart';
import 'package:firstpro/data/datasources/services/journal_service.dart';
import 'package:firstpro/data/models/production_consumption_model.dart';
import 'package:firstpro/data/models/production_order_model.dart';
import 'package:firstpro/data/models/production_output_model.dart';

/// Posts recipe-based production as one auditable stock and journal operation.
class ProductionService {
  final DatabaseHelper _dbHelper;
  late final CostingEngineService _costing =
      CostingEngineService(_dbHelper);
  late final JournalService _journal = JournalService(_dbHelper);
  late final BaseCurrencyService _baseCurrency =
      BaseCurrencyService(_dbHelper);

  ProductionService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  Future<void> createDraft({required ProductionOrder order}) async {
    _validateOrder(order);
    if (order.status != 'draft' || order.isPosted || order.postedJournalId != null) {
      throw StateError('A production order must start as an unposted draft.');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'production_orders',
        columns: ['id'],
        where: 'id = ? OR order_number = ?',
        whereArgs: [order.id, order.orderNumber],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('Production order already exists: ${order.id}');
      }

      final recipeRows = await txn.query(
        'recipes',
        where: 'id = ? AND output_product_id = ? AND is_active = 1',
        whereArgs: [order.recipeId, order.outputProductId],
        limit: 1,
      );
      if (recipeRows.isEmpty) {
        throw StateError('Active recipe was not found for production order.');
      }
      final lines = await txn.query(
        'recipe_lines',
        where: 'recipe_id = ?',
        whereArgs: [order.recipeId],
        limit: 1,
      );
      if (lines.isEmpty) {
        throw StateError('A production recipe must contain at least one component.');
      }

      await txn.insert('production_orders', order.toMap());
      await _insertStatusHistory(
        txn,
        orderId: order.id,
        fromStatus: null,
        toStatus: 'draft',
        note: order.notes,
        createdAt: order.createdAt.toIso8601String(),
      );
    });
  }

  Future<ProductionOrder> getById(String orderId) async {
    final rows = await (await _db).query(
      'production_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Production order not found: $orderId');
    return ProductionOrder.fromMap(rows.single);
  }

  /// Posts raw material consumption and finished output atomically.
  Future<void> postProduction({required String orderId}) async {
    final db = await _db;
    final initialRows = await db.query(
      'production_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (initialRows.isEmpty) {
      throw StateError('Production order not found: $orderId');
    }
    final date = initialRows.single['created_at'] as String?;
    if (date == null || date.trim().isEmpty) {
      throw StateError('A production creation date is required before posting.');
    }
    await _journal.checkFiscalPeriodOpen(date);

    // Resolve the base offset before opening SQLite's transaction. Some
    // currency implementations query the database and can deadlock in txn.
    final baseCurrencyOffset = await _baseCurrency.getOffsetForCurrency('YER');
    final defaultInventoryAccountId = await _findAccountId(
      accountCode: (1300 + baseCurrencyOffset).toString(),
      currency: 'YER',
    );

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        'production_orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) throw StateError('Production order not found: $orderId');
      final order = orderRows.single;
      final status = order['status'] as String? ?? 'draft';
      if (status != 'draft' && status != 'in_progress') {
        throw StateError('Production order is not ready for posting: $status');
      }
      if ((order['is_posted'] as num?)?.toInt() == 1 ||
          order['posted_journal_id'] != null) {
        throw StateError('Production order is already posted: $orderId');
      }

      final recipeRows = await txn.query(
        'recipes',
        where: 'id = ? AND output_product_id = ? AND is_active = 1',
        whereArgs: [order['recipe_id'], order['output_product_id']],
        limit: 1,
      );
      if (recipeRows.isEmpty) throw StateError('Active production recipe was not found.');
      final recipe = recipeRows.single;
      final outputQuantity = (recipe['output_quantity'] as num).toDouble();
      final plannedQuantity = (order['planned_quantity'] as num).toDouble();
      if (plannedQuantity <= 0 || outputQuantity <= 0) {
        throw StateError('Production quantity must be positive.');
      }

      final componentRows = await txn.query(
        'recipe_lines',
        where: 'recipe_id = ?',
        whereArgs: [order['recipe_id']],
        orderBy: 'id ASC',
      );
      if (componentRows.isEmpty) {
        throw StateError('A production recipe must contain at least one component.');
      }

      final outputRows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [order['output_product_id']],
        limit: 1,
      );
      if (outputRows.isEmpty) {
        throw StateError('Finished product was not found: ${order['output_product_id']}');
      }
      final outputProduct = outputRows.single;
      final outputInventoryAccountId =
          (outputProduct['inventory_account_id'] as num?)?.toInt() ??
              defaultInventoryAccountId;
      if (outputInventoryAccountId == null) {
        throw StateError('Finished product inventory account is missing.');
      }

      final ratio = plannedQuantity / outputQuantity;
      final now = DateTime.now().toIso8601String();
      final journalId = generateUniqueJournalId();
      final creditsByAccount = <int, double>{};
      double totalCost = 0.0;

      for (final component in componentRows) {
        final productId = (component['component_product_id'] as num).toInt();
        final quantity = (component['quantity'] as num).toDouble() * ratio;
        if (quantity <= 0) throw StateError('Recipe component quantity must be positive.');

        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) throw StateError('Component product was not found: $productId');
        final product = productRows.single;
        if ((product['track_stock'] as num?)?.toInt() != 1 ||
            (product['product_kind'] as String? ?? 'stock') == 'service') {
          throw StateError('Component product is not stock-tracked: $productId');
        }
        final currentStock = (product['current_stock'] as num?)?.toDouble() ?? 0;
        final allowNegative = (product['allow_negative'] as num?)?.toInt() == 1;
        if (!allowNegative && quantity > currentStock + 0.005) {
          throw StateError(
            'Insufficient stock for component $productId: available $currentStock, required $quantity',
          );
        }

        final componentCost = await _costing.calculateCOGSInTransaction(
          txn,
          productId: productId,
          baseQuantity: quantity,
          invoiceId: orderId,
          codeOffset: baseCurrencyOffset,
        );
        if (componentCost < 0) throw StateError('Production component cost cannot be negative.');
        final inventoryAccountId =
            (product['inventory_account_id'] as num?)?.toInt() ??
                defaultInventoryAccountId;
        if (inventoryAccountId == null) {
          throw StateError('Component inventory account is missing: $productId');
        }
        creditsByAccount[inventoryAccountId] =
            (creditsByAccount[inventoryAccountId] ?? 0) + componentCost;
        totalCost += componentCost;

        await txn.rawUpdate(
          'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
          [quantity, now, productId],
        );
        final unitCost = quantity > 0 ? componentCost / quantity : 0.0;
        await txn.insert(
          'stock_movements',
          {
            'product_id': productId,
            'movement_type': 'production_consumption',
            'quantity': -quantity,
            'reference_type': 'production',
            'reference_id': orderId,
            'unit_cost': MoneyHelper.toCents(unitCost),
            'created_at': now,
          },
        );
        await txn.insert(
          'production_consumptions',
          ProductionConsumption(
            productionOrderId: orderId,
            componentProductId: productId,
            quantity: quantity,
            unitCost: MoneyHelper.toCents(unitCost),
            totalCost: MoneyHelper.toCents(componentCost),
            createdAt: DateTime.parse(now),
          ).toMap()..remove('id'),
        );
      }

      final outputCostMinor = MoneyHelper.toCents(totalCost);
      final outputCost = MoneyHelper.fromCents(outputCostMinor);
      final oldOutputStock = (outputProduct['current_stock'] as num?)?.toDouble() ?? 0;
      final oldOutputAverage = MoneyHelper.readMoney(outputProduct['average_cost']);
      final newOutputStock = oldOutputStock + plannedQuantity;
      final newOutputAverage = newOutputStock > 0
          ? ((oldOutputStock * oldOutputAverage) + outputCost) / newOutputStock
          : 0.0;
      await txn.rawUpdate(
        'UPDATE products SET current_stock = current_stock + ?, average_cost = ?, cost_price = ?, updated_at = ? WHERE id = ?',
        [plannedQuantity, MoneyHelper.toCents(newOutputAverage), MoneyHelper.toCents(newOutputAverage), now, order['output_product_id']],
      );
      await txn.insert(
        'stock_movements',
        {
          'product_id': order['output_product_id'],
          'movement_type': 'production_output',
          'quantity': plannedQuantity,
          'reference_type': 'production',
          'reference_id': orderId,
          'unit_cost': plannedQuantity > 0
              ? MoneyHelper.toCents(outputCost / plannedQuantity)
              : 0,
          'created_at': now,
        },
      );
      await txn.insert(
        'production_outputs',
        ProductionOutput(
          productionOrderId: orderId,
          productId: (order['output_product_id'] as num).toInt(),
          quantity: plannedQuantity,
          totalCost: outputCostMinor,
          createdAt: DateTime.parse(now),
        ).toMap()..remove('id'),
      );

      await txn.insert('transactions', {
        'account_id': outputInventoryAccountId,
        'journal_id': journalId,
        'debit': outputCostMinor,
        'credit': 0,
        'description': 'Finished production $orderId',
        'date': date,
        'created_at': now,
        'reference_type': 'production',
        'reference_id': orderId,
        'currency_code': 'YER',
        'exchange_rate': 1.0,
        'amount_base': outputCostMinor,
      });
      await _journal.updateAccountBalanceWithJournal(
        txn,
        outputInventoryAccountId,
        outputCost,
        0,
        now,
      );
      for (final entry in creditsByAccount.entries) {
        final amountMinor = MoneyHelper.toCents(entry.value);
        if (amountMinor <= 0) continue;
        final amount = MoneyHelper.fromCents(amountMinor);
        await txn.insert('transactions', {
          'account_id': entry.key,
          'journal_id': journalId,
          'debit': 0,
          'credit': amountMinor,
          'description': 'Raw material consumption $orderId',
          'date': date,
          'created_at': now,
          'reference_type': 'production',
          'reference_id': orderId,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': amountMinor,
        });
        await _journal.updateAccountBalanceWithJournal(
          txn,
          entry.key,
          0,
          amount,
          now,
        );
      }
      await _journal.validateJournalBalanceInTransaction(txn, journalId);
      await _journal.validateJournalBaseBalanceInTransaction(txn, journalId);

      await txn.update(
        'production_orders',
        {
          'actual_quantity': plannedQuantity,
          'total_cost': outputCostMinor,
          'waste_cost': 0,
          'status': 'completed',
          'is_posted': 1,
          'posted_journal_id': journalId,
          'updated_at': now,
        },
        where: 'id = ? AND is_posted = 0 AND posted_journal_id IS NULL',
        whereArgs: [orderId],
      );
      await _insertStatusHistory(
        txn,
        orderId: orderId,
        fromStatus: status,
        toStatus: 'completed',
        note: 'Production posted atomically.',
        createdAt: now,
      );
    });
  }

  /// Cancels a posted order by reversing stock and adding a new journal.
  Future<void> cancelProduction({
    required String orderId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('Cancellation reason is required.');
    final db = await _db;
    final rows = await db.query(
      'production_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Production order not found: $orderId');
    await _journal.checkFiscalPeriodOpen(DateTime.now().toIso8601String());

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        'production_orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      final order = orderRows.single;
      if (order['status'] != 'completed' ||
          (order['is_posted'] as num?)?.toInt() != 1) {
        throw StateError('Only a posted completed production order can be cancelled.');
      }
      final consumptions = await txn.query(
        'production_consumptions',
        where: 'production_order_id = ?',
        whereArgs: [orderId],
      );
      final outputs = await txn.query(
        'production_outputs',
        where: 'production_order_id = ?',
        whereArgs: [orderId],
      );
      if (consumptions.isEmpty || outputs.isEmpty) {
        throw StateError('Posted production has no auditable stock records.');
      }
      final now = DateTime.now().toIso8601String();
      final reversalJournalId = generateUniqueJournalId();
      final totalCostMinor = (order['total_cost'] as num).toInt();
      final totalCost = MoneyHelper.fromCents(totalCostMinor);

      for (final row in consumptions) {
        final quantity = (row['quantity'] as num).toDouble();
        final productId = (row['component_product_id'] as num).toInt();
        await txn.rawUpdate(
          'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
          [quantity, now, productId],
        );
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'production_reversal_consumption',
          'quantity': quantity,
          'reference_type': 'production_reversal',
          'reference_id': orderId,
          'unit_cost': row['unit_cost'],
          'created_at': now,
        });
      }
      for (final row in outputs) {
        final quantity = (row['quantity'] as num).toDouble();
        final productId = (row['product_id'] as num).toInt();
        final productRows = await txn.query(
          'products',
          columns: ['current_stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) throw StateError('Output product was not found: $productId');
        final currentStock = (productRows.single['current_stock'] as num).toDouble();
        if (currentStock + 0.005 < quantity) {
          throw StateError('Cannot cancel production: finished stock was already consumed.');
        }
        await txn.rawUpdate(
          'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
          [quantity, now, productId],
        );
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'production_reversal_output',
          'quantity': -quantity,
          'reference_type': 'production_reversal',
          'reference_id': orderId,
          'unit_cost': row['total_cost'],
          'created_at': now,
        });
      }

      await _costing.reverseCOGSAllocationsInTransaction(
        txn,
        invoiceId: orderId,
      );
      final originalTransactions = await txn.query(
        'transactions',
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['production', orderId],
        orderBy: 'id ASC',
      );
      if (originalTransactions.isEmpty) {
        throw StateError('Original production journal was not found.');
      }
      for (final original in originalTransactions) {
        final debit = (original['debit'] as num).toInt();
        final credit = (original['credit'] as num).toInt();
        await txn.insert('transactions', {
          'account_id': original['account_id'],
          'journal_id': reversalJournalId,
          'debit': credit,
          'credit': debit,
          'description': 'Reversal of production $orderId: $reason',
          'date': now,
          'created_at': now,
          'reference_type': 'production_reversal',
          'reference_id': orderId,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': (original['amount_base'] as num?)?.toInt() ?? debit + credit,
        });
        await _journal.updateAccountBalanceWithJournal(
          txn,
          (original['account_id'] as num).toInt(),
          MoneyHelper.fromCents(credit),
          MoneyHelper.fromCents(debit),
          now,
        );
      }
      await _journal.validateJournalBalanceInTransaction(txn, reversalJournalId);
      await _journal.validateJournalBaseBalanceInTransaction(txn, reversalJournalId);
      await txn.update(
        'production_orders',
        {'status': 'cancelled', 'updated_at': now},
        where: 'id = ? AND status = ? AND is_posted = 1',
        whereArgs: [orderId, 'completed'],
      );
      await _insertStatusHistory(
        txn,
        orderId: orderId,
        fromStatus: 'completed',
        toStatus: 'cancelled',
        note: reason,
        createdAt: now,
      );

      // Keep the original journal and rows intact; only append the reversal.
      if (totalCostMinor < 0 || totalCost < 0) {
        throw StateError('Production cost cannot be negative.');
      }
    });
  }

  void _validateOrder(ProductionOrder order) {
    if (order.id.trim().isEmpty || order.orderNumber.trim().isEmpty) {
      throw ArgumentError('Production order id and number are required.');
    }
    if (order.plannedQuantity <= 0) {
      throw ArgumentError.value(order.plannedQuantity, 'plannedQuantity');
    }
    if (order.currencyCode.trim().isEmpty || order.exchangeRate <= 0) {
      throw ArgumentError('Production currency and exchange rate are invalid.');
    }
  }

  Future<int?> _findAccountId({
    required String accountCode,
    required String currency,
  }) async {
    final rows = await (await _db).query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ? AND is_active = 1',
      whereArgs: [accountCode, currency],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.single['id'] as num).toInt();
  }

  Future<void> _insertStatusHistory(
    Transaction txn, {
    required String orderId,
    required String? fromStatus,
    required String toStatus,
    required String? note,
    required String createdAt,
  }) async {
    await txn.insert('production_status_history', {
      'production_order_id': orderId,
      'from_status': fromStatus,
      'to_status': toStatus,
      'note': note,
      'created_at': createdAt,
    });
  }
}
