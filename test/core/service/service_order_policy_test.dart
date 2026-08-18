import 'package:firstpro/core/service/service_order_line_policy.dart';
import 'package:firstpro/data/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceOrderLinePolicy', () {
    test('service line never affects inventory', () {
      expect(
        ServiceOrderLinePolicy.canAffectInventory(
          lineType: 'service',
          productKind: ProductKind.stock,
          trackStock: true,
        ),
        isFalse,
      );
    });

    test('non-stock product cannot affect inventory as a part', () {
      expect(
        ServiceOrderLinePolicy.canAffectInventory(
          lineType: 'part',
          productKind: ProductKind.nonStock,
          trackStock: true,
        ),
        isFalse,
      );
    });

    test('tracked stock and bundle parts affect inventory', () {
      for (final kind in [ProductKind.stock, ProductKind.bundle]) {
        expect(
          ServiceOrderLinePolicy.canAffectInventory(
            lineType: 'part',
            productKind: kind,
            trackStock: true,
          ),
          isTrue,
        );
      }
    });

    test('untracked stock part does not affect inventory', () {
      expect(
        ServiceOrderLinePolicy.canAffectInventory(
          lineType: 'part',
          productKind: ProductKind.stock,
          trackStock: false,
        ),
        isFalse,
      );
    });

    test('unknown line type is rejected', () {
      expect(
        () => ServiceOrderLinePolicy.canAffectInventory(
          lineType: 'unknown',
          productKind: ProductKind.stock,
          trackStock: true,
        ),
        throwsArgumentError,
      );
    });
  });
}
