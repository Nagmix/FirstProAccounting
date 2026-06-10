import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/product_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

void main() {
  late DatabaseHelper dbHelper;
  late InvoiceRepository invoiceRepo;
  late ProductRepository productRepo;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbHelper = DatabaseHelper.instance;
    // Use an in-memory database for testing
    db = await openDatabase(inMemoryDatabasePath, version: 50,
        onCreate: (db, version) async {
      // We need to run the actual migrations to have the schema
      // For simplicity in this test environment, we might need a more robust way
      // But let's try to initialize it properly.
    });
    
    // Actually, DatabaseHelper.instance.database will try to open a real file.
    // For tests, we usually mock or use a specific test path.
    // Let's use a temporary file for the test database.
    final dbPath = p.join(Directory.systemTemp.path, 'test_db_${DateTime.now().millisecondsSinceEpoch}.db');
    db = await dbHelper.openTestDatabase(dbPath);
    invoiceRepo = InvoiceRepository();
    productRepo = ProductRepository();
  });

  tearDown(() async {
    await db.close();
  });

  test('A-9: Purchase in USD should update average_cost in YER (Base Currency)', () async {
    // 1. Create a product with 0 stock
    final productId = await db.insert('products', {
      'name': 'Test Product',
      'category_id': 1,
      'unit_id': 1,
      'current_stock': 0,
      'average_cost': 0,
      'cost_price': 0,
      'costing_method': 'weighted_average',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // 2. Create a purchase invoice in USD
    // Rate: 1 USD = 530 YER
    final invoiceMap = {
      'id': 'INV-001',
      'customer_id': null,
      'supplier_id': 1, // Assume supplier 1 exists
      'date': DateTime.now().toIso8601String(),
      'total': 100.0, // 100 USD
      'currency': 'USD',
      'exchange_rate': 530.0,
      'warehouse_id': 1,
      'discount_amount': 0.0,
      'tax_amount': 0.0,
      'transport_charges': 0.0,
      'is_paid': 1,
      'paid_amount': 100.0,
      'remaining_amount': 0.0,
      'payment_method': 'cash',
      'created_at': DateTime.now().toIso8601String(),
    };

    final items = [
      {
        'product_id': productId,
        'quantity': 10.0,
        'unit_price': 10.0, // 10 USD per piece
        'unit_id': 1,
        'conversion_factor': 1.0,
      }
    ];

    await invoiceRepo.saveInvoiceWithJournalEntries(
      invoiceMap,
      items,
      invoiceType: 'purchase',
      paymentMechanism: 'cash',
      isReturn: false,
    );

    // 3. Check product average_cost
    final product = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    final avgCostCents = product.first['average_cost'] as int;
    final avgCost = MoneyHelper.readMoney(avgCostCents);

    // Expected: 10 USD * 530 YER/USD = 5300 YER
    // Current (BUGGY) behavior: it would be 10.0 (raw USD amount)
    expect(avgCost, 5300.0, reason: 'Average cost should be in YER (base currency)');
  });

  test('A-7: Invoice in USD should have journal entries in USD on USD accounts', () async {
    // 1. Setup accounts for USD (codeOffset = 2)
    // 1202 for Customers USD, 4102 for Sales USD
    // These should be created by seeds, but let's ensure they exist
    
    // 2. Create a sales invoice in USD
    final invoiceMap = {
      'id': 'SALE-001',
      'customer_id': 1,
      'supplier_id': null,
      'date': DateTime.now().toIso8601String(),
      'total': 100.0, // 100 USD
      'currency': 'USD',
      'exchange_rate': 530.0,
      'warehouse_id': 1,
      'discount_amount': 0.0,
      'tax_amount': 0.0,
      'transport_charges': 0.0,
      'is_paid': 0,
      'paid_amount': 0.0,
      'remaining_amount': 100.0,
      'payment_method': 'credit',
      'created_at': DateTime.now().toIso8601String(),
    };

    final items = [
      {
        'product_id': 1,
        'quantity': 1.0,
        'unit_price': 100.0,
        'unit_id': 1,
        'conversion_factor': 1.0,
      }
    ];

    await invoiceRepo.saveInvoiceWithJournalEntries(
      invoiceMap,
      items,
      invoiceType: 'sales',
      paymentMechanism: 'credit',
      isReturn: false,
    );

    // 3. Check transactions
    final transactions = await db.query('transactions', where: 'reference_id = ?', whereArgs: ['SALE-001']);
    
    for (var tx in transactions) {
      // Expected: currency_code = 'USD', amount_base = amount * 530
      expect(tx['currency_code'], 'USD', reason: 'Transaction should be in USD');
      
      final debit = MoneyHelper.readMoney(tx['debit'] as int);
      final credit = MoneyHelper.readMoney(tx['credit'] as int);
      final amount = debit > 0 ? debit : credit;
      final amountBase = MoneyHelper.readMoney(tx['amount_base'] as int);
      
      expect(amountBase, closeTo(amount * 530.0, 0.001), reason: 'amount_base should be correctly converted to YER');
    }
  });
}
