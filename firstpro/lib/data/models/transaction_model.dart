class Transaction {
  final int? id;
  final int accountId;
  final int? journalId;
  final double debit;
  final double credit;
  final String? description;
  final DateTime date;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.accountId,
    this.journalId,
    this.debit = 0.0,
    this.credit = 0.0,
    this.description,
    required this.date,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'journal_id': journalId,
      'debit': debit,
      'credit': credit,
      'description': description,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      accountId: map['account_id'],
      journalId: map['journal_id'],
      debit: (map['debit'] ?? 0.0).toDouble(),
      credit: (map['credit'] ?? 0.0).toDouble(),
      description: map['description'],
      date: DateTime.parse(map['date']),
      createdAt: DateTime.parse(map['created_at']),
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
    );
  }
}
