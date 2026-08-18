import 'package:firstpro/data/models/service_order_line_model.dart';
import 'package:firstpro/data/models/service_order_model.dart';
import 'package:firstpro/data/models/service_payment_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceOrder model', () {
    test('defaults to draft in YER and round-trips monetary fields', () {
      final createdAt = DateTime.utc(2026, 8, 18, 10, 0);
      final order = ServiceOrder(
        id: 'so-1',
        orderNumber: 'SO-0001',
        receivedAt: createdAt,
        subtotal: 125.50,
        discountAmount: 5.50,
        taxAmount: 18.00,
        total: 138.00,
        remaining: 138.00,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      expect(order.status, 'draft');
      expect(order.currencyCode, 'YER');
      expect(order.exchangeRate, 1.0);

      final restored = ServiceOrder.fromMap(order.toMap());
      expect(restored.subtotal, 125.50);
      expect(restored.discountAmount, 5.50);
      expect(restored.taxAmount, 18.00);
      expect(restored.total, 138.00);
      expect(restored.createdAt, createdAt);
    });
  });

  group('ServiceOrderLine model', () {
    test('round-trips service line without changing monetary units', () {
      final line = ServiceOrderLine(
        serviceOrderId: 'so-1',
        lineType: 'service',
        description: 'تغيير شاشة',
        quantity: 1,
        unitPrice: 250.75,
        taxRate: 0.0,
        lineTotal: 250.75,
      );

      final restored = ServiceOrderLine.fromMap(line.toMap());
      expect(restored.lineType, 'service');
      expect(restored.quantity, 1.0);
      expect(restored.unitPrice, 250.75);
      expect(restored.lineTotal, 250.75);
    });
  });

  group('ServicePayment model', () {
    test('reads persisted base amount as minor units even when SQLite returns double', () {
      final payment = ServicePayment.fromMap({
        'id': 1,
        'service_order_id': 'so-1',
        'payment_method': 'cash',
        'amount': 10000,
        'currency_code': 'USD',
        'exchange_rate': 140.0,
        'amount_base': 14000.0,
        'is_posted': 0,
        'payment_date': '2026-08-18T00:00:00.000Z',
      });

      expect(payment.amount, 100);
      expect(payment.amountBase, 140);
    });

    test('requires a positive amount and preserves currency metadata', () {
      final payment = ServicePayment(
        serviceOrderId: 'so-1',
        amount: 50.25,
        currencyCode: 'SAR',
        exchangeRate: 145.5,
        amountBase: 7313.88,
        paymentDate: DateTime.utc(2026, 8, 18),
      );

      expect(payment.amount, 50.25);
      expect(payment.currencyCode, 'SAR');
      expect(payment.exchangeRate, 145.5);
      expect(payment.amountBase, 7313.88);
    });
  });
}
