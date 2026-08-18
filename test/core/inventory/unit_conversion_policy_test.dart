import 'package:flutter_test/flutter_test.dart';

import 'package:firstpro/core/inventory/unit_conversion_policy.dart';

void main() {
  test('يحوّل كمية وحدة البيع إلى كمية الوحدة الأساسية بدقة', () {
    expect(
      UnitConversionPolicy.toBaseQuantity(quantity: 3, factor: 12),
      36,
    );
  });

  test('يرفض كمية أو عامل تحويل غير موجب أو غير منته', () {
    expect(
      () => UnitConversionPolicy.toBaseQuantity(quantity: 0, factor: 12),
      throwsArgumentError,
    );
    expect(
      () => UnitConversionPolicy.toBaseQuantity(quantity: 1, factor: 0),
      throwsArgumentError,
    );
    expect(
      () => UnitConversionPolicy.validateFactor(double.infinity),
      throwsArgumentError,
    );
  });

  test('يرفض التحويل الذاتي والدورة في شبكة الوحدات', () {
    expect(
      () => UnitConversionPolicy.validateEdge(fromUnitId: 1, toUnitId: 1, factor: 1),
      throwsArgumentError,
    );
    expect(
      () => UnitConversionPolicy.validateNoCycles([
        UnitConversionEdge(fromUnitId: 1, toUnitId: 2, factor: 12),
        UnitConversionEdge(fromUnitId: 2, toUnitId: 3, factor: 10),
        UnitConversionEdge(fromUnitId: 3, toUnitId: 1, factor: 1 / 120),
      ]),
      throwsArgumentError,
    );
  });
}
