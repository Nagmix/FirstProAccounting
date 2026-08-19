import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment and cancellation resolve currency offset before transaction', () {
    final source = File(
      'lib/data/datasources/repositories/invoice_repository.dart',
    ).readAsStringSync();

    for (final methodName in ['recordInvoicePayment', 'cancelInvoice']) {
      final methodStart = source.indexOf('Future<void> $methodName');
      expect(methodStart, greaterThanOrEqualTo(0), reason: methodName);

      final nextMethod = source.indexOf('\n  Future<', methodStart + 1);
      final methodEnd = nextMethod == -1 ? source.length : nextMethod;
      final methodSource = source.substring(methodStart, methodEnd);

      final transactionIndex = methodSource.indexOf('await db.transaction');
      final offsetIndex = methodSource.indexOf(
        'getOffsetForCurrency(invoiceCurrency)',
      );

      expect(transactionIndex, greaterThanOrEqualTo(0), reason: methodName);
      expect(offsetIndex, greaterThanOrEqualTo(0), reason: methodName);
      expect(
        offsetIndex,
        lessThan(transactionIndex),
        reason: '$methodName must resolve currency outside its transaction',
      );
    }
  });
}
