import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/invoice_model.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Invoice Model Unit Tests
/// Tests the Invoice domain model including:
/// - Construction and defaults
/// - effectiveType logic (sale, purchase, returns)
/// - toMap/fromMap serialization with cents conversion
/// - copyWith functionality
void main() {
  group('Invoice Model', () {
    group('construction', () {
      test('creates invoice with required fields', () {
        final invoice = Invoice(id: 'INV-001', type: 'sale');
        expect(invoice.id, equals('INV-001'));
        expect(invoice.type, equals('sale'));
        expect(invoice.paymentMechanism, equals('cash'));
        expect(invoice.paymentMethod, equals('cash'));
        expect(invoice.isReturn, isFalse);
        expect(invoice.status, equals('pending'));
        expect(invoice.currency, equals('YER'));
        expect(invoice.isPosted, isFalse);
      });

      test('creates credit invoice', () {
        final invoice = Invoice(
          id: 'INV-002',
          type: 'sale',
          paymentMechanism: 'credit',
        );
        expect(invoice.paymentMechanism, equals('credit'));
      });

      test('creates purchase invoice', () {
        final invoice = Invoice(
          id: 'INV-003',
          type: 'purchase',
          supplierId: 5,
        );
        expect(invoice.type, equals('purchase'));
        expect(invoice.supplierId, equals(5));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  effectiveType — Invoice type resolution
    // ═══════════════════════════════════════════════════════════
    group('effectiveType', () {
      test('sale invoice returns sale', () {
        final invoice = Invoice(id: 'INV-001', type: 'sale');
        expect(invoice.effectiveType, equals('sale'));
      });

      test('purchase invoice returns purchase', () {
        final invoice = Invoice(id: 'INV-001', type: 'purchase');
        expect(invoice.effectiveType, equals('purchase'));
      });

      test('sale return returns sale_return', () {
        final invoice = Invoice(id: 'INV-001', type: 'sale', isReturn: true);
        expect(invoice.effectiveType, equals('sale_return'));
      });

      test('purchase return returns purchase_return', () {
        final invoice =
            Invoice(id: 'INV-001', type: 'purchase', isReturn: true);
        expect(invoice.effectiveType, equals('purchase_return'));
      });

      test('non-return sale with isReturn=false returns sale', () {
        final invoice = Invoice(id: 'INV-001', type: 'sale', isReturn: false);
        expect(invoice.effectiveType, equals('sale'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Serialization
    // ═══════════════════════════════════════════════════════════
    group('serialization', () {
      test('toMap returns human-readable doubles', () {
        final invoice = Invoice(
          id: 'INV-001',
          type: 'sale',
          subtotal: 1000.0,
          discountAmount: 50.0,
          taxAmount: 45.0,
          total: 995.0,
          paidAmount: 995.0,
          remaining: 0.0,
          transportCharges: 25.0,
        );
        final map = invoice.toMap();
        expect(map['subtotal'], equals(1000.0));
        expect(map['discount_amount'], equals(50.0));
        expect(map['tax_amount'], equals(45.0));
        expect(map['total'], equals(995.0));
        expect(map['paid_amount'], equals(995.0));
        expect(map['remaining'], equals(0.0));
        expect(map['transport_charges'], equals(25.0));
      });

      test('toMap converts boolean fields to 0/1', () {
        final returnInvoice = Invoice(
            id: 'INV-001', type: 'sale', isReturn: true, isPosted: true);
        final map = returnInvoice.toMap();
        expect(map['is_return'], equals(1));
        expect(map['is_posted'], equals(1));
      });

      test('toMap preserves discount_rate as-is (not monetary)', () {
        final invoice = Invoice(id: 'INV-001', type: 'sale', discountRate: 5.0);
        final map = invoice.toMap();
        expect(map['discount_rate'], equals(5.0)); // Not converted to cents
      });

      test('fromMap reads cents as double correctly', () {
        final map = {
          'id': 'INV-001',
          'type': 'sale',
          'payment_mechanism': 'cash',
          'payment_method': 'cash',
          'is_return': 0,
          'cash_box_id': null,
          'customer_id': 1,
          'supplier_id': null,
          'subtotal': 100000, // cents = 1000.00
          'discount_rate': 0.0,
          'discount_amount': 5000, // cents = 50.00
          'tax_amount': 4500, // cents = 45.00
          'total': 99500, // cents = 995.00
          'paid_amount': 99500,
          'remaining': 0,
          'status': 'paid',
          'cashier_id': null,
          'warehouse_id': null,
          'notes': null,
          'currency': 'YER',
          'exchange_rate': 1.0,
          'transport_charges': 2500, // cents = 25.00
          'ewallet_provider': null,
          'bank_transfer_provider': null,
          'transfer_number': null,
          'attachment_path': null,
          'shift_id': null,
          'cashier_name': null,
          'is_posted': 1,
          'original_invoice_id': null,
          'created_at': '2026-01-01T00:00:00.000',
        };
        final invoice = Invoice.fromMap(map);
        expect(invoice.subtotal, closeTo(1000.0, 0.01));
        expect(invoice.discountAmount, closeTo(50.0, 0.01));
        expect(invoice.taxAmount, closeTo(45.0, 0.01));
        expect(invoice.total, closeTo(995.0, 0.01));
        expect(invoice.paidAmount, closeTo(995.0, 0.01));
        expect(invoice.transportCharges, closeTo(25.0, 0.01));
        expect(invoice.isPosted, isTrue);
        expect(invoice.status, equals('paid'));
      });

      test('round-trip via toCentsMap preserves monetary values', () {
        final original = Invoice(
          id: 'INV-001',
          type: 'sale',
          customerId: 1,
          subtotal: 1000.0,
          discountAmount: 50.0,
          taxAmount: 45.0,
          total: 995.0,
          paidAmount: 995.0,
          remaining: 0.0,
          transportCharges: 25.0,
          currency: 'SAR',
          isPosted: true,
          createdAt: DateTime(2026, 1, 1),
        );
        final dbMap = MoneyHelper.toCentsMap(original.toMap(), MoneyHelper.invoiceMoneyFields);
        final restored = Invoice.fromMap(dbMap);
        expect(restored.subtotal, closeTo(original.subtotal, 0.01));
        expect(restored.discountAmount, closeTo(original.discountAmount, 0.01));
        expect(restored.taxAmount, closeTo(original.taxAmount, 0.01));
        expect(restored.total, closeTo(original.total, 0.01));
        expect(restored.paidAmount, closeTo(original.paidAmount, 0.01));
        expect(restored.transportCharges,
            closeTo(original.transportCharges, 0.01));
        expect(restored.currency, equals(original.currency));
        expect(restored.isPosted, equals(original.isPosted));
      });
    });

    group('copyWith', () {
      test('copies with changed fields', () {
        final original = Invoice(id: 'INV-001', type: 'sale', total: 1000.0);
        final modified = original.copyWith(total: 2000.0, status: 'paid');
        expect(modified.total, equals(2000.0));
        expect(modified.status, equals('paid'));
        expect(modified.type, equals('sale')); // Unchanged
        expect(modified.id, equals('INV-001')); // Unchanged
      });
    });
  });
}
