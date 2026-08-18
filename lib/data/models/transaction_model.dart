import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/finance/currency_engine.dart';

class Transaction {
  final int? id;
  final int accountId;
  final int? journalId;
  final double debit;
  final double credit;
  final String? description;
  final DateTime date;
  final DateTime createdAt;
  final String? balanceType;
  final String currencyCode;
  final double exchangeRate;
  final double? amountBase;
  final String? referenceType;
  final String? referenceId;

  Transaction({
    this.id,
    required this.accountId,
    this.journalId,
    this.debit = 0.0,
    this.credit = 0.0,
    this.description,
    required this.date,
    DateTime? createdAt,
    this.balanceType,
    this.currencyCode = 'YER',
    this.exchangeRate = 1.0,
    this.amountBase,
    this.referenceType,
    this.referenceId,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    final lineAmount = debit != 0.0 ? debit : credit;
    final lineAmountMinorUnits = MoneyHelper.toCents(lineAmount);
    final resolvedAmountBaseMinorUnits = amountBase != null
        ? MoneyHelper.toCents(amountBase!)
        : (currencyCode == 'YER'
            ? lineAmountMinorUnits
            : const CurrencyEngine().convertMinorUnits(
                amountMinorUnits: lineAmountMinorUnits,
                exchangeRateMicros: CurrencyEngine.rateToMicros(exchangeRate),
              ));

    return {
      'id': id,
      'account_id': accountId,
      'journal_id': journalId,
      'debit': MoneyHelper.toCents(debit),
      'credit': MoneyHelper.toCents(credit),
      'description': description,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'balance_type': balanceType,
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'amount_base': resolvedAmountBaseMinorUnits,
      'reference_type': referenceType,
      'reference_id': referenceId,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    final rawRate = map['exchange_rate'];
    return Transaction(
      id: map['id'] as int?,
      accountId: map['account_id'] as int,
      journalId: map['journal_id'] as int?,
      debit: MoneyHelper.readMoney(map['debit']),
      credit: MoneyHelper.readMoney(map['credit']),
      description: map['description'] as String?,
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      balanceType: map['balance_type'] as String?,
      currencyCode: map['currency_code'] as String? ?? 'YER',
      exchangeRate: rawRate is num ? rawRate.toDouble() : 1.0,
      amountBase: map.containsKey('amount_base')
          ? MoneyHelper.readMoney(map['amount_base'])
          : null,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id']?.toString(),
    );
  }

  Transaction copyWith({
    int? id,
    int? accountId,
    int? journalId,
    double? debit,
    double? credit,
    String? description,
    DateTime? date,
    DateTime? createdAt,
    String? balanceType,
    String? currencyCode,
    double? exchangeRate,
    double? amountBase,
    String? referenceType,
    String? referenceId,
  }) {
    return Transaction(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      journalId: journalId ?? this.journalId,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      description: description ?? this.description,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      balanceType: balanceType ?? this.balanceType,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      amountBase: amountBase ?? this.amountBase,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
    );
  }
}
