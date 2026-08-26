import 'package:flutter/material.dart';

class NavigationDefinition {
  final String route;
  final String labelAr;
  final IconData icon;
  final Set<String> requiredCapabilities;
  final bool isCore;
  final int priority;

  const NavigationDefinition({
    required this.route,
    required this.labelAr,
    required this.icon,
    this.requiredCapabilities = const <String>{},
    this.isCore = false,
    required this.priority,
  });
}
