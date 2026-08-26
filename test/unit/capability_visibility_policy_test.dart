import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/capability_visibility_policy.dart';

void main() {
  test('visible codes include selected capabilities, dependencies, and core tools', () {
    final visible = CapabilityVisibilityPolicy.visibleCodes({'sell'});

    expect(visible, containsAll({'sell', 'settle'}));
    expect(visible, containsAll({'backup', 'settings', 'audit'}));
    expect(visible, isNot(contains('service')));
    expect(visible, isNot(contains('transform')));
  });

  test('unknown capability codes are rejected instead of silently shown', () {
    expect(
      () => CapabilityVisibilityPolicy.visibleCodes({'not-a-capability'}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('contextual visibility is explicit and never deletes a hidden capability', () {
    final active = {'sell', 'settle'};

    expect(
      CapabilityVisibilityPolicy.isVisible('service', active),
      isFalse,
    );
    expect(
      CapabilityVisibilityPolicy.isVisible(
        'service',
        active,
        contextCapability: 'service',
      ),
      isTrue,
    );
    expect(active, isNot(contains('service')));
  });
}
