import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/transaction_model.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:firstpro/data/models/invoice_item_model.dart';
import 'package:firstpro/data/models/inventory_cost_layer_model.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Transaction, Product, InvoiceItem, and InventoryCostLayer Model Tests
void main() {
  group('Transaction Model', () {
    test('creates transaction with required fields', () {
      final txn = Transaction(accountId: 1, date: DateTime(2026, 1, 1));
      expect(txn.accountId, equals(1));
      expect(txn.debit, equals(0.0));
      expect(txn.credit, equals(0.0));
    });

    test('toMap converts debit/credit to cents', () {
      final txn = Transaction(
        accountId: 1, date: DateTime(2026, 1, 1),
        debit: 1000.0, credit: 0.0,
      );
      final map = txn.toMap();
      expect(map['debit'], equals(MoneyHelper.toCents(1000.0)));
      expect(map['credit'], equals(0));
    });

    test('fromMap reads cents correctly', () {
      final map = {
        'id': 1, 'account_id': 5, 'journal_id': 100,
        'debit': 100000, 'credit': 0,
        'description': 'Test', 'date': '2026-01-01',
        'created_at': '2026-01-01T00:00:00.000', 'balance_type': 'debit',
      };
      final txn = Transaction.fromMap(map);
      expect(txn.debit, closeTo(1000.0, 0.01));
      expect(txn.credit, equals(0.0));
    });

    test('round-trip preserves debit and credit', () {
      final original = Transaction(
        id: 1, accountId: 5, journalId: 100,
        debit: 1500.75, credit: 500.25,
        description: 'قيد', date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      final restored = Transaction.fromMap(original.toMap());
      expect(restored.debit, closeTo(original.debit, 0.01));
      expect(restored.credit, closeTo(original.credit, 0.01));
    });

    test('copyWith works correctly', () {
      final original = Transaction(accountId: 1, date: DateTime(2026, 1, 1), debit: 100.0);
      final modified = original.copyWith(debit: 200.0, credit: 50.0);
      expect(modified.debit, equals(200.0));
      expect(modified.credit, equals(50.0));
      expect(modified.accountId, equals(1)); // Unchanged
    });
  });

  group('Product Model', () {
    test('creates product with required fields', () {
      final product = Product(nameAr: 'قلم');
      expect(product.nameAr, equals('قلم'));
      expect(product.nameEn, equals(''));
      expect(product.costPrice, equals(0.0));
      expect(product.sellPrice, equals(0.0));
      expect(product.currentStock, equals(0.0));
      expect(product.trackStock, isTrue);
      expect(product.isActive, isTrue);
      expect(product.costingMethod, equals(CostingMethod.weightedAverage));
    });

    test('effectiveBaseUnitId falls back to unitId', () {
      final product1 = Product(nameAr: 'Test', baseUnitId: 10, unitId: 5);
      expect(product1.effectiveBaseUnitId, equals(10));

      final product2 = Product(nameAr: 'Test', unitId: 5);
      expect(product2.effectiveBaseUnitId, equals(5));

      final product3 = Product(nameAr: 'Test');
      expect(product3.effectiveBaseUnitId, isNull);
    });

    test('toMap converts monetary fields to cents', () {
      final product = Product(
        nameAr: 'قلم', costPrice: 50.0, sellPrice: 100.0,
        averageCost: 45.0, wholesalePrice: 80.0,
      );
      final map = product.toMap();
      expect(map['cost_price'], equals(MoneyHelper.toCents(50.0)));
      expect(map['sell_price'], equals(MoneyHelper.toCents(100.0)));
      expect(map['average_cost'], equals(MoneyHelper.toCents(45.0)));
      expect(map['wholesale_price'], equals(MoneyHelper.toCents(80.0)));
    });

    test('current_stock is NOT converted to cents (it is a quantity)', () {
      final product = Product(nameAr: 'قلم', currentStock: 150.5);
      final map = product.toMap();
      expect(map['current_stock'], equals(150.5)); // Not in cents!
    });

    test('toMap converts boolean fields to 0/1', () {
      final product = Product(
        nameAr: 'قلم', isActive: true, trackStock: true,
        isSellable: true, allowNegative: false, showInPos: true,
      );
      final map = product.toMap();
      expect(map['is_active'], equals(1));
      expect(map['track_stock'], equals(1));
      expect(map['is_sellable'], equals(1));
      expect(map['allow_negative'], equals(0));
      expect(map['show_in_pos'], equals(1));
    });

    test('toMap stores costingMethod value string', () {
      final fifo = Product(nameAr: 'Test', costingMethod: CostingMethod.fifo);
      expect(fifo.toMap()['costing_method'], equals('fifo'));

      final lifo = Product(nameAr: 'Test', costingMethod: CostingMethod.lifo);
      expect(lifo.toMap()['costing_method'], equals('lifo'));

      final wa = Product(nameAr: 'Test', costingMethod: CostingMethod.weightedAverage);
      expect(wa.toMap()['costing_method'], equals('weighted_average'));
    });

    test('fromMap reads cents correctly for monetary fields', () {
      final map = {
        'id': 1, 'item_code': 'P001', 'name_ar': 'قلم', 'name_en': 'Pen',
        'barcode': '12345', 'category_id': null, 'unit_id': null,
        'base_unit_id': null, 'purchase_unit_id': null, 'sale_unit_id': null,
        'supplier_id': null, 'group_id': null, 'description': null,
        'cost_price': 5000, // cents = 50.00
        'average_cost': 4500, // cents = 45.00
        'sell_price': 10000, // cents = 100.00
        'wholesale_price': 8000, 'special_wholesale_price': 0,
        'minimum_sale_price': 0,
        'tax_rate': 0.0, 'tax_inclusive': 0,
        'sales_account_id': null, 'purchase_account_id': null,
        'inventory_account_id': null, 'cogs_account_id': null,
        'vat_account_id': null,
        'current_stock': 150.5,
        'min_stock': 10.0,
        'warehouse_id': null,
        'expiry_date': null, 'expiry_tracking': 0,
        'track_stock': 1, 'weight': 0.0, 'notes': null,
        'include_in_reports': 1, 'is_active': 1, 'has_variants': 0,
        'is_sellable': 1, 'is_purchasable': 1, 'allow_negative': 0,
        'sell_retail': 1, 'show_in_pos': 1,
        'image_path': null, 'supplier_code': null,
        'currency': 'YER', 'costing_method': 'weighted_average',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-01-01T00:00:00.000',
      };
      final product = Product.fromMap(map);
      expect(product.costPrice, closeTo(50.0, 0.01));
      expect(product.averageCost, closeTo(45.0, 0.01));
      expect(product.sellPrice, closeTo(100.0, 0.01));
      expect(product.currentStock, equals(150.5)); // Quantity, not cents
      expect(product.costingMethod, equals(CostingMethod.weightedAverage));
    });

    test('round-trip preserves monetary values', () {
      final original = Product(
        id: 1, nameAr: 'قلم', nameEn: 'Pen',
        costPrice: 50.0, sellPrice: 100.0, averageCost: 45.0,
        currentStock: 150.5, currency: 'SAR',
        costingMethod: CostingMethod.fifo,
        createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1),
      );
      final restored = Product.fromMap(original.toMap());
      expect(restored.costPrice, closeTo(original.costPrice, 0.01));
      expect(restored.sellPrice, closeTo(original.sellPrice, 0.01));
      expect(restored.averageCost, closeTo(original.averageCost, 0.01));
      expect(restored.currentStock, equals(original.currentStock));
      expect(restored.currency, equals(original.currency));
      expect(restored.costingMethod, equals(CostingMethod.fifo));
    });
  });

  group('InvoiceItem Model', () {
    test('creates invoice item with required fields', () {
      final item = InvoiceItem(
        invoiceId: 'INV-001', productId: 1, productName: 'قلم',
      );
      expect(item.invoiceId, equals('INV-001'));
      expect(item.quantity, equals(1.0));
      expect(item.unitPrice, equals(0.0));
      expect(item.conversionFactor, equals(1.0));
    });

    test('toMap converts monetary fields to cents', () {
      final item = InvoiceItem(
        invoiceId: 'INV-001', productId: 1, productName: 'قلم',
        unitPrice: 50.0, totalPrice: 100.0, unitCost: 30.0,
      );
      final map = item.toMap();
      expect(map['unit_price'], equals(MoneyHelper.toCents(50.0)));
      expect(map['total_price'], equals(MoneyHelper.toCents(100.0)));
      expect(map['unit_cost'], equals(MoneyHelper.toCents(30.0)));
    });

    test('round-trip preserves values', () {
      final original = InvoiceItem(
        id: 1, invoiceId: 'INV-001', productId: 1, productName: 'قلم',
        quantity: 5.0, unitPrice: 50.0, totalPrice: 250.0,
        unitCost: 30.0, conversionFactor: 24.0, baseQuantity: 120.0,
      );
      final restored = InvoiceItem.fromMap(original.toMap());
      expect(restored.unitPrice, closeTo(original.unitPrice, 0.01));
      expect(restored.totalPrice, closeTo(original.totalPrice, 0.01));
      expect(restored.unitCost, closeTo(original.unitCost, 0.01));
      expect(restored.quantity, equals(original.quantity));
      expect(restored.conversionFactor, equals(original.conversionFactor));
      expect(restored.baseQuantity, equals(original.baseQuantity));
    });
  });

  group('InventoryCostLayer Model', () {
    test('creates cost layer correctly', () {
      final layer = InventoryCostLayer(
        productId: 1, quantityOriginal: 100.0,
        quantityRemaining: 80.0, unitCost: 50.0,
        acquisitionDate: DateTime(2026, 1, 1),
      );
      expect(layer.quantityOriginal, equals(100.0));
      expect(layer.quantityRemaining, equals(80.0));
      expect(layer.unitCost, equals(50.0));
      expect(layer.remainingValue, closeTo(4000.0, 0.01)); // 80 * 50
    });

    test('toMap converts unitCost to cents', () {
      final layer = InventoryCostLayer(
        productId: 1, quantityOriginal: 100.0,
        quantityRemaining: 80.0, unitCost: 50.75,
        acquisitionDate: DateTime(2026, 1, 1),
      );
      final map = layer.toMap();
      expect(map['unit_cost'], equals(MoneyHelper.toCents(50.75)));
    });

    test('round-trip preserves values', () {
      final original = InventoryCostLayer(
        id: 1, productId: 1, quantityOriginal: 100.0,
        quantityRemaining: 80.0, unitCost: 50.75,
        acquisitionDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      final restored = InventoryCostLayer.fromMap(original.toMap());
      expect(restored.unitCost, closeTo(original.unitCost, 0.01));
      expect(restored.quantityOriginal, equals(original.quantityOriginal));
      expect(restored.quantityRemaining, equals(original.quantityRemaining));
    });
  });

  group('CostingMethod Extension', () {
    test('value property returns correct strings', () {
      expect(CostingMethod.weightedAverage.value, equals('weighted_average'));
      expect(CostingMethod.fifo.value, equals('fifo'));
      expect(CostingMethod.lifo.value, equals('lifo'));
    });

    test('nameAr returns correct Arabic names', () {
      expect(CostingMethod.weightedAverage.nameAr, equals('متوسط مرجح'));
      expect(CostingMethod.fifo.nameAr, contains('FIFO'));
      expect(CostingMethod.lifo.nameAr, contains('LIFO'));
    });

    test('fromValue returns correct enum', () {
      expect(CostingMethodExt.fromValue('fifo'), equals(CostingMethod.fifo));
      expect(CostingMethodExt.fromValue('lifo'), equals(CostingMethod.lifo));
      expect(CostingMethodExt.fromValue('weighted_average'),
          equals(CostingMethod.weightedAverage));
      expect(CostingMethodExt.fromValue('unknown'),
          equals(CostingMethod.weightedAverage)); // Default
    });
  });
}
