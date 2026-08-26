import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/core/platform/feature_visibility_service.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';

void main() {
  test('core features remain visible while disabled operational features hide',
      () async {
    final repository = _FakeCapabilityRepository(enabled: <String>{'sell'});
    final service = FeatureVisibilityService(repository);

    await service.load();

    expect(service.isVisible(<String>{}, isCore: true), isTrue);
    expect(service.isVisible(<String>{'sell'}, isCore: false), isTrue);
    expect(service.isVisible(<String>{'service'}, isCore: false), isFalse);
  });

  test('enabling a capability persists the requested dependency-aware state',
      () async {
    final repository = _FakeCapabilityRepository();
    final service = FeatureVisibilityService(repository);

    await service.load();
    await service.setEnabled('transform', true);

    expect(repository.lastSetCode, 'transform');
    expect(repository.lastSetEnabled, isTrue);
    expect(service.isVisible(<String>{'stock'}, isCore: false), isTrue);
  });

  test('core capabilities cannot be disabled and enabled dependents block disable',
      () async {
    final repository = _FakeCapabilityRepository(
      enabled: <String>{'transform'},
    );
    final service = FeatureVisibilityService(repository);
    await service.load();

    expect(service.canDisable('backup'), isFalse);
    expect(service.canDisable('stock'), isFalse);
    expect(service.canDisable('sell'), isTrue);
  });
}

class _FakeCapabilityRepository extends CapabilityRepository {
  Set<String> enabled;
  String? lastSetCode;
  bool? lastSetEnabled;

  _FakeCapabilityRepository({Set<String>? enabled})
      : enabled = enabled ?? <String>{},
        super(DatabaseHelper());

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
    if (enabled) {
      this.enabled = {...this.enabled, ...CapabilityCatalog.resolveDependencies(<String>{code})};
    } else {
      this.enabled = {...this.enabled}..remove(code);
    }
  }
}
