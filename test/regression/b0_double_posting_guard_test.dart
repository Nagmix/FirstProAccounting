import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';

/// ══════════════════════════════════════════════════════════════════
/// B-0 — حارس الترحيل المزدوج (Double-Posting Guard)
///
/// المشكلة الأصلية (A-2): شاشة تفاصيل الصندوق كانت تستدعي
/// CashBoxService.insertVoucher (الذي يرحّل القيود ويحدّث الأرصدة
/// ورصيد الصندوق ذرّياً) ثم تكرر كل ذلك يدوياً مرة ثانية خارج أي
/// transaction — فتتضاعف القيود والأرصدة مع كل سند قبض/صرف.
///
/// هذا الملف يحتوي على:
/// 1. حارس مصدري: يفشل إذا عاد نمط الترحيل اليدوي إلى الشاشة.
/// 2. اختبار سلوكي: يحاكي منطق insertVoucher على قاعدة في الذاكرة
///    ويتحقق أن الترحيل الواحد ينتج قيدين فقط ورصيداً صحيحاً
///    (وأن التكرار — لو حدث — يكتشفه الاختبار).
/// ══════════════════════════════════════════════════════════════════

void main() {
  group('B-0 Source Guard — cash_box_detail_screen must not manually post', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/ui/screens/cash_boxes/cash_box_detail_screen.dart',
      ).readAsStringSync();
    });

    test('screen does not insert journal transactions directly', () {
      // The screen must never write to the `transactions` table itself —
      // posting belongs to CashBoxService.insertVoucher (atomic).
      expect(
        source.contains("insert('transactions'"),
        isFalse,
        reason: 'وجد إدراج يدوي في جدول transactions داخل الشاشة — '
            'هذا يعيد مشكلة الترحيل المزدوج A-2. الترحيل مسؤولية '
            'CashBoxService.insertVoucher حصراً.',
      );
    });

    test('screen does not manually update account balances after insertVoucher',
        () {
      expect(
        source.contains('updateAccountBalance('),
        isFalse,
        reason: 'وجد استدعاء updateAccountBalance يدوي في الشاشة — '
            'insertVoucher يحدّث الأرصدة بنفسه داخل المعاملة.',
      );
    });

    test('screen does not manually update the cash box balance', () {
      expect(
        source.contains("update('cash_boxes'"),
        isFalse,
        reason: 'وجد تحديث يدوي لرصيد الصندوق في الشاشة — '
            'insertVoucher يحدّث رصيد الصندوق بنفسه عبر cash_box_id.',
      );
    });

    test('screen still creates vouchers through insertVoucher', () {
      expect(
        source.contains('insertVoucher('),
        isTrue,
        reason: 'يجب أن تستمر الشاشة في استخدام insertVoucher '
            'كمسار الترحيل الوحيد.',
      );
    });
  });

  group('B-0 Behavioral — single posting produces exactly one journal set', () {
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

    /// Replicates CashBoxService.insertVoucher posting logic (the single
    /// source of truth) against the in-memory DB.
    Future<int> postVoucherOnce({
      required Database database,
      required Map<String, dynamic> voucherMap,
      required List<Map<String, dynamic>> items,
    }) async {
      final now = DateTime.now().toIso8601String();
      final journalId = DateTime.now().microsecondsSinceEpoch;
      int voucherId = 0;
      await database.transaction((txn) async {
        voucherId = await txn.insert(
          'vouchers',
          MoneyHelper.toCentsMap(voucherMap, MoneyHelper.voucherMoneyFields),
        );
        for (final item in items) {
          final itemMap = Map<String, dynamic>.from(item);
          itemMap['voucher_id'] = voucherId;
          itemMap['created_at'] = now;
          await txn.insert(
            'voucher_items',
            MoneyHelper.toCentsMap(itemMap, MoneyHelper.transactionMoneyFields),
          );
          final accountId = (item['account_id'] as num?)?.toInt();
          final debit = MoneyHelper.readMoney(item['debit']);
          final credit = MoneyHelper.readMoney(item['credit']);
          if (accountId != null && (debit > 0 || credit > 0)) {
            await txn.insert('transactions', {
              'account_id': accountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(debit),
              'credit': MoneyHelper.toCents(credit),
              'description': item['description'] ?? 'سند',
              'date': voucherMap['date'],
              'created_at': now,
              'currency_code': voucherMap['currency'] ?? 'YER',
              'exchange_rate': 1.0,
              'amount_base': MoneyHelper.toCents(debit > 0 ? debit : credit),
            });
          }
        }
        // Cash box balance update (credit-nature cash box, receipt = cash in)
        final cashBoxId = voucherMap['cash_box_id'];
        if (cashBoxId != null) {
          final rows = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          if (rows.isNotEmpty) {
            final current = MoneyHelper.readMoney(rows.first['balance']);
            final amount = MoneyHelper.readMoney(voucherMap['total_amount']);
            final isCashIn = voucherMap['voucher_type'] == 'receipt';
            final newBalance = isCashIn ? current + amount : current - amount;
            await txn.update(
              'cash_boxes',
              {'balance': MoneyHelper.toCents(newBalance), 'updated_at': now},
              where: 'id = ?',
              whereArgs: [cashBoxId],
            );
          }
        }
      });
      return voucherId;
    }

    Future<({int cashBoxId, int cashAccountId, int contraAccountId})>
        seedFixtures() async {
      final now = DateTime.now().toIso8601String();

      Future<int> getOrInsertAccount({
        required String code,
        required String nameAr,
        required String nameEn,
        required String type,
        required String balanceType,
      }) async {
        final existing = await db.query(
          'accounts',
          columns: ['id'],
          where: 'account_code = ? AND currency = ?',
          whereArgs: [code, 'YER'],
          limit: 1,
        );
        if (existing.isNotEmpty) return existing.first['id'] as int;
        return db.insert('accounts', {
          'name_ar': nameAr,
          'name_en': nameEn,
          'account_code': code,
          'account_type': type,
          'balance': 0,
          'currency': 'YER',
          'balance_type': balanceType,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
      }

      final cashAccountId = await getOrInsertAccount(
        code: '1100',
        nameAr: 'الصناديق والبنوك',
        nameEn: 'Cash & Banks',
        type: 'ASSET',
        balanceType: 'debit',
      );
      final contraAccountId = await getOrInsertAccount(
        code: '2901',
        nameAr: 'رصيد افتتاحي',
        nameEn: 'Opening Balance Equity',
        type: 'EQUITY',
        balanceType: 'credit',
      );
      final cashBoxId = await db.insert('cash_boxes', {
        'name': 'الصندوق الرئيسي',
        'balance': 0,
        'balance_type': 'credit',
        'currency': 'YER',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      return (
        cashBoxId: cashBoxId,
        cashAccountId: cashAccountId,
        contraAccountId: contraAccountId,
      );
    }

    test('one receipt voucher = exactly 2 journal rows and correct balance',
        () async {
      final f = await seedFixtures();
      final now = DateTime.now().toIso8601String();

      final voucherMap = {
        'voucher_number': 'RV-0001',
        'voucher_type': 'receipt',
        'date': now,
        'description': 'سند قبض اختباري',
        'currency': 'YER',
        'total_amount': 1000.0,
        'cash_box_id': f.cashBoxId,
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      };
      final items = [
        {
          'account_id': f.cashAccountId,
          'debit': 1000.0,
          'credit': 0.0,
          'description': 'سند قبض اختباري',
        },
        {
          'account_id': f.contraAccountId,
          'debit': 0.0,
          'credit': 1000.0,
          'description': 'سند قبض اختباري',
        },
      ];

      // ── الترحيل الصحيح: مرة واحدة فقط (كما تفعل الشاشة بعد إصلاح B-0) ──
      await postVoucherOnce(database: db, voucherMap: voucherMap, items: items);

      // 1. عدد القيود = 2 بالضبط (مدين + دائن)، وليس 4
      final txCount =
          (await db.rawQuery('SELECT COUNT(*) AS n FROM transactions'))
              .first['n'] as int;
      expect(txCount, 2,
          reason: 'يجب أن ينتج سند واحد قيدين بالضبط — أي عدد أكبر '
              'يعني ترحيلاً مزدوجاً (A-2)');

      // 2. توازن القيد: مجموع المدين = مجموع الدائن = 1000
      final sums = (await db.rawQuery(
              'SELECT SUM(debit) AS d, SUM(credit) AS c FROM transactions'))
          .first;
      expect(sums['d'], MoneyHelper.toCents(1000.0));
      expect(sums['c'], MoneyHelper.toCents(1000.0));

      // 3. رصيد الصندوق = 1000 بالضبط، وليس 2000
      final box = (await db.query('cash_boxes',
              where: 'id = ?', whereArgs: [f.cashBoxId], limit: 1))
          .first;
      expect(MoneyHelper.readMoney(box['balance']), 1000.0,
          reason: 'رصيد الصندوق يجب أن يزيد بمبلغ السند مرة واحدة فقط');

      // 4. سند واحد فقط في جدول السندات
      final vCount = (await db.rawQuery('SELECT COUNT(*) AS n FROM vouchers'))
          .first['n'] as int;
      expect(vCount, 1);
    });

    test('double posting (the old bug) is detectable by the same assertions',
        () async {
      final f = await seedFixtures();
      final now = DateTime.now().toIso8601String();

      final voucherMap = {
        'voucher_number': 'RV-0002',
        'voucher_type': 'receipt',
        'date': now,
        'description': 'سند قبض',
        'currency': 'YER',
        'total_amount': 500.0,
        'cash_box_id': f.cashBoxId,
        'is_posted': 1,
        'created_at': now,
        'updated_at': now,
      };
      final items = [
        {
          'account_id': f.cashAccountId,
          'debit': 500.0,
          'credit': 0.0,
          'description': 'سند قبض'
        },
        {
          'account_id': f.contraAccountId,
          'debit': 0.0,
          'credit': 500.0,
          'description': 'سند قبض'
        },
      ];

      // المسار الصحيح
      await postVoucherOnce(database: db, voucherMap: voucherMap, items: items);

      // محاكاة الخلل القديم: تكرار إدراج القيود وتحديث رصيد الصندوق يدوياً
      final nowStr = DateTime.now().toIso8601String();
      for (final item in items) {
        await db.insert('transactions', {
          'account_id': item['account_id'],
          'journal_id': DateTime.now().microsecondsSinceEpoch,
          'debit': MoneyHelper.toCents((item['debit'] as double)),
          'credit': MoneyHelper.toCents((item['credit'] as double)),
          'description': 'تكرار يدوي (الخلل القديم)',
          'date': nowStr,
          'created_at': nowStr,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(((item['debit'] as double) > 0
              ? item['debit']
              : item['credit']) as double),
        });
      }
      final box0 = (await db.query('cash_boxes',
              where: 'id = ?', whereArgs: [f.cashBoxId], limit: 1))
          .first;
      await db.update(
        'cash_boxes',
        {
          'balance': MoneyHelper.toCents(
              MoneyHelper.readMoney(box0['balance']) + 500.0),
        },
        where: 'id = ?',
        whereArgs: [f.cashBoxId],
      );

      // الآن نتحقق أن أدوات الكشف ترصد الخلل:
      final txCount =
          (await db.rawQuery('SELECT COUNT(*) AS n FROM transactions'))
              .first['n'] as int;
      expect(txCount, isNot(2),
          reason: 'الترحيل المزدوج ينتج 4 قيود بدل 2 — يجب أن يكون '
              'قابلاً للاكتشاف');

      final box = (await db.query('cash_boxes',
              where: 'id = ?', whereArgs: [f.cashBoxId], limit: 1))
          .first;
      expect(MoneyHelper.readMoney(box['balance']), isNot(500.0),
          reason: 'الترحيل المزدوج يضاعف رصيد الصندوق (1000 بدل 500)');
    });
  });
}
