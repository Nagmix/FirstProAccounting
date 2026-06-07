import 'package:flutter/material.dart';

/// Shared avatar color logic used across all entity list screens.
///
/// Previously, [_avatarColors] and [_avatarColor()] were duplicated
/// in 6+ screen files. This class provides a single source of truth.
class AvatarHelper {
  AvatarHelper._();

  /// Color palette for avatar backgrounds.
  static const List<Color> avatarColors = [
    Color(0xFF1A237E),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1B5E20),
    Color(0xFF33691E),
  ];

  /// Returns a deterministic avatar color based on the entity name.
  static Color avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return avatarColors[hash % avatarColors.length];
  }

  /// Returns the first letter of a name for avatar display.
  static String avatarLetter(String name) {
    return name.isNotEmpty ? name[0] : '?';
  }
}
