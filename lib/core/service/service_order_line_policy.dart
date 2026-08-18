import 'package:firstpro/data/models/product_model.dart';

/// Central policy for deciding whether a service-order line can create
/// inventory and COGS movements.
class ServiceOrderLinePolicy {
  ServiceOrderLinePolicy._();

  static bool canAffectInventory({
    required String lineType,
    required ProductKind productKind,
    required bool trackStock,
  }) {
    switch (lineType) {
      case 'service':
        return false;
      case 'part':
        return trackStock && productKind.createsStockMovement;
      default:
        throw ArgumentError.value(
          lineType,
          'lineType',
          'نوع بند أمر الخدمة غير مدعوم',
        );
    }
  }
}
