class CapabilityDefinition {
  final String code;
  final String labelAr;
  final String descriptionAr;
  final Set<String> dependencies;
  final bool isCore;
  final int priority;

  const CapabilityDefinition({
    required this.code,
    required this.labelAr,
    required this.descriptionAr,
    this.dependencies = const <String>{},
    this.isCore = false,
    this.priority = 100,
  });
}
