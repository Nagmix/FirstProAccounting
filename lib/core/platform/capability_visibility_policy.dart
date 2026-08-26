import 'capability_catalog.dart';

class CapabilityVisibilityPolicy {
  CapabilityVisibilityPolicy._();

  static Set<String> visibleCodes(Iterable<String> enabledCodes) {
    final resolved = CapabilityCatalog.resolveDependencies(enabledCodes);
    resolved.addAll(
      CapabilityCatalog.definitions
          .where((definition) => definition.isCore)
          .map((definition) => definition.code),
    );
    return resolved;
  }

  static bool isVisible(
    String capabilityCode,
    Set<String> enabledCodes, {
    String? contextCapability,
  }) {
    CapabilityCatalog.byCode(capabilityCode);
    if (contextCapability != null) {
      CapabilityCatalog.byCode(contextCapability);
    }

    final visible = visibleCodes(enabledCodes);
    return visible.contains(capabilityCode) ||
        capabilityCode == contextCapability;
  }
}
