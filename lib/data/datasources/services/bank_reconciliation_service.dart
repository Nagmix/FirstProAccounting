import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';
import 'package:firstpro/data/models/bank_reconciliation_model.dart';

class BankReconciliationService {
  final DatabaseHelper _dbHelper;
  BankReconciliationService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Get next reconciliation number
  Future<String> getNextReconciliationNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'BR-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(reconciliation_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM bank_reconciliations WHERE reconciliation_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create a new bank reconciliation session
  Future<int> createReconciliation(BankReconciliation reconciliation) async {
    final db = await _db;
    return await db.insert('bank_reconciliations', MoneyHelper.toCentsMap(reconciliation.toMap(), MoneyHelper.bankReconciliationMoneyFields));
  }

  /// Get all bank-type cash boxes
  Future<List<Map<String, dynamic>>> getBankCashBoxes() async {
    final db = await _db;
    return await db.query('cash_boxes',
        where: "type = 'bank' AND is_active = 1", orderBy: 'name');
  }

  /// Get book balance for a bank cash box (from linked account)
  Future<double> getBookBalance(int cashBoxId) async {
    final db = await _db;
    final cashBox = await db.query('cash_boxes',
        where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
    if (cashBox.isEmpty) return 0.0;

    final linkedAccountId = cashBox.first['linked_account_id'] as int?;
    if (linkedAccountId == null) {
      // Use cash box balance as fallback
      return MoneyHelper.readMoney(cashBox.first['balance']);
    }

    final account = await db.query('accounts',
        where: 'id = ?', whereArgs: [linkedAccountId], limit: 1);
    if (account.isEmpty) return 0.0;

    return MoneyHelper.readMoney(account.first['balance']);
  }

  /// Get book transactions for a bank account within a date range
  Future<List<Map<String, dynamic>>> getBookTransactions(
      int cashBoxId, DateTime startDate, DateTime endDate) async {
    final db = await _db;
    final cashBox = await db.query('cash_boxes',
        where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
    if (cashBox.isEmpty) return [];

    final linkedAccountId = cashBox.first['linked_account_id'] as int?;
    if (linkedAccountId == null) return [];

    final startDateStr = startDate.toIso8601String();
    final endDateStr = endDate.toIso8601String();

    return await db.query('transactions',
        where: 'account_id = ? AND date >= ? AND date <= ?',
        whereArgs: [linkedAccountId, startDateStr, endDateStr],
        orderBy: 'date ASC');
  }

  /// Add a bank statement line
  Future<int> addStatementLine(BankStatementLine line) async {
    final db = await _db;
    return await db.insert('bank_statement_lines', MoneyHelper.toCentsMap(line.toMap(), MoneyHelper.bankStatementLineMoneyFields));
  }

  /// Add multiple bank statement lines at once (for bulk import)
  Future<void> addStatementLines(List<BankStatementLine> lines) async {
    final db = await _db;
    for (final line in lines) {
      await db.insert('bank_statement_lines', MoneyHelper.toCentsMap(line.toMap(), MoneyHelper.bankStatementLineMoneyFields));
    }
  }

  /// Get statement lines for a reconciliation
  Future<List<BankStatementLine>> getStatementLines(
      int reconciliationId) async {
    final db = await _db;
    final rows = await db.query('bank_statement_lines',
        where: 'reconciliation_id = ?',
        whereArgs: [reconciliationId],
        orderBy: 'transaction_date ASC');
    return rows.map((r) => BankStatementLine.fromMap(r)).toList();
  }

  /// Get unmatched statement lines
  Future<List<BankStatementLine>> getUnmatchedLines(
      int reconciliationId) async {
    final db = await _db;
    final rows = await db.query('bank_statement_lines',
        where: 'reconciliation_id = ? AND match_status = ?',
        whereArgs: [reconciliationId, 'unmatched'],
        orderBy: 'transaction_date ASC');
    return rows.map((r) => BankStatementLine.fromMap(r)).toList();
  }

  /// Match a statement line with a book transaction
  Future<void> matchLine(int statementLineId, int transactionId) async {
    final db = await _db;
    await db.update(
        'bank_statement_lines',
        {
          'match_status': 'matched',
          'matched_transaction_id': transactionId,
        },
        where: 'id = ?',
        whereArgs: [statementLineId]);
  }

  /// Unmatch a statement line
  Future<void> unmatchLine(int statementLineId) async {
    final db = await _db;
    await db.update(
        'bank_statement_lines',
        {
          'match_status': 'unmatched',
          'matched_transaction_id': null,
        },
        where: 'id = ?',
        whereArgs: [statementLineId]);
  }

  /// Auto-match statement lines with book transactions by amount and date proximity
  Future<int> autoMatch(int reconciliationId,
      {int dateToleranceDays = 3}) async {
    final db = await _db;
    int matchedCount = 0;

    final unmatchedLines = await db.query('bank_statement_lines',
        where:
            'reconciliation_id = ? AND match_status = ? AND is_book_entry = 0',
        whereArgs: [reconciliationId, 'unmatched']);

    for (final line in unmatchedLines) {
      final lineAmount = MoneyHelper.readMoney(line['amount']);
      final lineDate = DateTime.parse(line['transaction_date'] as String);
      final lineType = line['transaction_type'] as String;
      final lineCashBoxId = line['cash_box_id'] as int;

      // Get linked account for this cash box
      final cashBox = await db.query('cash_boxes',
          where: 'id = ?', whereArgs: [lineCashBoxId], limit: 1);
      if (cashBox.isEmpty) continue;
      final linkedAccountId = cashBox.first['linked_account_id'] as int?;
      if (linkedAccountId == null) continue;

      // For bank: debit = withdrawal (credit in books), credit = deposit (debit in books)
      final isDebit = lineType == 'debit';
      final searchDebit = isDebit ? 0 : MoneyHelper.toCents(lineAmount);
      final searchCredit = isDebit ? MoneyHelper.toCents(lineAmount) : 0;

      // Search for matching transactions within date tolerance
      final startDate = lineDate.subtract(Duration(days: dateToleranceDays));
      final endDate = lineDate.add(Duration(days: dateToleranceDays));

      final candidates = await db.query('transactions',
          where: '''account_id = ? 
          AND ((debit = ? AND credit = 0) OR (credit = ? AND debit = 0))
          AND date >= ? AND date <= ?
          AND id NOT IN (SELECT matched_transaction_id FROM bank_statement_lines WHERE matched_transaction_id IS NOT NULL)''',
          whereArgs: [
            linkedAccountId,
            searchDebit,
            searchCredit,
            startDate.toIso8601String(),
            endDate.toIso8601String(),
          ],
          limit: 1);

      if (candidates.isNotEmpty) {
        final txnId = candidates.first['id'] as int;
        await db.update(
            'bank_statement_lines',
            {
              'match_status': 'matched',
              'matched_transaction_id': txnId,
            },
            where: 'id = ?',
            whereArgs: [line['id']]);
        matchedCount++;
      }
    }

    return matchedCount;
  }

  /// Calculate adjusted balances for a reconciliation
  Future<BankReconciliation> calculateAdjustedBalances(
      BankReconciliation recon) async {
    final db = await _db;

    // Calculate unmatched deposits in transit (book debit entries not matched to bank)
    final unmatchedDeposits = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM bank_statement_lines 
      WHERE reconciliation_id = ? AND is_book_entry = 1 AND transaction_type = 'debit' AND match_status = 'unmatched'
    ''', [recon.id]);

    // Calculate unmatched outstanding checks (book credit entries not matched to bank)
    final unmatchedChecks = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM bank_statement_lines 
      WHERE reconciliation_id = ? AND is_book_entry = 1 AND transaction_type = 'credit' AND match_status = 'unmatched'
    ''', [recon.id]);

    // Calculate new bank entries (bank statement lines not in books)
    final newBankCredits = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM bank_statement_lines 
      WHERE reconciliation_id = ? AND is_book_entry = 0 AND transaction_type = 'credit' AND match_status = 'unmatched'
    ''', [recon.id]);

    final newBankDebits = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM bank_statement_lines 
      WHERE reconciliation_id = ? AND is_book_entry = 0 AND transaction_type = 'debit' AND match_status = 'unmatched'
    ''', [recon.id]);

    final depositsInTransit =
        MoneyHelper.readCalculatedMoney(unmatchedDeposits.first['total']);
    final outstandingChecks =
        MoneyHelper.readCalculatedMoney(unmatchedChecks.first['total']);
    final interestEarned = MoneyHelper.readCalculatedMoney(newBankCredits.first['total']);
    final bankCharges = MoneyHelper.readCalculatedMoney(newBankDebits.first['total']);

    final adjustedBankBalance =
        recon.statementBalance + depositsInTransit - outstandingChecks;
    final adjustedBookBalance =
        recon.bookBalance + interestEarned - bankCharges;
    final difference = (adjustedBankBalance - adjustedBookBalance).abs();

    return recon.copyWith(
      depositsInTransit: depositsInTransit,
      outstandingChecks: outstandingChecks,
      bankCharges: bankCharges,
      interestEarned: interestEarned,
      adjustedBankBalance: adjustedBankBalance,
      adjustedBookBalance: adjustedBookBalance,
      difference: difference,
    );
  }

