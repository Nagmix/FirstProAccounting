import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/navigation/navigation_catalog.dart';

void main() {
  test('visible navigation maps operational routes to selected capabilities', () {
    final visible = NavigationCatalog.visibleCodes(<String>{'sell'});
    final routes = visible.map((definition) => definition.route).toSet();

    expect(routes, contains(AppConstants.newSaleInvoice));
    expect(routes, contains(AppConstants.settings));
    expect(routes, contains(AppConstants.reports));
    expect(routes, isNot(contains(AppConstants.serviceOrders)));
    expect(routes, isNot(contains(AppConstants.productionOrders)));
  });

  test('stock selection exposes products and warehouse operations without service', () {
    final visible = NavigationCatalog.visibleCodes(<String>{'stock'});
    final routes = visible.map((definition) => definition.route).toSet();

    expect(routes, contains(AppConstants.products));
    expect(routes, contains(AppConstants.warehouses));
    expect(routes, contains(AppConstants.inventoryAdjustments));
    expect(routes, isNot(contains(AppConstants.serviceOrders)));
  });

  test('navigation definitions have unique routes and explicit capability metadata', () {
    final routes = NavigationCatalog.definitions.map((definition) => definition.route);

    expect(routes.length, routes.toSet().length);
    expect(
      NavigationCatalog.byRoute(AppConstants.settings).isCore,
      isTrue,
    );
    expect(
      NavigationCatalog.byRoute(AppConstants.newSaleInvoice)
          .requiredCapabilities,
      contains('sell'),
    );
  });
}
