import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/order_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(dynamic, OrderRepository)> createRepository() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return (db, OrderRepository(DatabaseHelper()));
  }

  tearDown(() {
    DatabaseHelper.clearTestDatabase();
  });

  Future<void> expectDeletionRejected({
    required String table,
    required String id,
    required String itemTable,
    required String itemForeignKey,
    required String status,
  }) async {
    final (db, repository) = await createRepository();
    try {
      final now = '2026-08-27T00:00:00.000Z';
      final idColumn = table == 'quotations' ? 'quotation_number' : 'order_number';
      await db.insert(table, {
        'id': id,
        idColumn: 'DOC-$id',
        'status': status,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert(itemTable, {
        itemForeignKey: id,
        'product_name': 'بند الاختبار',
      });

      Future<void> deleteDocument() {
        if (table == 'quotations') return repository.deleteQuotation(id);
        if (table == 'purchase_orders') return repository.deletePurchaseOrder(id);
        return repository.deleteSalesOrder(id);
      }

      await expectLater(deleteDocument(), throwsA(isA<StateError>()));
      expect(await db.query(table, where: 'id = ?', whereArgs: [id]), hasLength(1));
      expect(
        await db.query(itemTable, where: '$itemForeignKey = ?', whereArgs: [id]),
        hasLength(1),
      );
    } finally {
      await db.close();
    }
  }

  test('deleting a confirmed quotation is rejected without data loss', () async {
    await expectDeletionRejected(
      table: 'quotations',
      id: 'Q-POSTED',
      itemTable: 'quotation_items',
      itemForeignKey: 'quotation_id',
      status: 'confirmed',
    );
  });

  test('deleting a confirmed purchase order is rejected without data loss', () async {
    await expectDeletionRejected(
      table: 'purchase_orders',
      id: 'PO-POSTED',
      itemTable: 'purchase_order_items',
      itemForeignKey: 'purchase_order_id',
      status: 'confirmed',
    );
  });

  test('deleting a confirmed sales order is rejected without data loss', () async {
    await expectDeletionRejected(
      table: 'sales_orders',
      id: 'SO-POSTED',
      itemTable: 'sales_order_items',
      itemForeignKey: 'sales_order_id',
      status: 'confirmed',
    );
  });
}

