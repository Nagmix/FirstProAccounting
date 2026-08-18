import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/services/inventory_adjustment_service.dart';
import 'package:firstpro/ui/screens/inventory_adjustments/inventory_adjustment_screen.dart';

void main() {
  testWidgets('rejects negative counted quantity before creating a draft',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryAdjustmentScreen(
          onCreateDraft: (_) async {
            calls++;
            return 1;
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('voucher-number')), 'INV-1');
    await tester.enterText(find.byKey(const Key('product-id')), '7');
    await tester.enterText(find.byKey(const Key('actual-quantity')), '-2');
    await tester.enterText(find.byKey(const Key('unit-cost')), '100');
    final createButton = find.byKey(const Key('create-inventory-draft'));
    await tester.scrollUntilVisible(createButton, 500);
    await tester.tap(createButton);
    await tester.pump();

    expect(find.text('الكمية الفعلية لا يمكن أن تكون سالبة'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('converts counted sales units once and confirms the draft',
      (tester) async {
    InventoryAdjustmentDraft? captured;
    var confirmedId = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryAdjustmentScreen(
          onCreateDraft: (draft) async {
            captured = draft;
            return 42;
          },
          onConfirm: (id) async => confirmedId = id,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('voucher-number')), 'INV-2');
    await tester.enterText(find.byKey(const Key('product-id')), '7');
    await tester.enterText(find.byKey(const Key('actual-quantity')), '3');
    await tester.enterText(find.byKey(const Key('conversion-factor')), '12');
    await tester.enterText(find.byKey(const Key('unit-cost')), '100');
    final createButton = find.byKey(const Key('create-inventory-draft'));
    await tester.scrollUntilVisible(createButton, 500);
    await tester.tap(createButton);
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.lines.single.actualQuantity, 3);
    expect(captured!.lines.single.conversionFactor, 12);
    expect(find.textContaining('تم إنشاء مسودة تسوية الجرد'), findsOneWidget);
    expect(find.byKey(const Key('confirm-inventory-adjustment')), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-inventory-adjustment')));
    await tester.pumpAndSettle();
    expect(confirmedId, 42);
  });
}
