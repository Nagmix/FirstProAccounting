/// A validated journal line expressed entirely in minor currency units.
class JournalLine {
  const JournalLine({
    required this.accountId,
    required this.debitMinorUnits,
    required this.creditMinorUnits,
    required this.currencyCode,
    required this.amountBaseMinorUnits,
  });

  final int accountId;
  final int debitMinorUnits;
  final int creditMinorUnits;
  final String currencyCode;
  final int amountBaseMinorUnits;

  bool get hasDebit => debitMinorUnits > 0;
  bool get hasCredit => creditMinorUnits > 0;
  bool get hasAmount => hasDebit || hasCredit;
}

class JournalValidationException implements Exception {
  const JournalValidationException(this.message);

  final String message;

  @override
  String toString() => 'JournalValidationException: $message';
}

/// Pure validation rules shared by invoice, voucher, stock and service posts.
class JournalValidator {
  const JournalValidator._();

  static void ensureBalanced(Iterable<JournalLine> lines) {
    final entries = lines.toList(growable: false);
    if (entries.isEmpty) {
      throw const JournalValidationException('Journal must contain entries');
    }

    var debitBase = 0;
    var creditBase = 0;
    var hasAmount = false;

    for (final line in entries) {
      if (line.accountId <= 0) {
        throw const JournalValidationException('Every line needs an account');
      }
      if (line.currencyCode.trim().isEmpty) {
        throw const JournalValidationException('Every line needs a currency');
      }
      if (line.debitMinorUnits < 0 || line.creditMinorUnits < 0) {
        throw const JournalValidationException('Debit and credit cannot be negative');
      }
      if (line.hasDebit && line.hasCredit) {
        throw const JournalValidationException(
          'A journal line cannot contain both debit and credit',
        );
      }
      if (line.amountBaseMinorUnits < 0) {
        throw const JournalValidationException(
          'Base amount cannot be negative',
        );
      }
      if (line.hasAmount && line.amountBaseMinorUnits == 0) {
        throw const JournalValidationException(
          'A monetary line must have a base-currency amount',
        );
      }

      hasAmount = hasAmount || line.hasAmount;
      if (line.hasDebit) debitBase += line.amountBaseMinorUnits;
      if (line.hasCredit) creditBase += line.amountBaseMinorUnits;
    }

    if (!hasAmount) {
      throw const JournalValidationException('Journal cannot be all zero');
    }
    if (debitBase != creditBase) {
      throw JournalValidationException(
        'Journal is not balanced in base currency: '
        'debit=$debitBase, credit=$creditBase',
      );
    }
  }
}
