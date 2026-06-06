import 'package:flutter_test/flutter_test.dart';

import 'package:firstpro/main.dart';
import 'package:firstpro/core/di/service_locator.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Ensure GetIt is reset before each test to avoid conflicts
    await locator.reset();

    // Build the app - setupLocator is called in main()
    await tester.pumpWidget(const FirstProApp());

    // Allow time for async initialization
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // The app should render without throwing an exception.
    // We don't check for specific text because the app may show
    // a splash screen, license screen, or main dashboard depending
    // on initialization state. The key is that it doesn't crash.
    expect(find.byType(FirstProApp), findsOneWidget);
  });
}
