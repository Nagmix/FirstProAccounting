import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/dashboard/action_catalog.dart';
import 'package:firstpro/ui/dashboard/dashboard_actions_panel.dart';

void main() {
  testWidgets('dashboard renders only actions enabled by capabilities',
      (tester) async {
    final actions = ActionCatalog.prioritizedActions({'sell', 'stock'}, limit: 6);
    final tappedRoutes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardActionsPanel(
            actions: actions,
            onAction: tappedRoutes.add,
          ),
        ),
      ),
    );

    expect(find.text('فاتورة بيع'), findsOneWidget);
    expect(find.text('المنتجات'), findsOneWidget);
    expect(find.text('الخدمات والطلبات'), findsNothing);
    expect(find.text('الإنتاج والوصفات'), findsNothing);

    await tester.tap(find.text('فاتورة بيع'));
    expect(tappedRoutes, contains(AppConstants.newSaleInvoice));
  });

  testWidgets('dashboard action panel stays usable with one action',
      (tester) async {
    final actions = ActionCatalog.prioritizedActions({'service'}, limit: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardActionsPanel(actions: actions, onAction: (_) {}),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('الخدمات والطلبات'), findsOneWidget);
  });
}
