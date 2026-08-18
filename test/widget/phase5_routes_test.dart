import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/navigation/app_router.dart';
import 'package:firstpro/ui/screens/inventory_adjustments/inventory_adjustment_screen.dart';
import 'package:firstpro/ui/screens/production/production_orders_screen.dart';

void main() {
  test('registers production and inventory adjustment routes', () {
    final production = AppRouter.routes[AppConstants.productionOrders];
    final inventory = AppRouter.routes[AppConstants.inventoryAdjustments];

    expect(production, isNotNull);
    expect(inventory, isNotNull);
    expect(production!(const _BuildContextStub()), isA<ProductionOrdersScreen>());
    expect(inventory!(const _BuildContextStub()), isA<InventoryAdjustmentScreen>());
  });
}

class _BuildContextStub implements BuildContext {
  const _BuildContextStub();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
