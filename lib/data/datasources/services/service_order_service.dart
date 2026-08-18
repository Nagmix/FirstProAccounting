import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/service/service_order_line_policy.dart';
import 'package:firstpro/core/service/service_order_status_policy.dart';
import 'package:firstpro/core/service/service_order_totals.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';

class ServiceOrderService {
  ServiceOrderService(this._dbHelper);

  final DatabaseHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  Future<String> createDraft({required ServiceOrder order}) async {
    _validateOrder(order);
    if (order.status != 'draft') {
      throw StateError('A new service order must start in draft status.');
    }
    if (order.isPosted) {
      throw StateError('A posted service order cannot be created as a draft.');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final values = MoneyHelper.toCentsMap(
        order.toMap(),
        const [
          'subtotal',
          'discount_amount',
          'tax_amount',
          'transport_charges',
          'total',
          'paid_amount',
          'remaining',
        ],
      );
      await txn.insert('service_orders', values);
    });
    return order.id;
  }

  Future<void> addLine({
    required String orderId,
    required ServiceOrderLine line,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, orderId);
      _ensureEditable(order);
      await _validateLine(txn, order, line, orderId);

      final values = MoneyHelper.toCentsMap(
        line.toMap()
          ..remove('id')
          ..['created_at'] =
              line.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        const ['unit_price', 'unit_cost', 'tax_amount', 'line_total'],
      );
      await txn.insert('service_order_lines', values);
      await _recalculateOrder(txn, orderId);
    });
  }

  Future<void> updateLine({required ServiceOrderLine line}) async {
    final lineId = line.id;
    if (lineId == null) {
      throw ArgumentError('A line id is required for update.');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, line.serviceOrderId);
      _ensureEditable(order);
      await _validateLine(txn, order, line, line.serviceOrderId);

      final values = MoneyHelper.toCentsMap(
        line.toMap()
          ..remove('id')
          ..['created_at'] =
              line.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        const ['unit_price', 'unit_cost', 'tax_amount', 'line_total'],
      );
      await txn.update(
        'service_order_lines',
        values,
        where: 'id = ? AND service_order_id = ?',
        whereArgs: [lineId, line.serviceOrderId],
      );
      await _recalculateOrder(txn, line.serviceOrderId);
    });
  }

  Future<void> removeLine({
    required String orderId,
    required int lineId,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, orderId);
      _ensureEditable(order);
      await txn.delete(
        'service_order_lines',
        where: 'id = ? AND service_order_id = ?',
        whereArgs: [lineId, orderId],
      );
      await _recalculateOrder(txn, orderId);
    });
  }

  Future<void> transitionStatus({
    required String orderId,
    required String toStatus,
    String? note,
    int? changedBy,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, orderId);
      _ensureEditable(order);
      final fromStatus = order['status'] as String? ?? 'draft';
      if (!ServiceOrderStatusPolicy.canTransition(fromStatus, toStatus)) {
        throw StateError('Invalid service order transition: $fromStatus -> $toStatus');
      }

      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'status': toStatus,
        'updated_at': now,
      };
      if (toStatus == 'in_progress') updates['completed_at'] = null;
      if (toStatus == 'ready') updates['completed_at'] = now;
      if (toStatus == 'delivered') updates['delivered_at'] = now;

      await txn.update(
        'service_orders',
        updates,
        where: 'id = ?',
        whereArgs: [orderId],
      );
      await txn.insert('service_status_history', {
        'service_order_id': orderId,
        'from_status': fromStatus,
        'to_status': toStatus,
        'note': note,
        'changed_by': changedBy,
        'created_at': now,
      });
    });
  }

  Future<ServiceOrder?> getById(String orderId) async {
    final db = await _db;
    final rows = await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    return rows.isEmpty ? null : ServiceOrder.fromMap(rows.first);
  }

  Future<List<Map<String, dynamic>>> getStatusHistory(String orderId) async {
    final db = await _db;
    return db.query(
      'service_status_history',
      where: 'service_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
  }

  Future<Map<String, dynamic>> _requireOrder(
    DatabaseExecutor db,
    String orderId,
  ) async {
    final rows = await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Service order not found: $orderId');
    }
    return rows.single;
  }

  Future<void> _validateLine(
    DatabaseExecutor db,
    Map<String, dynamic> order,
    ServiceOrderLine line,
    String orderId,
  ) async {
    if (line.serviceOrderId != orderId) {
      throw ArgumentError('Line does not belong to the service order.');
    }
    if (line.quantity <= 0) {
      throw ArgumentError.value(line.quantity, 'quantity', 'must be positive');
    }
    if (line.currencyCode.trim().isEmpty ||
        line.currencyCode != order['currency_code']) {
      throw ArgumentError('Line currency must match the service order currency.');
    }
    if (line.lineType != 'service' && line.lineType != 'part') {
      throw ArgumentError.value(line.lineType, 'lineType', 'is not supported');
    }

    if (line.lineType == 'service') {
      if (line.productId == null) return;
      final product = await _requireProduct(db, line.productId!);
      final kind = ProductKind.fromValue(product['product_kind'] as String?);
      if (kind.createsStockMovement) {
        throw StateError('A stock product cannot be added as a service line.');
      }
      return;
    }

    final productId = line.productId;
    if (productId == null) {
      throw ArgumentError('A part line requires a product.');
    }
    final product = await _requireProduct(db, productId);
    final kind = ProductKind.fromValue(product['product_kind'] as String?);
    final trackStock = (product['track_stock'] ?? 0) == 1;
    if (!ServiceOrderLinePolicy.canAffectInventory(
      lineType: line.lineType,
      productKind: kind,
      trackStock: trackStock,
    )) {
      throw StateError(
        'Only tracked stock or bundle products can be added as part lines.',
      );
    }
  }

  Future<Map<String, dynamic>> _requireProduct(
    DatabaseExecutor db,
    int productId,
  ) async {
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Product not found: $productId');
    }
    return rows.single;
  }

  Future<void> _recalculateOrder(
    DatabaseExecutor db,
    String orderId,
  ) async {
    final order = await _requireOrder(db, orderId);
    final rows = await db.query(
      'service_order_lines',
      where: 'service_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    final lines = rows.map(ServiceOrderLine.fromMap).toList();
    final result = ServiceOrderTotals.calculate(
      lines: lines,
      discountAmount: MoneyHelper.readMoney(order['discount_amount']),
      transportCharges: MoneyHelper.readMoney(order['transport_charges']),
    );
    final paidAmount = MoneyHelper.readMoney(order['paid_amount']);
    final values = MoneyHelper.toCentsMap(
      {
        'subtotal': result.subtotal,
        'tax_amount': result.taxAmount,
        'total': result.total,
        'remaining': result.total - paidAmount,
        'updated_at': DateTime.now().toIso8601String(),
      },
      const ['subtotal', 'tax_amount', 'total', 'remaining'],
    );
    await db.update(
      'service_orders',
      values,
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  void _validateOrder(ServiceOrder order) {
    if (order.id.trim().isEmpty) throw ArgumentError('Order id is required.');
    if (order.orderNumber.trim().isEmpty) {
      throw ArgumentError('Order number is required.');
    }
    if (order.currencyCode.trim().isEmpty) {
      throw ArgumentError('Currency code is required.');
    }
    if (order.exchangeRate <= 0) {
      throw ArgumentError.value(
        order.exchangeRate,
        'exchangeRate',
        'must be positive',
      );
    }
  }

  void _ensureEditable(Map<String, dynamic> order) {
    if ((order['is_posted'] ?? 0) == 1) {
      throw StateError('Posted service orders cannot be edited.');
    }
    final status = order['status'] as String? ?? 'draft';
    if (ServiceOrderStatusPolicy.isTerminal(status)) {
      throw StateError('Terminal service orders cannot be edited.');
    }
  }
}
