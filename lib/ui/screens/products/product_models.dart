import 'package:flutter/material.dart';

/// Data models for the product form (shared between main sheet and step widgets).

class UnitConversionRow {
  int? unitId;
  double factor;
  String barcode;
  double sellPrice;
  double costPrice;

  UnitConversionRow({
    this.unitId,
    this.factor = 1.0,
    this.barcode = '',
    this.sellPrice = 0.0,
    this.costPrice = 0.0,
  });
}

class StepDef {
  final String title;
  final IconData icon;
  const StepDef(this.title, this.icon);
}
