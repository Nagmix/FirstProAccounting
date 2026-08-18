import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/product_model.dart';

void main() {
  test('service and non-stock products do not create stock movements', () {
    expect(ProductKind.service.createsStockMovement, isFalse);
    expect(ProductKind.nonStock.createsStockMovement, isFalse);
  });

  test('stock and bundle products create stock movements', () {
    expect(ProductKind.stock.createsStockMovement, isTrue);
    expect(ProductKind.bundle.createsStockMovement, isTrue);
  });

  test('unknown persisted product kind remains stock-compatible', () {
    expect(ProductKind.fromValue('unknown'), ProductKind.stock);
    expect(ProductKind.fromValue(null), ProductKind.stock);
  });
}
