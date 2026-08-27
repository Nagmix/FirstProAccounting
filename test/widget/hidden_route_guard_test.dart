import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/platform/feature_visibility_service.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/ui/navigation/app_router.dart';

void main() {
  testWidgets('hidden route offers enable or back instead of opening feature',
      (tester) async {
    final repository = _FakeCapabilityRepository();
    final service = FeatureVisibilityService(repository);
    await service.load();
    await locator.reset();
    locator.registerSingleton<FeatureVisibilityService>(service);
    addTearDown(locator.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AppRouter.push(context, AppConstants.serviceOrders),
            child: const Text('فتح الخدمة'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح الخدمة'));
    await tester.pumpAndSettle();

    expect(find.text('هذه الوظيفة مخفية حالياً'), findsOneWidget);
    expect(find.text('إظهار الوظيفة'), findsOneWidget);
    expect(find.text('رجوع'), findsOneWidget);

    await tester.tap(find.text('إظهار الوظيفة'));
    await tester.pumpAndSettle();

    expect(repository.lastSetCode, 'service');
    expect(repository.lastSetEnabled, isTrue);
  });

  testWidgets('named route table also guards a hidden route', (tester) async {
    final repository = _FakeCapabilityRepository();
    final service = FeatureVisibilityService(repository);
    await service.load();
    await locator.reset();
    locator.registerSingleton<FeatureVisibilityService>(service);
    addTearDown(locator.reset);

    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed(
              AppConstants.serviceOrders,
            ),
            child: const Text('فتح بالاسم'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح بالاسم'));
    await tester.pumpAndSettle();

    expect(find.text('هذه الوظيفة مخفية حالياً'), findsOneWidget);
    expect(find.text('إظهار الوظيفة'), findsOneWidget);
  });

  testWidgets('replace also guards a hidden route', (tester) async {
    final repository = _FakeCapabilityRepository();
    final service = FeatureVisibilityService(repository);
    await service.load();
    await locator.reset();
    locator.registerSingleton<FeatureVisibilityService>(service);
    addTearDown(locator.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AppRouter.replace(
              context,
              AppConstants.serviceOrders,
            ),
            child: const Text('استبدال الخدمة'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('استبدال الخدمة'));
    await tester.pumpAndSettle();

    expect(find.text('هذه الوظيفة مخفية حالياً'), findsOneWidget);
    expect(find.text('إظهار الوظيفة'), findsOneWidget);
  });
}

class _FakeCapabilityRepository extends CapabilityRepository {
  String? lastSetCode;
  bool? lastSetEnabled;

  _FakeCapabilityRepository() : super(DatabaseHelper());

  @override
  Future<Set<String>> getEnabledCodes() async => <String>{};

  @override
  Future<void> setEnabled(
    String code,
    bool enabled, {
    required String source,
  }) async {
    lastSetCode = code;
    lastSetEnabled = enabled;
  }
}
