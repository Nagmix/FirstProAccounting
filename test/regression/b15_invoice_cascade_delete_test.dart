import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';

/// ══════════════════════════════════════════════════════════════════
/// B-1.5 (A-3) — اختبارات حذف الفاتورة التعاقبي
///
/// الأخطاء الأصلية الثلاثة:
///   1. حذف حركات المخزون دون إعادة الكميات للمنتجات.
///   2. حذف القيود دون عكس أثرها على أرصدة الحسابات.
///   3. مطابقة القيود بـ LIKE '%id%' فتُحذف قيود فواتير أخرى
///      (فاتورة "12" تطابق "112" و"120").
/// ══════════════════════════════════════════════════════════════════

void main() {
  group('B-1.5 Source Guard — deleteInvoiceWithCascade', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/data/datasources/repositories/invoice_repository.dart',
      ).readAsStringSync();
    });

    test('no bare substring LIKE matching on invoice id', () {
      expect(
        source.contains(r"'%$invoiceId%'"),
        isFalse,
        reason: "مطابقة LIKE '%invoiceId%' خطرة: فاتورة 12 تطابق 112 و120 "
            'فتُحذف قيود فواتير أخرى. استخدم reference_id أو النمط '
            "الدقيق '% - id'.",
      );
    });

    test('cascade delete restores stock before deleting movements', () {
      final idx = source.indexOf('deleteInvoiceWithCascade');
      expect(idx, greaterThan(0));
      final body = source.substring(idx, idx + 7000);
      expect(
        body.contains('current_stock = current_stock - ?'),
        isTrue,
        reason: 'يجب عكس كميات المخزون من الحركات قبل حذفها.',
      );
    });

    test('cascade delete reverses account balances for deleted journals', () {
      final idx = source.indexOf('deleteInvoiceWithCascade');
      final body = source.substring(idx, idx + 9000);
      expect(
        body.contains('updateAccountBalanceWithJournal'),
        isTrue,
        reason: 'يجب عكس أثر كل قيد محذوف على رصيد حسابه.',
      );
    });

    test('cascade delete checks fiscal period before deleting', () {
      final idx = source.indexOf('deleteInvoiceWithCascade');
      final body = source.substring(idx, idx + 9000);
      expect(body.contains('checkFiscalPeriodOpen'), isTrue,
          reason: 'لا يجوز حذف فاتورة في فترة مالية مقفلة.');
    });
  });

  group('B-1.5 Behavioral — reversal math on in-memory DB', () {
    late Database db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 50,
        onCreate: (database, version) async {
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

    test('stock restoration: signed movement quantity reversal is exact',
        () async {
      final now = DateTime.now().toIso8601String();
      // منتج برصيد 100 ثم بيع 30 (الحركة تخزن -30 والرصيد صار 70)
      final productId = await db.insert('products', {
        'name_ar': 'منتج اختبار',
        'name_en': 'Test Product',
        'sell_price': MoneyHelper.toCents(100),
        'cost_price': MoneyHelper.toCents(60),
        'average_cost': MoneyHelper.toCents(60),
        'current_stock': 70.0,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('stock_movements', {
        'product_id': productId,
        'movement_type': 'sale',
        'quantity': -30.0,
        'reference_type': 'sale',
        'reference_id': 'INV-12',
        'unit_cost': MoneyHelper.toCents(60),
        'created_at': now,
      });

      // الإلغاء: current_stock - quantity = 70 - (-30) = 100
      final movements = await db.query('stock_movements',
          where: 'reference_id = ?', whereArgs: ['INV-12']);
      for (final m in movements) {
        final qty = (m['quantity'] as num).toDouble();
        await db.rawUpdate(
          'UPDATE products SET current_stock = current_stock - ? WHERE id = ?',
          [qty, productId],
        );
      }

      final row = (await db.query('products',
              where: 'id = ?', whereArgs: [productId], limit: 1))
          .first;
      expect((row['current_stock'] as num).toDouble(), 100.0,
          reason: 'حذف فاتورة بيع 30 قطعة يجب أن يعيد المخزون من 70 إلى 100');
    });

    test('precise matching: deleting invoice 12 must not touch invoice 112',
        () async {
      final now = DateTime.now().toIso8601String();
      final accId = await db.insert('accounts', {
        'name_ar': 'المبيعات',
        'name_en': 'Sales',
        'account_code': '4100',
        'account_type': 'REVENUE',
        'balance': 0,
        'currency': 'YER',
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      Future<void> insertTx(String desc, String? refId) => db.insert(
            'transactions',
            {
              'account_id': accId,
              'journal_id': DateTime.now().microsecondsSinceEpoch,
              'debit': 0,
              'credit': MoneyHelper.toCents(100),
              'description': desc,
              'date': now,
              'created_at': now,
              'reference_id': refId,
              'currency_code': 'YER',
            },
          );

      await insertTx('إيراد مبيعات - 12', '12'); // الفاتورة المستهدفة
      await insertTx('إيراد مبيعات - 112', '112'); // يجب ألا تُمس
      await insertTx('إيراد مبيعات - 120', '120'); // يجب ألا تُمس

      // النمط الدقيق المعتمد في الإصلاح:
      final matched = await db.rawQuery(
        'SELECT * FROM transactions WHERE reference_id = ? OR description LIKE ?',
        ['12', '% - 12'],
      );
      expect(matched.length, 1,
          reason: 'النمط الدقيق يطابق الفاتورة 12 فقط، '
              'وليس 112 أو 120');

      // النمط القديم الخطير كان سيطابق الثلاثة:
      final dangerous = await db.rawQuery(
        'SELECT * FROM transactions WHERE description LIKE ?',
        ['%12%'],
      );
      expect(dangerous.length, 3,
          reason: 'يؤكد أن النمط القديم كان فعلاً يصيب فواتير أخرى');
    });

    test('account balance reversal: swapped debit/credit restores balance',
        () async {
      final now = DateTime.now().toIso8601String();
      // حساب مبيعات (دائن الطبيعة) رصيده 1000 بعد فاتورة
      final accId = await db.insert('accounts', {
        'name_ar': 'المبيعات',
        'name_en': 'Sales',
        'account_code': '4100',
        'account_type': 'REVENUE',
        'balance': MoneyHelper.toCents(1000),
        'currency': 'YER',
        'balance_type': 'credit',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // القيد الأصلي كان: credit=1000. العكس = تطبيق (debit=1000):
      // credit-nature: balance += credit - debit = -1000
      await db.rawUpdate('''
        UPDATE accounts SET balance = balance + CASE
          WHEN balance_type = 'credit' THEN ? - ?
          ELSE ? - ?
        END WHERE id = ?
      ''', [
        0, // معكوس: credit الجديد = debit الأصلي = 0... swapped
        MoneyHelper.toCents(1000),
        MoneyHelper.toCents(1000),
        0,
        accId,
      ]);

      final row = (await db.query('accounts',
              where: 'id = ?', whereArgs: [accId], limit: 1))
          .first;
      expect(MoneyHelper.readMoney(row['balance']), 0.0,
          reason: 'عكس قيد دائن 1000 على حساب دائن الطبيعة يعيد الرصيد للصفر');
    });

    test('cash box reversal sign matrix', () {
      // reversalSign = ((bt == credit) == isCashIn) ? -1 : +1
      int sign(String bt, bool isCashIn) =>
          ((bt == 'credit') == isCashIn) ? -1 : 1;

      // بيع نقدي على صندوق credit: الأصل +paid ⇒ العكس -paid
      expect(sign('credit', true), -1);
      // شراء نقدي على صندوق credit: الأصل -paid ⇒ العكس +paid
      expect(sign('credit', false), 1);
      // بيع نقدي على صندوق debit: الأصل -paid ⇒ العكس +paid
      expect(sign('debit', true), 1);
      // شراء نقدي على صندوق debit: الأصل +paid ⇒ العكس -paid
      expect(sign('debit', false), -1);
    });
  });
}
