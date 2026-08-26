import 'package:flutter/material.dart';

class ActionDefinition {
  final String key;
  final String labelAr;
  final IconData icon;
  final String route;
  final Set<String> requiredCapabilities;
  final int priority;
  final bool isCore;
  final Color color;
  final Color backgroundColor;

  const ActionDefinition({
    required this.key,
    required this.labelAr,
    required this.icon,
    required this.route,
    this.requiredCapabilities = const <String>{},
    required this.priority,
    this.isCore = false,
    required this.color,
    required this.backgroundColor,
  });
}
