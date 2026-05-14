import 'package:flutter_test/flutter_test.dart';

import 'package:firstpro/main.dart';

void main() {
  testWidgets('App renders dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const FirstProApp());

    // Verify the app name appears
    expect(find.text('الأول برو'), findsWidgets);
  });
}
