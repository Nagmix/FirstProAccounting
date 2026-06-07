import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/customer_model.dart';
import 'package:firstpro/data/models/supplier_model.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Customer & Supplier Model Unit Tests
/// Tests both models since they share similar structure:
/// - Balance type handling (credit/debit)
/// - toMap/fromMap serialization
/// - copyWith including nullable fields
void main() {
  group('Customer Model', () {
    group('construction', () {
      test('creates customer with required fields', () {
        final customer = Customer(name: 'أحمد محمد');
        expect(customer.name, equals('أحمد محمد'));
        expect(customer.balance, equals(0.0));
        expect(customer.balanceType, equals('credit'));
        expect(customer.currency, isNull); // Multi-currency
        expect(customer.debtCeiling, equals(0.0));
      });

      test('creates customer with all fields', () {
        final customer = Customer(
          id: 1, name: 'أحمد محمد', phone: '777123456',
          balance: 5000.0, balanceType: 'debit', currency: 'YER',
          debtCeiling: 10000.0,
        );
        expect(customer.id, equals(1));
        expect(customer.balance, equals(5000.0));
        expect(customer.balanceType, equals('debit'));
        expect(customer.currency, equals('YER'));
      });
    });

    group('serialization', () {
      test('toMap converts balance to cents', () {
        final customer = Customer(name: 'أحمد', balance: 150.75, debtCeiling: 5000.50);
        final map = customer.toMap();
        expect(map['balance'], equals(MoneyHelper.toCents(150.75)));
        expect(map['debt_ceiling'], equals(MoneyHelper.toCents(5000.50)));
      });

      test('fromMap reads cents correctly', () {
        final map = {
          'id': 1, 'name': 'أحمد', 'phone': null, 'address': null,
          'address2': null, 'email': null, 'contact_method': null,
          'notes': null, 'balance': 15075, 'balance_type': 'debit',
          'currency': 'YER', 'debt_ceiling': 500050,
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        };
        final customer = Customer.fromMap(map);
        expect(customer.balance, closeTo(150.75, 0.001));
        expect(customer.debtCeiling, closeTo(5000.50, 0.001));
        expect(customer.balanceType, equals('debit'));
      });

      test('fromMap handles legacy field names (notification_method, credit_limit)', () {
        final map = {
          'id': 1, 'name': 'أحمد', 'phone': null, 'address': null,
          'address2': null, 'email': null,
          'contact_method': null, 'notification_method': 'whatsapp',
          'notes': null, 'balance': 15075, 'balance_type': 'credit',
          'currency': 'YER', 'debt_ceiling': 500050, 'credit_limit': 10000,
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        };
        final customer = Customer.fromMap(map);
        // Should use contact_method, fallback to notification_method
        expect(customer.contactMethod, equals('whatsapp'));
      });

      test('round-trip preserves monetary values', () {
        final original = Customer(
          id: 1, name: 'أحمد', balance: 5000.75,
          debtCeiling: 10000.50, balanceType: 'debit',
          createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
        );
        final restored = Customer.fromMap(original.toMap());
        expect(restored.balance, closeTo(original.balance, 0.01));
        expect(restored.debtCeiling, closeTo(original.debtCeiling, 0.01));
        expect(restored.balanceType, equals(original.balanceType));
      });
    });

    group('copyWith', () {
      test('copies with changed fields', () {
        final original = Customer(id: 1, name: 'أحمد', balance: 5000.0);
        final modified = original.copyWith(balance: 6000.0);
        expect(modified.balance, equals(6000.0));
        expect(modified.name, equals('أحمد'));
      });

      test('copyWith handles nullable currency with sentinel', () {
        final original = Customer(id: 1, name: 'أحمد', currency: 'YER');
        // Not passing currency → should keep original
        final kept = original.copyWith(balance: 100.0);
        expect(kept.currency, equals('YER'));

        // Explicitly setting currency to null
        final nulled = original.copyWith(currency: null);
        expect(nulled.currency, isNull);
      });
    });
  });

  group('Supplier Model', () {
    group('construction', () {
      test('creates supplier with required fields', () {
        final supplier = Supplier(name: 'شركة التوريد');
        expect(supplier.name, equals('شركة التوريد'));
        expect(supplier.balance, equals(0.0));
        expect(supplier.balanceType, equals('credit'));
        expect(supplier.currency, equals('YER'));
        expect(supplier.contactMethod, equals('whatsapp'));
      });
    });

    group('getDynamicBalanceLabel', () {
      test('zero balance returns متساوي', () {
        expect(Supplier.getDynamicBalanceLabel(0.0, 'credit'), equals('متساوي'));
        expect(Supplier.getDynamicBalanceLabel(0.0, 'debit'), equals('متساوي'));
      });

      test('positive balance with credit type returns له', () {
        expect(Supplier.getDynamicBalanceLabel(5000.0, 'credit'), equals('له'));
      });

      test('positive balance with debit type returns عليه', () {
        expect(Supplier.getDynamicBalanceLabel(5000.0, 'debit'), equals('عليه'));
      });

      test('negative balance with credit type returns عليه', () {
        expect(Supplier.getDynamicBalanceLabel(-5000.0, 'credit'), equals('عليه'));
      });

      test('negative balance with debit type returns له', () {
        expect(Supplier.getDynamicBalanceLabel(-5000.0, 'debit'), equals('له'));
      });

      test('near-zero balance returns متساوي', () {
        expect(Supplier.getDynamicBalanceLabel(0.003, 'credit'), equals('متساوي'));
      });
    });

    group('serialization', () {
      test('toMap converts balance to cents', () {
        final supplier = Supplier(name: 'شركة التوريد', balance: 250.50, debtCeiling: 10000.0);
        final map = supplier.toMap();
        expect(map['balance'], equals(MoneyHelper.toCents(250.50)));
        expect(map['debt_ceiling'], equals(MoneyHelper.toCents(10000.0)));
      });

      test('round-trip preserves values', () {
        final original = Supplier(
          id: 1, name: 'شركة التوريد', phone: '777654321',
          balance: 3000.75, balanceType: 'debit', currency: 'SAR',
          createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
        );
        final restored = Supplier.fromMap(original.toMap());
        expect(restored.balance, closeTo(original.balance, 0.01));
        expect(restored.balanceType, equals(original.balanceType));
        expect(restored.currency, equals(original.currency));
      });
    });
  });
}
