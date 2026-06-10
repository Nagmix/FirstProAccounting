import 'package:firstpro/core/utils/money_helper.dart';

class BankReconciliation {
  final int? id;
  final String reconciliationNumber;
  final int cashBoxId;
  final DateTime statementDate;
  final double statementBalance;
  final double bookBalance;
  final double depositsInTransit;
  final double outstandingChecks;
  final double bankCharges;
  final double interestEarned;
  final double nsfChecks;
  final double otherAdjustments;
  final double adjustedBankBalance;
  final double adjustedBookBalance;
  final double difference;
  final String status; // 'draft', 'in_progress', 'completed', 'posted'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  BankReconciliation({
    this.id,
    required this.reconciliationNumber,
    required this.cashBoxId,
    required this.statementDate,
    this.statementBalance = 0.0,
    this.bookBalance = 0.0,
    this.depositsInTransit = 0.0,
    this.outstandingChecks = 0.0,
    this.bankCharges = 0.0,
    this.interestEarned = 0.0,
    this.nsfChecks = 0.0,
    this.otherAdjustments = 0.0,
    this.adjustedBankBalance = 0.0,
    this.adjustedBookBalance = 0.0,
    this.difference = 0.0,
    this.status = 'draft',
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isReconciled => difference.abs() < 0.005;

