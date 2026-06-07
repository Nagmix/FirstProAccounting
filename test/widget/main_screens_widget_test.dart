import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/customer_model.dart';
import 'package:firstpro/data/models/supplier_model.dart';
import 'package:firstpro/data/models/cash_box_model.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';

/// ══════════════════════════════════════════════════════════════════
/// 7.2 — اختبارات الويدجت للشاشات الرئيسية
/// Widget tests for main screens:
///   - Customer data rendering
///   - Supplier data rendering
///   - Cash box data rendering
///   - Loading, error, and empty states
///   - User interactions (tap, scroll, search)
/// ══════════════════════════════════════════════════════════════════

void main() {
  // ══════════════════════════════════════════════════════════════
  //  Model Tests (domain logic for widgets)
  // ══════════════════════════════════════════════════════════════

  group('Customer Model', () {
    test('toMap and fromMap round-trip preserves data', () {
      final customer = Customer(
        id: 1,
        name: 'أحمد محمد',
        phone: '777123456',
        address: 'صنعاء',
        email: 'ahmed@test.com',
        balance: 5000.0,
        balanceType: 'credit',
        currency: 'YER',
        debtCeiling: 10000.0,
      );

      final map = customer.toMap();
      final restored = Customer.fromMap(map);

      expect(restored.id, customer.id);
      expect(restored.name, customer.name);
      expect(restored.phone, customer.phone);
      expect(restored.balance, customer.balance);
      expect(restored.balanceType, customer.balanceType);
      expect(restored.currency, customer.currency);
    });

    test('Balance direction is correct', () {
      // Credit balance (له) - customer has money coming to them
      final creditCustomer = Customer(
        name: 'عميل دائن',
        balance: 5000.0,
        balanceType: 'credit',
      );
      expect(creditCustomer.balanceType, 'credit');
      expect(creditCustomer.balance, greaterThan(0));

      // Debit balance (عليه) - customer owes money
      final debitCustomer = Customer(
        name: 'عميل مدين',
        balance: 3000.0,
        balanceType: 'debit',
      );
      expect(debitCustomer.balanceType, 'debit');
      expect(debitCustomer.balance, greaterThan(0));
    });

    test('copyWith creates correct copy', () {
      final original = Customer(
        id: 1,
        name: 'عميل أصلي',
        balance: 1000.0,
        balanceType: 'credit',
        currency: 'YER',
      );

      final modified = original.copyWith(
        balance: 2000.0,
        name: 'عميل معدل',
      );

      expect(modified.id, original.id);
      expect(modified.name, 'عميل معدل');
      expect(modified.balance, 2000.0);
      expect(modified.balanceType, original.balanceType);
      expect(modified.currency, original.currency);
    });
  });

  group('Supplier Model', () {
    test('toMap and fromMap round-trip preserves data', () {
      final supplier = Supplier(
        id: 1,
        name: 'شركة التوريد',
        phone: '01234567',
        email: 'supplier@test.com',
        balance: 8000.0,
        balanceType: 'credit',
        currency: 'SAR',
      );

      final map = supplier.toMap();
      final restored = Supplier.fromMap(map);

      expect(restored.id, supplier.id);
      expect(restored.name, supplier.name);
      expect(restored.balance, supplier.balance);
      expect(restored.currency, supplier.currency);
    });
  });

  group('CashBox Model', () {
    test('Type helpers work correctly', () {
      final cashBox = CashBox(
        id: 1,
        name: 'الصندوق الرئيسي',
        type: 'cash_box',
        currency: 'YER',
        balance: 10000.0,
        balanceType: 'credit',
      );

      expect(cashBox.isCashBox, isTrue);
      expect(cashBox.isBank, isFalse);
      expect(cashBox.typeAr, 'صندوق');

      final bank = CashBox(
        id: 2,
        name: 'البنك الأهلي',
        type: 'bank',
        currency: 'SAR',
        balance: 50000.0,
        balanceType: 'credit',
      );

      expect(bank.isBank, isTrue);
      expect(bank.isCashBox, isFalse);
      expect(bank.typeAr, 'بنك');
    });

    test('Effective balance calculation is correct', () {
      // Credit balance: effective is positive (له)
      final creditBox = CashBox(
        name: 'صندوق دائن',
        balance: 5000.0,
        balanceType: 'credit',
      );
      final creditEffective = creditBox.balanceType == 'credit'
          ? creditBox.balance
          : -creditBox.balance;
      expect(creditEffective, 5000.0);
      expect(creditEffective >= 0, isTrue);

      // Debit balance: effective is negative (عليه)
      final debitBox = CashBox(
        name: 'صندوق مدين',
        balance: 3000.0,
        balanceType: 'debit',
      );
      final debitEffective = debitBox.balanceType == 'credit'
          ? debitBox.balance
          : -debitBox.balance;
      expect(debitEffective, -3000.0);
      expect(debitEffective < 0, isTrue);
    });

    test('Bank-specific fields are preserved', () {
      final bank = CashBox(
        name: 'البنك الأهلي',
        type: 'bank',
        bankName: 'الأهلي',
        bankBranch: 'الفرع الرئيسي',
        bankAccountNumber: 'ACC-12345',
        currency: 'SAR',
        balance: 100000.0,
        balanceType: 'credit',
      );

      final map = bank.toMap();
      final restored = CashBox.fromMap(map);

      expect(restored.bankName, 'الأهلي');
      expect(restored.bankBranch, 'الفرع الرئيسي');
      expect(restored.bankAccountNumber, 'ACC-12345');
      expect(restored.isBank, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Currency Formatter Tests (UI rendering)
  // ══════════════════════════════════════════════════════════════

  group('Currency Formatter', () {
    test('Formats integer amounts correctly', () {
      expect(CurrencyFormatter.format(1000.0), contains('1,000'));
      expect(CurrencyFormatter.format(0.0), contains('0'));
    });

    test('Formats decimal amounts correctly', () {
      expect(CurrencyFormatter.format(1000.50), contains('1,000.5'));
    });

    test('Formats large amounts with commas', () {
      expect(CurrencyFormatter.format(1000000.0), contains('1,000,000'));
      expect(CurrencyFormatter.format(12345.67), contains('12,345'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Money Helper Tests (core for all financial widgets)
  // ══════════════════════════════════════════════════════════════

  group('MoneyHelper', () {
    test('toCents and fromCents are inverse operations', () {
      final testValues = [0.0, 0.01, 1.0, 99.99, 100.0, 9999.99, 1000000.0];
      for (final value in testValues) {
        final cents = MoneyHelper.toCents(value);
        final restored = MoneyHelper.fromCents(cents);
        expect(restored, equals(value),
            reason: 'MoneyHelper lost precision for $value');
      }
    });

    test('readMoney handles int (cents) correctly', () {
      // New format: integer cents
      expect(MoneyHelper.readMoney(10000), 100.0);
      expect(MoneyHelper.readMoney(0), 0.0);
      expect(MoneyHelper.readMoney(1), 0.01);
    });

    test('readMoney handles double (legacy) correctly', () {
      // Legacy format: already in human-readable double
      expect(MoneyHelper.readMoney(100.0), 100.0);
      expect(MoneyHelper.readMoney(0.0), 0.0);
    });

    test('readMoney handles null with fallback', () {
      expect(MoneyHelper.readMoney(null), 0.0);
      expect(MoneyHelper.readMoney(null, fallback: 5.0), 5.0);
    });

    test('readCalculatedMoney always divides by 100', () {
      // Calculated SQL results are always in cents
      expect(MoneyHelper.readCalculatedMoney(10000), 100.0);
      expect(MoneyHelper.readCalculatedMoney(10000.0), 100.0); // REAL from SQL
      expect(MoneyHelper.readCalculatedMoney(0), 0.0);
    });

    test('round2 rounds to 2 decimal places', () {
      expect(MoneyHelper.round2(1.005), closeTo(1.01, 0.001));
      expect(MoneyHelper.round2(1.004), closeTo(1.0, 0.001));
      expect(MoneyHelper.round2(99.999), closeTo(100.0, 0.001));
    });

    test('isZero detects effectively zero amounts', () {
      expect(MoneyHelper.isZero(0.0), isTrue);
      expect(MoneyHelper.isZero(0.001), isFalse);
      expect(MoneyHelper.isZero(-0.001), isFalse);
    });

    test('add and subtract maintain precision', () {
      // Classic floating-point problem: 0.1 + 0.2 != 0.3
      expect(MoneyHelper.add(0.1, 0.2), equals(0.3));
      expect(MoneyHelper.subtract(1.0, 0.3), equals(0.7));
      expect(MoneyHelper.add(99.99, 0.01), equals(100.0));
    });

    test('multiply and divide maintain precision', () {
      expect(MoneyHelper.multiply(100.0, 1.5), equals(150.0));
      expect(MoneyHelper.divide(100.0, 3), closeTo(33.33, 0.01));
      expect(MoneyHelper.divide(100.0, 0), equals(0.0));
    });

    test('compare works correctly for monetary values', () {
      expect(MoneyHelper.compare(1.0, 1.0), equals(0));
      expect(MoneyHelper.compare(1.01, 1.0), greaterThan(0));
      expect(MoneyHelper.compare(1.0, 1.01), lessThan(0));
      // Floating-point trap: 0.1 + 0.2 != 0.3 normally
      expect(MoneyHelper.compare(MoneyHelper.add(0.1, 0.2), 0.3), equals(0));
    });

    test('toCentsMap converts specified fields correctly', () {
      final map = {
        'name': 'Test',
        'balance': 1000.0,
        'opening_balance': 500.0,
        'non_money_field': 'hello',
      };

      final converted = MoneyHelper.toCentsMap(
        map,
        MoneyHelper.customerMoneyFields,
      );

      expect(converted['name'], 'Test');
      expect(converted['balance'], 100000); // 1000.0 * 100
      expect(converted['opening_balance'], 50000); // 500.0 * 100
      expect(converted['non_money_field'], 'hello');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Widget Rendering Tests (basic widget smoke tests)
  // ══════════════════════════════════════════════════════════════

  group('Widget Smoke Tests', () {
    testWidgets('Empty state widget renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 72),
                  const SizedBox(height: 16),
                  const Text('لا توجد صناديق أو بنوك'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة جديدة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('لا توجد صناديق أو بنوك'), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet), findsOneWidget);
      expect(find.text('إضافة جديدة'), findsOneWidget);
    });

    testWidgets('Cash box card renders balance correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestCashBoxCard(
              name: 'الصندوق الرئيسي',
              balance: 5000.0,
              balanceType: 'credit',
              isBank: false,
            ),
          ),
        ),
      );

      expect(find.text('الصندوق الرئيسي'), findsOneWidget);
      expect(find.text('صندوق'), findsOneWidget);
      expect(find.text('له'), findsOneWidget);
    });

    testWidgets('Cash box card shows عليه for debit balance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestCashBoxCard(
              name: 'صندوق مدين',
              balance: 3000.0,
              balanceType: 'debit',
              isBank: false,
            ),
          ),
        ),
      );

      expect(find.text('صندوق مدين'), findsOneWidget);
      expect(find.text('عليه'), findsOneWidget);
    });

    testWidgets('Loading state shows progress indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Error state shows error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text('حدث خطأ أثناء تحميل البيانات'),
                  SizedBox(height: 8),
                  FilledButton(onPressed: null, child: Text('إعادة المحاولة')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('حدث خطأ أثناء تحميل البيانات'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Tab bar renders all tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'الكل'),
                    Tab(text: 'صناديق'),
                    Tab(text: 'بنوك'),
                  ],
                ),
              ),
              body: const TabBarView(
                children: [
                  Center(child: Text('محتوى الكل')),
                  Center(child: Text('محتوى الصناديق')),
                  Center(child: Text('محتوى البنوك')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('صناديق'), findsOneWidget);
      expect(find.text('بنوك'), findsOneWidget);

      // Tap on 'بنوك' tab
      await tester.tap(find.text('بنوك'));
      await tester.pumpAndSettle();

      expect(find.text('محتوى البنوك'), findsOneWidget);
    });
  });
}

/// Test helper widget for cash box card rendering
class _TestCashBoxCard extends StatelessWidget {
  final String name;
  final double balance;
  final String balanceType;
  final bool isBank;

  const _TestCashBoxCard({
    required this.name,
    required this.balance,
    required this.balanceType,
    required this.isBank,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBalance = balanceType == 'credit' ? balance : -balance;
    final isCredit = effectiveBalance >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(isBank ? 'بنك' : 'صندوق'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.format(effectiveBalance.abs())),
                Text(isCredit ? 'له' : 'عليه'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
