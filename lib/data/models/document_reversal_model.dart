class DocumentReversalModel {
  final int? id;
  final String documentType;
  final String documentId;
  final int? originalJournalId;
  final int reversalJournalId;
  final String reason;
  final String cancelledAt;
  final String source;

  const DocumentReversalModel({
    this.id,
    required this.documentType,
    required this.documentId,
    this.originalJournalId,
    required this.reversalJournalId,
    required this.reason,
    required this.cancelledAt,
    required this.source,
  });

  factory DocumentReversalModel.fromMap(Map<String, dynamic> map) {
    return DocumentReversalModel(
      id: (map['id'] as num?)?.toInt(),
      documentType: map['document_type'] as String,
      documentId: map['document_id'] as String,
      originalJournalId: (map['original_journal_id'] as num?)?.toInt(),
      reversalJournalId: (map['reversal_journal_id'] as num).toInt(),
      reason: map['reason'] as String,
      cancelledAt: map['cancelled_at'] as String,
      source: map['source'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'document_type': documentType,
      'document_id': documentId,
      'original_journal_id': originalJournalId,
      'reversal_journal_id': reversalJournalId,
      'reason': reason,
      'cancelled_at': cancelledAt,
      'source': source,
    };
  }
}