  /// Complete a reconciliation and post adjustment journal entries
  Future<void> completeReconciliation(int reconciliationId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final reconRow = await db.query('bank_reconciliations',
        where: 'id = ?', whereArgs: [reconciliationId], limit: 1);
    if (reconRow.isEmpty) return;

    final recon = BankReconciliation.fromMap(reconRow.first);
    final calculated = await calculateAdjustedBalances(recon);

    await db.transaction((txn) async {
      final journalId = generateUniqueJournalId();
      final cashBoxId = recon.cashBoxId;

      // Get cash box and linked account
      final cashBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
      if (cashBox.isEmpty) return;
      final linkedAccountId = cashBox.first['linked_account_id'] as int?;
      if (linkedAccountId == null) return;

      final currency = cashBox.first['currency'] as String? ?? 'YER';
      final codeOffset =
          await locator<BaseCurrencyService>().getOffsetForCurrency(currency);
      final exchangeRate = await _getExchangeRate(txn, currency);

      // Bank charges: Dr. Bank Charges Expense / Cr. Cash
      if (calculated.bankCharges.abs() >= 0.005) {
        final expenseCode = (5250 + codeOffset).toString();
        final expenseAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [expenseCode, currency],
            limit: 1);
        final expenseAccountId = expenseAccount.isNotEmpty
            ? expenseAccount.first['id'] as int
            : null;

        // Prevent unbalanced entry if expense account not found
        if (expenseAccountId == null) {
          throw Exception(
              'لا يوجد حساب رسوم بنكية (5250) للعملة $currency. يرجى التأكد من إنشاء الحساب.');
        }

        await txn.insert('transactions', {
          'account_id': expenseAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(calculated.bankCharges),
          'credit': 0,
          'description': 'رسوم بنكية - تسوية ${recon.reconciliationNumber}',
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': currency == 'YER' ? 1.0 : exchangeRate,
          'amount_base':
              (MoneyHelper.toCents(calculated.bankCharges) * exchangeRate)
                  .round(),
                  'reference_type': 'bank_reconciliation',
          'reference_id': journalId.toString(),
});
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, expenseAccountId, calculated.bankCharges, 0.0, now);

        await txn.insert('transactions', {
          'account_id': linkedAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(calculated.bankCharges),
          'description': 'رسوم بنكية - تسوية ${recon.reconciliationNumber}',
          'date': now,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': currency == 'YER' ? 1.0 : exchangeRate,
          'amount_base':
              (MoneyHelper.toCents(calculated.bankCharges) * exchangeRate)
                  .round(),
                  'reference_type': 'bank_reconciliation',
          'reference_id': journalId.toString(),
});
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, linkedAccountId, 0.0, calculated.bankCharges, now);

        // Update cash box balance
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(calculated.bankCharges), now, cashBoxId]);
      }

      // Interest earned: Dr. Cash / Cr. Interest Income (Other Revenue 4900)
      if (calculated.interestEarned.abs() >= 0.005) {
        final revenueCode = (4900 + codeOffset).toString();
        final revenueAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [revenueCode, currency],
            limit: 1);
        final revenueAccountId = revenueAccount.isNotEmpty
            ? revenueAccount.first['id'] as int
            : null;

        if (revenueAccountId != null) {
          await txn.insert('transactions', {
            'account_id': linkedAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(calculated.interestEarned),
            'credit': 0,
            'description': 'فوائد بنكية - تسوية ${recon.reconciliationNumber}',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : exchangeRate,
            'amount_base':
                (MoneyHelper.toCents(calculated.interestEarned) * exchangeRate)
                    .round(),
                    'reference_type': 'bank_reconciliation',
          'reference_id': journalId.toString(),
});
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, linkedAccountId, calculated.interestEarned, 0.0, now);

          await txn.insert('transactions', {
            'account_id': revenueAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(calculated.interestEarned),
            'description': 'فوائد بنكية - تسوية ${recon.reconciliationNumber}',
            'date': now,
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : exchangeRate,
            'amount_base':
                (MoneyHelper.toCents(calculated.interestEarned) * exchangeRate)
                    .round(),
                    'reference_type': 'bank_reconciliation',
          'reference_id': journalId.toString(),
});
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, revenueAccountId, 0.0, calculated.interestEarned, now);

          // Update cash box balance (only inside null check to stay in sync)
          await txn.rawUpdate(
              'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
              [MoneyHelper.toCents(calculated.interestEarned), now, cashBoxId]);
        }
      }

      // Update reconciliation status
      await txn.update(
          'bank_reconciliations',
          {
            'deposits_in_transit':
                MoneyHelper.toCents(calculated.depositsInTransit),
            'outstanding_checks':
                MoneyHelper.toCents(calculated.outstandingChecks),
            'bank_charges': MoneyHelper.toCents(calculated.bankCharges),
            'interest_earned': MoneyHelper.toCents(calculated.interestEarned),
            'adjusted_bank_balance':
                MoneyHelper.toCents(calculated.adjustedBankBalance),
            'adjusted_book_balance':
                MoneyHelper.toCents(calculated.adjustedBookBalance),
            'difference': MoneyHelper.toCents(calculated.difference),
            'status': 'completed',
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [reconciliationId]);
    });
  }

  /// Load book transactions as statement lines for a reconciliation
  Future<void> loadBookTransactionsAsStatementLines(int reconciliationId,
      int cashBoxId, DateTime startDate, DateTime endDate) async {
    final db = await _db;
    final bookTransactions =
        await getBookTransactions(cashBoxId, startDate, endDate);

    for (final txn in bookTransactions) {
      final debit = MoneyHelper.readMoney(txn['debit']);
      final credit = MoneyHelper.readMoney(txn['credit']);
      final date = DateTime.parse(txn['date'] as String);
      final description = txn['description'] as String? ?? '';

      final line = BankStatementLine(
        reconciliationId: reconciliationId,
        cashBoxId: cashBoxId,
        transactionDate: date,
        transactionType: debit > 0 ? 'debit' : 'credit',
        amount: debit > 0 ? debit : credit,
        description: description,
        matchStatus: 'unmatched',
        isBookEntry: true,
        sourceType: 'transaction',
        sourceId: txn['id']?.toString(),
      );

      await db.insert('bank_statement_lines', MoneyHelper.toCentsMap(line.toMap(), MoneyHelper.bankStatementLineMoneyFields));
    }
  }

  /// Get all reconciliations (history)
  Future<List<BankReconciliation>> getAllReconciliations() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT br.*, cb.name as cash_box_name, cb.bank_name
      FROM bank_reconciliations br
      LEFT JOIN cash_boxes cb ON br.cash_box_id = cb.id
      ORDER BY br.statement_date DESC
    ''');
    return rows.map((r) => BankReconciliation.fromMap(r)).toList();
  }

  /// Get all reconciliations with joined info (for list display)
  Future<List<Map<String, dynamic>>> getAllReconciliationsWithInfo() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT br.*, cb.name as cash_box_name, cb.bank_name
      FROM bank_reconciliations br
      LEFT JOIN cash_boxes cb ON br.cash_box_id = cb.id
      ORDER BY br.statement_date DESC
    ''');
  }

  /// Get a single reconciliation
  Future<BankReconciliation?> getReconciliation(int id) async {
    final db = await _db;
    final rows = await db.query('bank_reconciliations',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? BankReconciliation.fromMap(rows.first) : null;
  }

  /// Get a single reconciliation with joined info
  Future<Map<String, dynamic>?> getReconciliationWithInfo(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT br.*, cb.name as cash_box_name, cb.bank_name
      FROM bank_reconciliations br
      LEFT JOIN cash_boxes cb ON br.cash_box_id = cb.id
      WHERE br.id = ?
    ''', [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update a reconciliation
  Future<void> updateReconciliation(BankReconciliation recon) async {
    final db = await _db;
    await db.update('bank_reconciliations', MoneyHelper.toCentsMap(recon.toMap(), MoneyHelper.bankReconciliationMoneyFields),
        where: 'id = ?', whereArgs: [recon.id]);
  }

  /// Get exchange rate for a currency from the currencies table.
  /// Falls back to hardcoded defaults if the table/query fails.
  Future<double> _getExchangeRate(dynamic executor, String currency) async {
    if (currency == 'YER') return 1.0;
    try {
      final rows = await executor.query('currencies',
          where: 'code = ?', whereArgs: [currency], limit: 1);
      if (rows.isNotEmpty) {
        return (rows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      }
    } catch (e) {
      // B-8: لا نبتلع الأخطاء بصمت في كود مالي — سجّل ثم تابع المسار الاحتياطي
      debugPrint(
          'BankReconciliationService._getExchangeRate($currency) فشل، استخدام السعر الاحتياطي: $e');
    }
    // Fallback defaults
    if (currency == 'SAR') return 140.0;
    if (currency == 'USD') return 530.0;
    return 1.0;
  }

  /// Delete a draft reconciliation
  Future<void> deleteReconciliation(int id) async {
    final db = await _db;
    await db.delete('bank_statement_lines',
        where: 'reconciliation_id = ?', whereArgs: [id]);
    await db.delete('bank_reconciliations', where: 'id = ?', whereArgs: [id]);
  }
}
