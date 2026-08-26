import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/feature_visibility_service.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:firstpro/ui/screens/settings/business_capabilities_screen.dart';

void main() {
  testWidgets('capability settings presents Arabic choices and persists toggles',
      (tester) async {
    final repository = _FakeCapabilityRepository(enabled: <String>{'sell'});
    final service = FeatureVisibilityService(repository);

    await service.load();
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessCapabilitiesScreen(service: service),
      ),
    );
    await tester.pump();

    expect(find.text('الوظائف التي تديرها'), findsOneWidget);
    expect(find.text('البيع'), findsOneWidget);
    expect(find.text('الخدمات أو الطلبات'), findsOneWidget);
    expect(find.text('إخفاء الوظيفة لا يحذف بياناتها أو مستنداتها السابقة.'),
        findsOneWidget);

    final serviceSwitch = find.byType(SwitchListTile).at(3);
    await tester.tap(serviceSwitch);
    await tester.pump();

    expect(repository.lastSetCode, 'service');
    expect(repository.lastSetEnabled, isTrue);
  });
}

class _FakeCapabilityRepository extends CapabilityRepository {
  Set<String> enabled;
  String? lastSetCode;
  bool? lastSetEnabled;

  _FakeCapabilityRepository({required this.enabled}) : super(DatabaseHelper());

  @override
  Future<Set<String>> getEnabledCodes() async => enabled;

  @override
  Future<void> setEnabled(
    String code,
    bool enabled, {
    required String source,
  }) async {
    lastSetCode = code;
    lastSetEnabled = enabled;
    this.enabled = {...this.enabled, if (enabled) code};
  }
}
