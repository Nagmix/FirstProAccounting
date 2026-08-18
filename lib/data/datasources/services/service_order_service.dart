import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/finance/currency_engine.dart';
import 'package:firstpro/core/service/service_order_line_policy.dart';
import 'package:firstpro/core/service/service_order_status_policy.dart';
import 'package:firstpro/core/service/service_order_totals.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/data/models/service_order_device_model.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';
import 'package:firstpro/data/models/service_payment_model.dart';
import 'package:firstpro/data/models/service_warranty_model.dart';

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

  Future<void> addDevice({required ServiceOrderDevice device}) async {
    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, device.serviceOrderId);
      _ensureEditable(order);
      if (device.deviceType.trim().isEmpty) {
        throw ArgumentError('Device type is required.');
      }
      final values = device.toMap()
        ..remove('id')
        ..['created_at'] =
            device.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String();
      await txn.insert('service_order_devices', values);
    });
  }

  Future<List<ServiceOrderDevice>> getDevices(String orderId) async {
    final db = await _db;
    final rows = await db.query(
      'service_order_devices',
      where: 'service_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return rows.map(ServiceOrderDevice.fromMap).toList();
  }

  Future<void> addWarranty({required ServiceWarranty warranty}) async {
    if (warranty.endsAt.isBefore(warranty.startsAt)) {
      throw ArgumentError('Warranty end date cannot precede start date.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, warranty.serviceOrderId);
      _ensureEditable(order);
      if (warranty.serviceOrderLineId != null) {
        final lines = await txn.query(
          'service_order_lines',
          columns: ['id'],
          where: 'id = ? AND service_order_id = ?',
          whereArgs: [warranty.serviceOrderLineId, warranty.serviceOrderId],
          limit: 1,
        );
        if (lines.isEmpty) {
          throw StateError('Warranty line does not belong to the service order.');
        }
      }
      final now = DateTime.now().toIso8601String();
      final values = warranty.toMap()
        ..remove('id')
        ..['created_at'] = warranty.createdAt?.toIso8601String() ?? now
        ..['updated_at'] = warranty.updatedAt?.toIso8601String() ?? now;
      await txn.insert('service_warranties', values);
    });
  }

  Future<List<ServiceWarranty>> getWarranties(String orderId) async {
    final db = await _db;
    final rows = await db.query(
      'service_warranties',
      where: 'service_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return rows.map(ServiceWarranty.fromMap).toList();
  }

  Future<void> createPayment({required ServicePayment payment}) async {
    if (payment.amount <= 0) {
      throw ArgumentError.value(payment.amount, 'amount', 'must be positive');
    }
    if (payment.currencyCode.trim().isEmpty || payment.exchangeRate <= 0) {
      throw ArgumentError('Payment currency and positive exchange rate are required.');
    }
    if (payment.isPosted || payment.journalId != null) {
      throw StateError('A payment with an existing journal cannot be created as a draft.');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final order = await _requireOrder(txn, payment.serviceOrderId);
      _ensureEditable(order);
      if (payment.currencyCode != order['currency_code']) {
        throw ArgumentError('Payment currency must match the service order currency.');
      }

      final amountMinorUnits = MoneyHelper.toCents(payment.amount);
      final totalMinorUnits = MoneyHelper.toCents(
        MoneyHelper.readMoney(order['total']),
      );
      final paidMinorUnits = MoneyHelper.toCents(
        MoneyHelper.readMoney(order['paid_amount']),
      );
      if (paidMinorUnits + amountMinorUnits > totalMinorUnits) {
        throw ArgumentError('Payment exceeds the service order remaining amount.');
      }

      final amountBaseMinorUnits = const CurrencyEngine().convertMinorUnits(
        amountMinorUnits: amountMinorUnits,
        exchangeRateMicros: CurrencyEngine.rateToMicros(payment.exchangeRate),
      );
      final values = MoneyHelper.toCentsMap(
        payment.toMap()
          ..remove('id')
          ..['created_at'] =
              payment.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        const ['amount'],
      );
      values['amount_base'] = amountBaseMinorUnits;
      await txn.insert('service_payments', values);

      final newPaidMinorUnits = paidMinorUnits + amountMinorUnits;
      await txn.update(
        'service_orders',
        MoneyHelper.toCentsMap(
          {
            'paid_amount': newPaidMinorUnits / MoneyHelper.scaleFactor,
            'remaining':
                (totalMinorUnits - newPaidMinorUnits) / MoneyHelper.scaleFactor,
            'updated_at': DateTime.now().toIso8601String(),
          },
          const ['paid_amount', 'remaining'],
        ),
        where: 'id = ?',
        whereArgs: [payment.serviceOrderId],
      );
    });
  }

  /// Post a service-order payment as a balanced receipt journal.
  ///
  /// The debit goes to the cash-box linked account and the credit goes to
  /// the customer receivable account. The payment row is marked posted only
  /// after both journal rows, account balances, and exact currency checks
  /// succeed in the same SQLite transaction.
  Future<void> postPayment({required int paymentId}) async {
    final db = await _db;
    final initialRows = await db.query(
      'service_payments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (initialRows.isEmpty) {
      throw StateError('Service payment not found: $paymentId');
    }
    final paymentDate = initialRows.single['payment_date'] as String?;
    if (paymentDate == null || paymentDate.trim().isEmpty) {
      throw StateError('A payment date is required before posting.');
    }
    await _dbHelper.journal.checkFiscalPeriodOpen(paymentDate);
    final paymentCurrency = initialRows.single['currency_code'] as String? ?? 'YER';
    final currencyOffset =
        await _dbHelper.baseCurrency.getOffsetForCurrency(paymentCurrency);

    await db.transaction((txn) async {
      final paymentRows = await txn.query(
        'service_payments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (paymentRows.isEmpty) {
        throw StateError('Service payment not found: $paymentId');
      }
      final payment = paymentRows.single;
      if ((payment['is_posted'] as num?)?.toInt() == 1 ||
          payment['journal_id'] != null) {
        throw StateError('Service payment is already posted: $paymentId');
      }

      final orderRows = await txn.query(
        'service_orders',
        columns: ['id', 'customer_id', 'currency_code'],
        where: 'id = ?',
        whereArgs: [payment['service_order_id']],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        throw StateError('Service order for payment was not found.');
      }
      final order = orderRows.single;
      final customerId = order['customer_id'] as int?;
      if (customerId == null) {
        throw StateError('A customer is required before posting a payment.');
      }
      final customerRows = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customerRows.isEmpty) {
        throw StateError('Customer was not found: $customerId');
      }

      final currency = payment['currency_code'] as String? ?? 'YER';
      if (currency != paymentCurrency) {
        throw StateError('Payment currency changed while posting.');
      }
      if (currency != order['currency_code']) {
        throw StateError('Payment currency does not match the service order.');
      }
      final cashBoxId = payment['cash_box_id'] as int?;
      if (cashBoxId == null) {
        throw StateError('A cash box is required before posting a payment.');
      }
      final cashBoxRows = await txn.query(
        'cash_boxes',
        columns: ['linked_account_id', 'currency'],
        where: 'id = ?',
        whereArgs: [cashBoxId],
        limit: 1,
      );
      if (cashBoxRows.isEmpty) {
        throw StateError('Cash box not found: $cashBoxId');
      }
      final cashAccountId = cashBoxRows.single['linked_account_id'] as int?;
      if (cashAccountId == null) {
        throw StateError('Cash box has no linked ledger account.');
      }
      final cashCurrency = cashBoxRows.single['currency'] as String?;
      if (cashCurrency != null && cashCurrency != currency) {
        throw StateError('Cash box currency does not match the payment.');
      }

      final receivableRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ? AND is_active = 1',
        whereArgs: [(1200 + currencyOffset).toString(), currency],
        limit: 1,
      );
      if (receivableRows.isEmpty) {
        throw StateError(
          'Customer receivable account was not found for currency $currency.',
        );
      }
      final receivableAccountId = receivableRows.single['id'] as int;
      final journalId = generateUniqueJournalId();
      final now = DateTime.now().toIso8601String();
      final amountMinorUnits = (payment['amount'] as num).round();
      final amount = MoneyHelper.fromCents(amountMinorUnits);
      final amountBaseMinorUnits = (payment['amount_base'] as num).round();
      final exchangeRate = (payment['exchange_rate'] as num).toDouble();
      final referenceId = paymentId.toString();

      await txn.insert('transactions', {
        'account_id': cashAccountId,
        'journal_id': journalId,
        'debit': amountMinorUnits,
        'credit': 0,
        'description': 'Service payment $referenceId',
        'date': paymentDate,
        'created_at': now,
        'reference_type': 'service_payment',
        'reference_id': referenceId,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBaseMinorUnits,
      });
      await txn.insert('transactions', {
        'account_id': receivableAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': amountMinorUnits,
        'description': 'Service payment $referenceId',
        'date': paymentDate,
        'created_at': now,
        'reference_type': 'service_payment',
        'reference_id': referenceId,
        'currency_code': currency,
        'exchange_rate': exchangeRate,
        'amount_base': amountBaseMinorUnits,
      });

      await _dbHelper.journal.updateAccountBalanceWithJournal(
        txn,
        cashAccountId,
        amount,
        0.0,
        now,
      );
      await _dbHelper.journal.updateAccountBalanceWithJournal(
        txn,
        receivableAccountId,
        0.0,
        amount,
        now,
      );
      await _dbHelper.journal.validateJournalBalanceInTransaction(
        txn,
        journalId,
      );
      await _dbHelper.journal.validateJournalBaseBalanceInTransaction(
        txn,
        journalId,
      );

      await txn.update(
        'service_payments',
        {'is_posted': 1, 'journal_id': journalId, 'created_at': payment['created_at']},
        where: 'id = ? AND is_posted = 0 AND journal_id IS NULL',
        whereArgs: [paymentId],
      );
    });
  }

  Future<List<ServicePayment>> getPayments(String orderId) async {
    final db = await _db;
    final rows = await db.query(
      'service_payments',
      where: 'service_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return rows.map(ServicePayment.fromMap).toList();
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
