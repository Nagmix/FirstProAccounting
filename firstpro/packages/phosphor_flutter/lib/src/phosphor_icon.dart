library phosphor_flutter;

import 'package:flutter/material.dart';

class PhosphorIcon extends Icon {
  const PhosphorIcon(
    IconData icon, {
    super.key,
    double? size,
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
    String? semanticLabel,
    TextDirection? textDirection,
  }) : super(
          icon,
          color: color,
          fill: fill,
          grade: grade,
          opticalSize: opticalSize,
          semanticLabel: semanticLabel,
          shadows: shadows,
          size: size,
          textDirection: textDirection,
          weight: weight,
        );

  @override
  Widget build(BuildContext context) {
    return super.build(context);
  }
}
