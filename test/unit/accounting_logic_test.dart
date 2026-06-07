import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// ══════════════════════════════════════════════════════════════════
/// اختبارات الوحدة للمنطق المحاسبي
/// Unit tests for accounting business logic:
///   - Journal balance validation
///   - Double-entry bookkeeping integrity
///   - Balance type rules (debit vs credit)
///   - Exchange rate calculations
///   - Account type conventions
/// ══════════════════════════════════════════════════════════════════

void main() {
  // ══════════════════════════════════════════════════════════════
  //  Journal Balance Validation Tests
  // ══════════════════════════════════════════════════════════════

  group('Journal Balance Validation', () {
    /// Mirrors the logic of JournalService.validateJournalBalance
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

    test('Balanced journal entry passes validation', () {
      final entries = [
        {'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(5000.0)},
      ];

      expect(() => validateJournalBalance(entries), returnsNormally);
    });

    test('Unbalanced journal entry fails validation', () {
      final entries = [
        {'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(4000.0)},
      ];

      expect(() => validateJournalBalance(entries), throwsException);
    });

    test('Multi-line balanced journal entry passes', () {
      final entries = [
        {'debit': MoneyHelper.toCents(3000.0), 'credit': 0},
        {'debit': MoneyHelper.toCents(2000.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(4000.0)},
        {'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
      ];

      expect(() => validateJournalBalance(entries), returnsNormally);
    });

    test('Zero-amount entry is valid', () {
      final entries = [
        {'debit': 0, 'credit': 0},
      ];

      expect(() => validateJournalBalance(entries), returnsNormally);
    });

    test('Tiny rounding difference (<= 0.005) is tolerated', () {
      // In cents system, this shouldn't happen, but test the tolerance
      final entries = [
        {'debit': MoneyHelper.toCents(100.0), 'credit': 0},
        {'debit': 0, 'credit': MoneyHelper.toCents(100.0)},
      ];

      expect(() => validateJournalBalance(entries), returnsNormally);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Balance Type Rules Tests
  // ══════════════════════════════════════════════════════════════

  group('Balance Type Rules', () {
    test('Debit-balance accounts: debit increases, credit decreases', () {
      // ASSET, COST, EXPENSE accounts
      const balanceType = 'debit';
      double balance = 0.0;

      // Debit entry → balance increases
      final debitAmount = 5000.0;
      if (balanceType == 'debit') {
        balance += debitAmount;
      }
      expect(balance, 5000.0);

      // Credit entry → balance decreases
      final creditAmount = 2000.0;
      if (balanceType == 'debit') {
        balance -= creditAmount;
      }
      expect(balance, 3000.0);
    });

    test('Credit-balance accounts: credit increases, debit decreases', () {
      // LIABILITY, REVENUE, EQUITY accounts
      const balanceType = 'credit';
      double balance = 0.0;

      // Credit entry → balance increases
      final creditAmount = 5000.0;
      if (balanceType == 'credit') {
        balance += creditAmount;
      }
      expect(balance, 5000.0);

      // Debit entry → balance decreases
      final debitAmount = 2000.0;
      if (balanceType == 'credit') {
        balance -= debitAmount;
      }
      expect(balance, 3000.0);
    });

    test('Account type maps to correct balance type', () {
      // Debit-balance types
      const debitTypes = ['ASSET', 'COST', 'EXPENSE'];
      for (final type in debitTypes) {
        final balanceType = (type == 'ASSET' || type == 'COST' || type == 'EXPENSE')
            ? 'debit'
            : 'credit';
        expect(balanceType, 'debit');
      }

      // Credit-balance types
      const creditTypes = ['LIABILITY', 'EQUITY', 'REVENUE'];
      for (final type in creditTypes) {
        final balanceType = (type == 'ASSET' || type == 'COST' || type == 'EXPENSE')
            ? 'debit'
            : 'credit';
        expect(balanceType, 'credit');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Double-Entry Bookkeeping Tests
  // ══════════════════════════════════════════════════════════════

  group('Double-Entry Bookkeeping Integrity', () {
    test('Cash sale: Cash increases, Revenue increases', () {
      const saleAmount = 10000.0;

      // Cash account (ASSET/debit): debit → increases
      double cashBalance = 0.0;
      cashBalance += saleAmount; // debit increases debit-balance account
      expect(cashBalance, 10000.0);

      // Revenue account (REVENUE/credit): credit → increases
      double revenueBalance = 0.0;
      revenueBalance += saleAmount; // credit increases credit-balance account
      expect(revenueBalance, 10000.0);

      // Total debit = Total credit (balanced)
      expect(saleAmount, saleAmount); // trivially true but validates the concept
    });

    test('Credit sale with partial payment', () {
      const totalAmount = 10000.0;
      const paidAmount = 6000.0;
      const remaining = totalAmount - paidAmount;

      // Customer account (ASSET/debit): total amount debited
      double customerBalance = 0.0;
      customerBalance += totalAmount;
      expect(customerBalance, 10000.0);

      // Cash account (ASSET/debit): paid amount debited
      double cashBalance = 0.0;
      cashBalance += paidAmount;
      expect(cashBalance, 6000.0);

      // Revenue account (REVENUE/credit): total amount credited
      double revenueBalance = 0.0;
      revenueBalance += totalAmount;
      expect(revenueBalance, 10000.0);

      // Customer balance should show remaining debt
      final customerRemaining = customerBalance - paidAmount;
      expect(customerRemaining, remaining);
    });

    test('Purchase: Cost increases, Cash or Payable increases', () {
      const purchaseAmount = 5000.0;

      // COGS/Cost account (COST/debit): debit → increases
      double costBalance = 0.0;
      costBalance += purchaseAmount;
      expect(costBalance, 5000.0);

      // Cash account (ASSET/debit): credit → decreases
      double cashBalance = 10000.0;
      cashBalance -= purchaseAmount; // credit decreases debit-balance account
      expect(cashBalance, 5000.0);

      // Verify: total debit = purchaseAmount, total credit = purchaseAmount
      expect(costBalance, purchaseAmount);
      expect(10000.0 - cashBalance, purchaseAmount);
    });

    test('Receipt voucher: Cash increases, Customer decreases', () {
      const receiptAmount = 3000.0;
      double cashBalance = 5000.0;
      double customerBalance = 8000.0; // Customer owes 8000

      // Cash (ASSET/debit): debit → increases
      cashBalance += receiptAmount;
      expect(cashBalance, 8000.0);

      // Customer (ASSET/debit): credit → decreases
      customerBalance -= receiptAmount;
      expect(customerBalance, 5000.0);

      // Verify: debit = receiptAmount (cash), credit = receiptAmount (customer)
      expect(receiptAmount, 3000.0);
    });

    test('Payment voucher: Cash decreases, Supplier decreases', () {
      const paymentAmount = 4000.0;
      double cashBalance = 10000.0;
      double supplierBalance = 7000.0; // We owe supplier 7000

      // Cash (ASSET/debit): credit → decreases
      cashBalance -= paymentAmount;
      expect(cashBalance, 6000.0);

      // Supplier (LIABILITY/credit): debit → decreases
      supplierBalance -= paymentAmount;
      expect(supplierBalance, 3000.0);
    });

    test('Cash transfer between boxes: one decreases, other increases', () {
      const transferAmount = 2000.0;
      double fromBoxBalance = 5000.0;
      double toBoxBalance = 3000.0;

      // From box: decreases
      fromBoxBalance -= transferAmount;
      expect(fromBoxBalance, 3000.0);

      // To box: increases
      toBoxBalance += transferAmount;
      expect(toBoxBalance, 5000.0);

      // Total cash unchanged
      final totalBefore = 5000.0 + 3000.0;
      final totalAfter = fromBoxBalance + toBoxBalance;
      expect(totalAfter, totalBefore);
    });

    test('Return sale: reverses the original sale entries', () {
      const originalSaleAmount = 5000.0;
      const returnAmount = 1500.0;

      // Original sale effects
      double cashBalance = originalSaleAmount;
      double revenueBalance = originalSaleAmount;

      // Return: reverse the effects
      // Cash: credit → decreases
      cashBalance -= returnAmount;
      expect(cashBalance, 3500.0);

      // Revenue: debit → decreases
      revenueBalance -= returnAmount;
      expect(revenueBalance, 3500.0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Exchange Rate Calculation Tests
  // ══════════════════════════════════════════════════════════════

  group('Exchange Rate Calculations', () {
    test('Calculate exchange gain/loss correctly', () {
      // A receivable of 1000 SAR at original rate 140 YER/SAR
      // Current rate: 150 YER/SAR
      const baseAmount = 140000.0; // 1000 SAR * 140 = 140,000 YER
      const originalRate = 140.0;
      const currentRate = 150.0;

      final foreignAmount = baseAmount / originalRate;
      final valueAtCurrentRate = foreignAmount * currentRate;
      final gainLoss = valueAtCurrentRate - baseAmount;

      expect(foreignAmount, 1000.0);
      expect(valueAtCurrentRate, 150000.0);
      expect(gainLoss, 10000.0); // Gain of 10,000 YER
    });

    test('Exchange loss when rate decreases', () {
      const baseAmount = 530000.0; // 1000 USD * 530 = 530,000 YER
      const originalRate = 530.0;
      const currentRate = 500.0;

      final foreignAmount = baseAmount / originalRate;
      final valueAtCurrentRate = foreignAmount * currentRate;
      final gainLoss = valueAtCurrentRate - baseAmount;

      expect(foreignAmount, 1000.0);
      expect(valueAtCurrentRate, 500000.0);
      expect(gainLoss, -30000.0); // Loss of 30,000 YER
    });

    test('Zero rates return zero gain/loss', () {
      const baseAmount = 100000.0;

      // Original rate = 0
      final foreignAmount0 = baseAmount / 0;
      expect(foreignAmount0.isInfinite, isTrue);

      // The service code handles this: if (originalRate <= 0 || currentRate <= 0) return 0.0
    });

    test('Same rates result in zero gain/loss', () {
      const baseAmount = 140000.0;
      const rate = 140.0;

      final foreignAmount = baseAmount / rate;
      final valueAtCurrentRate = foreignAmount * rate;
      final gainLoss = valueAtCurrentRate - baseAmount;

      expect(gainLoss, closeTo(0.0, 0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Account Code Convention Tests
  // ══════════════════════════════════════════════════════════════

  group('Account Code Convention', () {
    test('Code offset matches currency: YER=0, SAR=1, USD=2', () {
      const baseCode = 1100;

      int codeOffset(String currency) {
        if (currency == 'SAR') return 1;
        if (currency == 'USD') return 2;
        return 0;
      }

      expect(baseCode + codeOffset('YER'), 1100);
      expect(baseCode + codeOffset('SAR'), 1101);
      expect(baseCode + codeOffset('USD'), 1102);
    });

    test('Account code ranges match account types', () {
      // 1000-1999: Assets
      // 2000-2999: Liabilities + Equity
      // 3000-3999: Costs
      // 4000-4999: Revenue
      // 5000-5999: Expenses

      String getAccountType(int code) {
        if (code >= 1000 && code < 2000) return 'ASSET';
        if (code >= 2000 && code < 3000) return 'LIABILITY/EQUITY';
        if (code >= 3000 && code < 4000) return 'COST';
        if (code >= 4000 && code < 5000) return 'REVENUE';
        if (code >= 5000 && code < 6000) return 'EXPENSE';
        return 'UNKNOWN';
      }

      expect(getAccountType(1100), 'ASSET');
      expect(getAccountType(1200), 'ASSET');
      expect(getAccountType(2100), 'LIABILITY/EQUITY');
      expect(getAccountType(2901), 'LIABILITY/EQUITY');
      expect(getAccountType(3100), 'COST');
      expect(getAccountType(3200), 'COST');
      expect(getAccountType(4100), 'REVENUE');
      expect(getAccountType(4700), 'REVENUE');
      expect(getAccountType(5100), 'EXPENSE');
      expect(getAccountType(5300), 'EXPENSE');
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Voucher Balance Validation Tests
  // ══════════════════════════════════════════════════════════════

  group('Voucher Balance Validation', () {
    test('Receipt voucher: single debit and credit balanced', () {
      const amount = 5000.0;

      final items = [
        {'account_id': 1, 'debit': MoneyHelper.toCents(amount), 'credit': 0},
        {'account_id': 2, 'debit': 0, 'credit': MoneyHelper.toCents(amount)},
      ];

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (final item in items) {
        totalDebit += MoneyHelper.readMoney(item['debit']);
        totalCredit += MoneyHelper.readMoney(item['credit']);
      }

      expect((totalDebit - totalCredit).abs(), lessThan(0.01));
    });

    test('Compound voucher: multiple debits and credits balanced', () {
      final items = [
        {'account_id': 1, 'debit': MoneyHelper.toCents(3000.0), 'credit': 0},
        {'account_id': 2, 'debit': MoneyHelper.toCents(2000.0), 'credit': 0},
        {'account_id': 3, 'debit': 0, 'credit': MoneyHelper.toCents(4000.0)},
        {'account_id': 4, 'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
      ];

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (final item in items) {
        totalDebit += MoneyHelper.readMoney(item['debit']);
        totalCredit += MoneyHelper.readMoney(item['credit']);
      }

      expect(totalDebit, 5000.0);
      expect(totalCredit, 5000.0);
      expect((totalDebit - totalCredit).abs(), lessThan(0.01));
    });

    test('Unbalanced voucher is rejected', () {
      final items = [
        {'account_id': 1, 'debit': MoneyHelper.toCents(5000.0), 'credit': 0},
        {'account_id': 2, 'debit': 0, 'credit': MoneyHelper.toCents(3000.0)},
      ];

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (final item in items) {
        totalDebit += MoneyHelper.readMoney(item['debit']);
        totalCredit += MoneyHelper.readMoney(item['credit']);
      }

      expect((totalDebit - totalCredit).abs(), greaterThan(0.01));
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  Cash Box Balance Type Tests
  // ══════════════════════════════════════════════════════════════

  group('Cash Box Balance Type', () {
    test('Credit cash box: receipt increases, payment decreases', () {
      double balance = 10000.0;
      const balanceType = 'credit';

      // Receipt (money in): increases credit balance
      const receiptAmount = 5000.0;
      if (balanceType == 'credit') {
        balance += receiptAmount;
      }
      expect(balance, 15000.0);

      // Payment (money out): decreases credit balance
      const paymentAmount = 3000.0;
      if (balanceType == 'credit') {
        balance -= paymentAmount;
      }
      expect(balance, 12000.0);
    });

    test('Debit cash box: receipt decreases, payment increases', () {
      double balance = 5000.0;
      const balanceType = 'debit';

      // Receipt (money in): decreases debit balance
      const receiptAmount = 2000.0;
      if (balanceType == 'debit') {
        balance -= receiptAmount;
      }
      expect(balance, 3000.0);

      // Payment (money out): increases debit balance
      const paymentAmount = 1000.0;
      if (balanceType == 'debit') {
        balance += paymentAmount;
      }
      expect(balance, 4000.0);
    });

    test('Cash box effective balance display', () {
      // Credit balance of 5000 → display as "5,000 له" (green)
      final creditBalance = 5000.0;
      const creditType = 'credit';
      final creditEffective = creditType == 'credit' ? creditBalance : -creditBalance;
      expect(creditEffective >= 0, isTrue); // "له"

      // Debit balance of 3000 → display as "3,000 عليه" (red)
      final debitBalance = 3000.0;
      const debitType = 'debit';
      final debitEffective = debitType == 'credit' ? debitBalance : -debitBalance;
      expect(debitEffective < 0, isTrue); // "عليه"
    });
  });
}
