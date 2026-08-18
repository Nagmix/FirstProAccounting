import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/transaction_model.dart';

void main() {
  test('serializes monetary values as integer minor units with audit metadata', () {
    final transaction = Transaction(
      accountId: 7,
      journalId: 19,
      debit: 12.34,
      credit: 0,
      date: DateTime.utc(2026, 1, 1),
      currencyCode: 'USD',
      exchangeRate: 530.0,
      amountBase: 6540.20,
      referenceType: 'invoice',
      referenceId: '42',
    );

    final map = transaction.toMap();

    expect(map['debit'], 1234);
    expect(map['credit'], 0);
    expect(map['amount_base'], 654020);
    expect(map['currency_code'], 'USD');
    expect(map['exchange_rate'], 530.0);
    expect(map['reference_type'], 'invoice');
    expect(map['reference_id'], '42');
  });
}
