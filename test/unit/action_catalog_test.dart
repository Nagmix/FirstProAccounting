import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/dashboard/action_catalog.dart';

void main() {
  test('retail-like capabilities show sales, products, purchases and core actions', () {
    final visible = ActionCatalog.visibleActions({'sell', 'buy', 'stock'});
    final routes = visible.map((action) => action.route).toSet();

    expect(routes, contains(AppConstants.newSaleInvoice));
    expect(routes, contains(AppConstants.newPurchaseInvoice));
    expect(routes, contains(AppConstants.products));
    expect(routes, contains(AppConstants.reports));
    expect(routes, isNot(contains(AppConstants.serviceOrders)));
    expect(routes, isNot(contains(AppConstants.productionOrders)));
  });

  test('service and stock capabilities expose service and parts workflows', () {
    final visible = ActionCatalog.visibleActions({'service', 'stock'});
    final routes = visible.map((action) => action.route).toSet();

    expect(routes, contains(AppConstants.serviceOrders));
    expect(routes, contains(AppConstants.products));
    expect(routes, contains(AppConstants.settings));
  });

  test('primary actions are capped and routes are unique', () {
    final primary = ActionCatalog.prioritizedActions(
      {'sell', 'buy', 'stock', 'service', 'schedule', 'settle', 'transform'},
      limit: 6,
    );

    expect(primary, hasLength(6));
    expect(primary.map((action) => action.route).toSet(), hasLength(6));
  });
}
