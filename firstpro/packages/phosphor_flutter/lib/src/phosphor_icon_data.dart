library phosphor_flutter;

import 'package:flutter/widgets.dart';

/// Compatibility layer for Flutter 3.44+ where IconData is final.
/// PhosphorIconData is now just an alias for IconData.
typedef PhosphorIconData = IconData;

/// PhosphorFlatIconData is now just an alias for IconData.
typedef PhosphorFlatIconData = IconData;

/// Duotone icon data - since we can't extend IconData, we use a wrapper.
class PhosphorDuotoneIconData {
  const PhosphorDuotoneIconData(int codePoint, this.secondary)
      : primary = IconData(
          codePoint,
          fontFamily: 'PhosphorDuotone',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        );

  final IconData primary;
  final IconData secondary;

  /// Allow using in Icon widget directly (uses primary icon)
  IconData get iconData => primary;
}
