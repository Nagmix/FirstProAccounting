import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/navigation/app_router.dart';
import 'package:firstpro/ui/screens/service_orders/service_orders_screen.dart';

void main() {
  test('registers the service orders route with the service orders screen', () {
    final builder = AppRouter.routes[AppConstants.serviceOrders];

    expect(builder, isNotNull);
    final widget = builder!(const BuildContextStub());
    expect(widget, isA<ServiceOrdersScreen>());
  });
}

/// A minimal context value for invoking a WidgetBuilder without mounting.
class BuildContextStub implements BuildContext {
  const BuildContextStub();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