  String get statusAr {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مكتملة';
      case 'posted':
        return 'مرحّلة';
      default:
        return status;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'reconciliation_number': reconciliationNumber,
        'cash_box_id': cashBoxId,
        'statement_date': statementDate.toIso8601String(),
        'statement_balance': MoneyHelper.toCents(statementBalance),
        'book_balance': MoneyHelper.toCents(bookBalance),
        'deposits_in_transit': MoneyHelper.toCents(depositsInTransit),
        'outstanding_checks': MoneyHelper.toCents(outstandingChecks),
        'bank_charges': MoneyHelper.toCents(bankCharges),
        'interest_earned': MoneyHelper.toCents(interestEarned),
        'nsf_checks': MoneyHelper.toCents(nsfChecks),
        'other_adjustments': MoneyHelper.toCents(otherAdjustments),
        'adjusted_bank_balance': MoneyHelper.toCents(adjustedBankBalance),
        'adjusted_book_balance': MoneyHelper.toCents(adjustedBookBalance),
        'difference': MoneyHelper.toCents(difference),
        'status': status,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory BankReconciliation.fromMap(Map<String, dynamic> map) =>
      BankReconciliation(
        id: map['id'],
        reconciliationNumber: map['reconciliation_number'] ?? '',
        cashBoxId: map['cash_box_id'],
        statementDate: DateTime.parse(map['statement_date']),
        statementBalance: MoneyHelper.readMoney(map['statement_balance']),
        bookBalance: MoneyHelper.readMoney(map['book_balance']),
        depositsInTransit: MoneyHelper.readMoney(map['deposits_in_transit']),
        outstandingChecks: MoneyHelper.readMoney(map['outstanding_checks']),
        bankCharges: MoneyHelper.readMoney(map['bank_charges']),
        interestEarned: MoneyHelper.readMoney(map['interest_earned']),
        nsfChecks: MoneyHelper.readMoney(map['nsf_checks']),
        otherAdjustments: MoneyHelper.readMoney(map['other_adjustments']),
        adjustedBankBalance:
            MoneyHelper.readMoney(map['adjusted_bank_balance']),
        adjustedBookBalance:
            MoneyHelper.readMoney(map['adjusted_book_balance']),
        difference: MoneyHelper.readMoney(map['difference']),
        status: map['status'] ?? 'draft',
        notes: map['notes'],
        createdAt: DateTime.parse(map['created_at']),
        updatedAt: DateTime.parse(map['updated_at']),
      );

  BankReconciliation copyWith({
    int? id,
    String? reconciliationNumber,
    int? cashBoxId,
    DateTime? statementDate,
    double? statementBalance,
    double? bookBalance,
    double? depositsInTransit,
    double? outstandingChecks,
    double? bankCharges,
    double? interestEarned,
    double? nsfChecks,
    double? otherAdjustments,
    double? adjustedBankBalance,
    double? adjustedBookBalance,
    double? difference,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BankReconciliation(
      id: id ?? this.id,
      reconciliationNumber: reconciliationNumber ?? this.reconciliationNumber,
      cashBoxId: cashBoxId ?? this.cashBoxId,
      statementDate: statementDate ?? this.statementDate,
      statementBalance: statementBalance ?? this.statementBalance,
      bookBalance: bookBalance ?? this.bookBalance,
      depositsInTransit: depositsInTransit ?? this.depositsInTransit,
      outstandingChecks: outstandingChecks ?? this.outstandingChecks,
      bankCharges: bankCharges ?? this.bankCharges,
      interestEarned: interestEarned ?? this.interestEarned,
      nsfChecks: nsfChecks ?? this.nsfChecks,
      otherAdjustments: otherAdjustments ?? this.otherAdjustments,
      adjustedBankBalance: adjustedBankBalance ?? this.adjustedBankBalance,
      adjustedBookBalance: adjustedBookBalance ?? this.adjustedBookBalance,
      difference: difference ?? this.difference,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class BankStatementLine {
  final int? id;
  final int? reconciliationId;
  final int cashBoxId;
  final DateTime transactionDate;
  final String transactionType; // 'debit' or 'credit'
  final double amount;
  final String? reference;
  final String? description;
  final String matchStatus; // 'unmatched', 'matched', 'new_transaction'
  final int? matchedTransactionId;
  final bool isBookEntry;
  final String? sourceType;
  final String? sourceId;
  final DateTime createdAt;

  BankStatementLine({
    this.id,
    this.reconciliationId,
    required this.cashBoxId,
    required this.transactionDate,
    required this.transactionType,
    required this.amount,
    this.reference,
    this.description,
    this.matchStatus = 'unmatched',
    this.matchedTransactionId,
    this.isBookEntry = false,
    this.sourceType,
    this.sourceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isMatched => matchStatus == 'matched';
  bool get isUnmatched => matchStatus == 'unmatched';

  Map<String, dynamic> toMap() => {
        'id': id,
        'reconciliation_id': reconciliationId,
        'cash_box_id': cashBoxId,
        'transaction_date': transactionDate.toIso8601String(),
        'transaction_type': transactionType,
        'amount': MoneyHelper.toCents(amount),
        'reference': reference,
        'description': description,
        'match_status': matchStatus,
        'matched_transaction_id': matchedTransactionId,
        'is_book_entry': isBookEntry ? 1 : 0,
        'source_type': sourceType,
        'source_id': sourceId,
        'created_at': createdAt.toIso8601String(),
      };

  factory BankStatementLine.fromMap(Map<String, dynamic> map) =>
      BankStatementLine(
        id: map['id'],
        reconciliationId: map['reconciliation_id'],
        cashBoxId: map['cash_box_id'],
        transactionDate: DateTime.parse(map['transaction_date']),
        transactionType: map['transaction_type'] ?? 'debit',
        amount: MoneyHelper.readMoney(map['amount']),
        reference: map['reference'],
        description: map['description'],
        matchStatus: map['match_status'] ?? 'unmatched',
        matchedTransactionId: map['matched_transaction_id'],
        isBookEntry: (map['is_book_entry'] ?? 0) == 1,
        sourceType: map['source_type'],
        sourceId: map['source_id'],
        createdAt: DateTime.parse(map['created_at']),
      );

  BankStatementLine copyWith({
    int? id,
    int? reconciliationId,
    int? cashBoxId,
    DateTime? transactionDate,
    String? transactionType,
    double? amount,
    String? reference,
    String? description,
    String? matchStatus,
    int? matchedTransactionId,
    bool? isBookEntry,
    String? sourceType,
    String? sourceId,
    DateTime? createdAt,
  }) {
    return BankStatementLine(
      id: id ?? this.id,
      reconciliationId: reconciliationId ?? this.reconciliationId,
      cashBoxId: cashBoxId ?? this.cashBoxId,
      transactionDate: transactionDate ?? this.transactionDate,
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      reference: reference ?? this.reference,
      description: description ?? this.description,
      matchStatus: matchStatus ?? this.matchStatus,
      matchedTransactionId: matchedTransactionId ?? this.matchedTransactionId,
      isBookEntry: isBookEntry ?? this.isBookEntry,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
