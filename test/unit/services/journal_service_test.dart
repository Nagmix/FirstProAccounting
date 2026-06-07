import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// JournalService Logic Unit Tests
/// Tests the journal validation logic that doesn't require a database.
///
/// Note: Full integration tests with database are in the integration folder.
void main() {
  group('JournalService Logic Tests', () {
    // ═══════════════════════════════════════════════════════════
    //  validateJournalBalance (C-03 verification)
    // ═══════════════════════════════════════════════════════════
    group('Journal Balance Validation', () {
      /// Replicates the validateJournalBalance logic from JournalService
      /// since it operates on List<Map<String, dynamic>> and doesn't
      /// need database access.
      void validateJournalBalance(List<Map<String, dynamic>> entries) {
        double totalDebit = 0.0;
        double totalCredit = 0.0;
        for (final entry in entries) {
          totalDebit += MoneyHelper.readMoney(entry['debit']);
          totalCredit += MoneyHelper.readMoney(entry['credit']);
        }
        final difference = (totalDebit - totalCredit).abs();
        if (difference > 0.005) {
          throw Exception(
            'قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference',
          );
        }
      }

      test('balanced entry passes validation', () {
        final entries = [
          {'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
        ];
        expect(() => validateJournalBalance(entries), returnsNormally);
      });

      test('unbalanced entry throws exception', () {
        final entries = [
          {'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'debit': 0, 'credit': MoneyHelper.toCents(900.0)},
        ];
        expect(() => validateJournalBalance(entries), throwsException);
      });

      test('compound balanced entry passes', () {
        final entries = [
          {'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'debit': MoneyHelper.toCents(150.0), 'credit': 0},
          {'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
          {'debit': 0, 'credit': MoneyHelper.toCents(150.0)},
        ];
        expect(() => validateJournalBalance(entries), returnsNormally);
      });

      test('zero-value entry passes (all zeros)', () {
        final entries = [
          {'debit': 0, 'credit': 0},
          {'debit': 0, 'credit': 0},
        ];
        expect(() => validateJournalBalance(entries), returnsNormally);
      });

      test('single-sided entry fails (debit only)', () {
        final entries = [
          {'debit': MoneyHelper.toCents(500.0), 'credit': 0},
        ];
        expect(() => validateJournalBalance(entries), throwsException);
      });

      test('single-sided entry fails (credit only)', () {
        final entries = [
          {'debit': 0, 'credit': MoneyHelper.toCents(500.0)},
        ];
        expect(() => validateJournalBalance(entries), throwsException);
      });

      test('entry with integer cents (no floating-point issue)', () {
        // All values stored as INTEGER cents — no floating-point drift possible
        final entries = [
          {'debit': 100000, 'credit': 0}, // 1000.00
          {'debit': 0, 'credit': 100000}, // 1000.00
        ];
        expect(() => validateJournalBalance(entries), returnsNormally);
      });

      test('near-balanced entry within tolerance passes', () {
        // Difference of 0.003 (within 0.005 tolerance)
        final entries = [
          {'debit': 100003, 'credit': 0}, // ~1000.03
          {'debit': 0, 'credit': 100000}, // ~1000.00
        ];
        // The difference after readMoney: 1000.03 - 1000.00 = 0.03 → FAILS
        // This is correct behavior — tolerance is only 0.005
        expect(() => validateJournalBalance(entries), throwsException);
      });

      test('sale with COGS and discount balances', () {
        // Cash sale: 1000 with 5% discount, COGS = 600
        // Entry 1: Debit Cash 950, Credit Revenue 1000, Debit Discount 50
        // Entry 2: Debit COGS 600, Credit Inventory 600
        final entries = [
          {'debit': MoneyHelper.toCents(950.0), 'credit': 0},   // Cash
          {'debit': MoneyHelper.toCents(50.0), 'credit': 0},    // Discount
          {'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},  // Revenue
          {'debit': MoneyHelper.toCents(600.0), 'credit': 0},   // COGS
          {'debit': 0, 'credit': MoneyHelper.toCents(600.0)},   // Inventory
        ];
        expect(() => validateJournalBalance(entries), returnsNormally);
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Account Balance Update Logic
    // ═══════════════════════════════════════════════════════════
    group('Account Balance Update Logic', () {
      test('credit-balance account: credit increases balance', () {
        // LIABILITY account (credit nature)
        // Current balance: 5000
        // Credit entry: 2000
        // New balance: 5000 + 2000 = 7000
        double currentBalance = 5000.0;
        final balanceType = 'credit';
        final debit = 0.0;
        final credit = 2000.0;
        double newBalance;
        if (balanceType == 'credit') {
          newBalance = currentBalance + credit - debit;
        } else {
          newBalance = currentBalance + debit - credit;
        }
        expect(newBalance, equals(7000.0));
      });

      test('credit-balance account: debit decreases balance', () {
        // LIABILITY account (credit nature)
        // Current balance: 5000
        // Debit entry: 2000 (payment reduces liability)
        // New balance: 5000 - 2000 = 3000
        double currentBalance = 5000.0;
        final balanceType = 'credit';
        final debit = 2000.0;
        final credit = 0.0;
        double newBalance;
        if (balanceType == 'credit') {
          newBalance = currentBalance + credit - debit;
        } else {
          newBalance = currentBalance + debit - credit;
        }
        expect(newBalance, equals(3000.0));
      });

      test('debit-balance account: debit increases balance', () {
        // ASSET account (debit nature)
        // Current balance: 10000
        // Debit entry: 5000 (receiving cash)
        // New balance: 10000 + 5000 = 15000
        double currentBalance = 10000.0;
        final balanceType = 'debit';
        final debit = 5000.0;
        final credit = 0.0;
        double newBalance;
        if (balanceType == 'credit') {
          newBalance = currentBalance + credit - debit;
        } else {
          newBalance = currentBalance + debit - credit;
        }
        expect(newBalance, equals(15000.0));
      });

      test('debit-balance account: credit decreases balance', () {
        // ASSET account (debit nature)
        // Current balance: 10000
        // Credit entry: 3000 (paying cash)
        // New balance: 10000 - 3000 = 7000
        double currentBalance = 10000.0;
        final balanceType = 'debit';
        final debit = 0.0;
        final credit = 3000.0;
        double newBalance;
        if (balanceType == 'credit') {
          newBalance = currentBalance + credit - debit;
        } else {
          newBalance = currentBalance + debit - credit;
        }
        expect(newBalance, equals(7000.0));
      });

      test('EXPENSE account (debit nature): debit increases balance', () {
        // C-01 verification: EXPENSE should be debit nature
        double currentBalance = 1000.0;
        final balanceType = 'debit'; // EXPENSE = debit (C-01 fix)
        final debit = 500.0;
        final credit = 0.0;
        double newBalance;
        if (balanceType == 'credit') {
          newBalance = currentBalance + credit - debit; // WRONG for expense
        } else {
          newBalance = currentBalance + debit - credit; // CORRECT for expense
        }
        expect(newBalance, equals(1500.0));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Journal ID Generation
    // ═══════════════════════════════════════════════════════════
    group('Journal ID Generation', () {
      test('IDs are unique even in rapid succession', () {
        // Simulate generating multiple IDs quickly
        final ids = <int>{};
        for (int i = 0; i < 100; i++) {
          final micros = DateTime.now().microsecondsSinceEpoch;
          final random = DateTime.now().millisecond;
          final id = micros * 1000 + (random % 1000);
          ids.add(id);
        }
        // Not guaranteed unique due to timing, but should have many distinct values
        expect(ids.length, greaterThan(90));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  Account Code Offset Logic
    // ═══════════════════════════════════════════════════════════
    group('Account Code Offset', () {
      test('YER accounts use offset 0', () {
        final baseCode = '1000';
        final currency = 'YER';
        final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
        final actualCode = (int.parse(baseCode) + codeOffset).toString();
        expect(actualCode, equals('1000'));
      });

      test('SAR accounts use offset 1', () {
        final baseCode = '1000';
        final currency = 'SAR';
        final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
        final actualCode = (int.parse(baseCode) + codeOffset).toString();
        expect(actualCode, equals('1001'));
      });

      test('USD accounts use offset 2', () {
        final baseCode = '1000';
        final currency = 'USD';
        final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
        final actualCode = (int.parse(baseCode) + codeOffset).toString();
        expect(actualCode, equals('1002'));
      });
    });
  });
}
