import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/production_order_model.dart';
import 'package:firstpro/ui/screens/production/production_orders_screen.dart';

void main() {
  testWidgets('rejects non-positive production quantity before service call',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProductionOrdersScreen(
          onCreateDraft: (_) async => calls++,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('recipe-id')), '12');
    await tester.enterText(find.byKey(const Key('output-product-id')), '7');
    await tester.enterText(find.byKey(const Key('planned-quantity')), '0');
    await tester.tap(find.byKey(const Key('create-production-draft')));
    await tester.pump();

    expect(find.text('أدخل كمية إنتاج أكبر من صفر'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('creates a draft and enables safe posting action', (tester) async {
    ProductionOrder? captured;
    var postedOrderId = '';
    await tester.pumpWidget(
      MaterialApp(
        home: ProductionOrdersScreen(
          onCreateDraft: (order) async => captured = order,
          onPostProduction: (orderId) async => postedOrderId = orderId,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('recipe-id')), '12');
    await tester.enterText(find.byKey(const Key('output-product-id')), '7');
    await tester.enterText(find.byKey(const Key('planned-quantity')), '24');
    await tester.tap(find.byKey(const Key('create-production-draft')));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.recipeId, 12);
    expect(captured!.outputProductId, 7);
    expect(captured!.plannedQuantity, 24);
    expect(find.textContaining('تم إنشاء مسودة أمر الإنتاج'), findsOneWidget);
    expect(find.byKey(const Key('post-production')), findsOneWidget);

    final postButton = find.byKey(const Key('post-production'));
    await tester.scrollUntilVisible(
      postButton,
      500,
      scrollable: find.byType(ListView),
    );
    await tester.tap(postButton);
    await tester.pumpAndSettle();
    expect(postedOrderId, captured!.id);
  });
}
