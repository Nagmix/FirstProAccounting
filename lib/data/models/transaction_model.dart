import 'package:firstpro/core/utils/money_helper.dart';

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
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
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
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      accountId: map['account_id'],
      journalId: map['journal_id'],
      debit: MoneyHelper.readMoney(map['debit']),
      credit: MoneyHelper.readMoney(map['credit']),
      description: map['description'],
      date: DateTime.parse(map['date']),
      createdAt: DateTime.parse(map['created_at']),
      balanceType: map['balance_type'] as String?,
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
    );
  }
}
