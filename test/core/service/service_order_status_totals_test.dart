import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/service/service_order_status_policy.dart';
import 'package:firstpro/core/service/service_order_totals.dart';
import 'package:firstpro/data/models/service_order_line_model.dart';

void main() {
  group('ServiceOrderStatusPolicy', () {
    test('allows the normal repair lifecycle', () {
      expect(ServiceOrderStatusPolicy.canTransition('draft', 'received'), isTrue);
      expect(ServiceOrderStatusPolicy.canTransition('received', 'diagnosing'), isTrue);
      expect(ServiceOrderStatusPolicy.canTransition('diagnosing', 'in_progress'), isTrue);
      expect(ServiceOrderStatusPolicy.canTransition('in_progress', 'ready'), isTrue);
      expect(ServiceOrderStatusPolicy.canTransition('ready', 'delivered'), isTrue);
    });

    test('rejects transitions after delivery and posting cancelled orders', () {
      expect(ServiceOrderStatusPolicy.canTransition('delivered', 'draft'), isFalse);
      expect(ServiceOrderStatusPolicy.canTransition('cancelled', 'in_progress'), isFalse);
      expect(ServiceOrderStatusPolicy.canPost('cancelled'), isFalse);
      expect(ServiceOrderStatusPolicy.canPost('ready'), isTrue);
    });
  });

  group('ServiceOrderTotals', () {
    test('rebuilds subtotal and total from lines', () {
      final result = ServiceOrderTotals.calculate(
        lines: [
          ServiceOrderLine(
            serviceOrderId: 'SO-1',
            lineType: 'service',
            description: 'Screen repair',
            quantity: 1,
            unitPrice: 100.0,
            lineTotal: 100.0,
            taxAmount: 15.0,
          ),
          ServiceOrderLine(
            serviceOrderId: 'SO-1',
            lineType: 'part',
            description: 'Screen',
            quantity: 1,
            unitPrice: 250.0,
            lineTotal: 250.0,
            taxAmount: 37.5,
          ),
        ],
        discountAmount: 20.0,
        transportCharges: 10.0,
      );

      expect(result.subtotal, 350.0);
      expect(result.discountAmount, 20.0);
      expect(result.taxAmount, 52.5);
      expect(result.transportCharges, 10.0);
      expect(result.total, 392.5);
    });

    test('rejects a discount larger than the subtotal', () {
      expect(
        () => ServiceOrderTotals.calculate(
          lines: [
            ServiceOrderLine(
              serviceOrderId: 'SO-1',
              lineType: 'service',
              description: 'Diagnosis',
              quantity: 1,
              unitPrice: 50.0,
              lineTotal: 50.0,
            ),
          ],
          discountAmount: 51.0,
          transportCharges: 0.0,
        ),
        throwsArgumentError,
      );
    });
  });
}
