import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/services/cash_box_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> createDatabase() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return db;
  }

  test('posted voucher cannot be deleted and remains auditable', () async {
    final db = await createDatabase();
    final service = CashBoxService(DatabaseHelper());
    try {
      final voucherId = await db.insert('vouchers', {
        'voucher_number': 'V-POSTED-1',
        'voucher_type': 'receipt',
        'date': '2026-08-26',
        'currency': 'YER',
        'total_amount': 10000,
        'is_posted': 1,
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });

      await expectLater(
        service.deleteVoucher(voucherId),
        throwsA(isA<StateError>()),
      );

      expect(
        await db.query('vouchers', where: 'id = ?', whereArgs: [voucherId]),
        hasLength(1),
      );
    } finally {
      DatabaseHelper.clearTestDatabase();
      await db.close();
    }
  });

  test('cancelling posted voucher keeps source and records balanced reversal',
      () async {
    final db = await createDatabase();
    final service = CashBoxService(DatabaseHelper());
    try {
      final cashAccountId = await db.insert('accounts', {
        'name_ar': 'النقدية',
        'account_code': '1100',
        'account_type': 'ASSET',
        'currency': 'YER',
        'balance_type': 'debit',
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });
      final incomeAccountId = await db.insert('accounts', {
        'name_ar': 'الإيرادات',
        'account_code': '4100',
        'account_type': 'REVENUE',
        'currency': 'YER',
        'balance_type': 'credit',
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });
      final voucherId = await db.insert('vouchers', {
        'voucher_number': 'V-POSTED-2',
        'voucher_type': 'receipt',
        'date': '2026-08-26',
        'currency': 'YER',
        'total_amount': 10000,
        'is_posted': 1,
        'created_at': '2026-08-26T10:00:00.000Z',
        'updated_at': '2026-08-26T10:00:00.000Z',
      });
      await db.insert('voucher_items', {
        'voucher_id': voucherId,
        'account_id': cashAccountId,
        'debit': 10000,
        'credit': 0,
        'description': 'النقدية',
        'created_at': '2026-08-26T10:00:00.000Z',
      });
      await db.insert('voucher_items', {
        'voucher_id': voucherId,
        'account_id': incomeAccountId,
        'debit': 0,
        'credit': 10000,
        'description': 'الإيرادات',
        'created_at': '2026-08-26T10:00:00.000Z',
      });

      await service.cancelVoucher(voucherId, reason: 'تصحيح إدخال');

      expect(
        await db.query('vouchers', where: 'id = ?', whereArgs: [voucherId]),
        hasLength(1),
      );
      expect(
        await db.query('voucher_items',
            where: 'voucher_id = ?', whereArgs: [voucherId]),
        hasLength(2),
      );
      final reversals = await db.query(
        'document_reversals',
        where: 'document_type = ? AND document_id = ?',
        whereArgs: ['voucher', voucherId.toString()],
      );
      expect(reversals, hasLength(1));
      final reversalJournalId = reversals.single['reversal_journal_id'];
      final totals = await db.rawQuery(
        'SELECT COALESCE(SUM(debit), 0) AS debit, '
        'COALESCE(SUM(credit), 0) AS credit FROM transactions '
        'WHERE journal_id = ?',
        [reversalJournalId],
      );
      expect(totals.single['debit'], totals.single['credit']);
    } finally {
      DatabaseHelper.clearTestDatabase();
      await db.close();
    }
  });
}
