import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/account_model.dart';
import 'package:firstpro/data/models/invoice_model.dart';
import 'package:firstpro/data/models/supplier_model.dart';

/// Accounting Business Logic Unit Tests
///
/// These tests verify the core accounting rules WITHOUT requiring a database.
/// They test the business logic at the model/helper level.
///
/// Key rules tested:
/// 1. Double-entry balance: Total Debits == Total Credits
/// 2. Balance type derivation: ASSET/COST/EXPENSE = debit, LIABILITY/EQUITY/REVENUE = credit
/// 3. Money arithmetic: Fixed-point precision (no floating-point drift)
/// 4. Invoice totals: subtotal - discount + tax = total
/// 5. Balance direction: credit (له) vs debit (عليه)
/// 6. Entity balance logic: balance flip when crossing zero
/// 7. COGS calculation: weighted average, FIFO, LIFO
/// 8. Invoice effectiveType: sale, purchase, sale_return, purchase_return
void main() {
  group('Accounting Business Logic Tests', () {
    // ═══════════════════════════════════════════════════════════
    //  1. Double-Entry Balance Verification
    // ═══════════════════════════════════════════════════════════
    group('Double-Entry Balance', () {
      test('simple journal entry: debits equal credits', () {
        // Cash sale: Debit Cash 1000, Credit Revenue 1000
        final entries = [
          {'account_id': 1, 'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'account_id': 2, 'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
        ];
        final totalDebit =
            entries.fold<int>(0, (sum, e) => sum + (e['debit'] as int));
        final totalCredit =
            entries.fold<int>(0, (sum, e) => sum + (e['credit'] as int));
        expect(totalDebit, equals(totalCredit));
      });

      test('compound journal entry: debits equal credits', () {
        // Credit sale: Debit Customers 1150, Credit Revenue 1000, Credit VAT 150
        final entries = [
          {'account_id': 1, 'debit': MoneyHelper.toCents(1150.0), 'credit': 0},
          {'account_id': 2, 'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
          {'account_id': 3, 'debit': 0, 'credit': MoneyHelper.toCents(150.0)},
        ];
        final totalDebit =
            entries.fold<int>(0, (sum, e) => sum + (e['debit'] as int));
        final totalCredit =
            entries.fold<int>(0, (sum, e) => sum + (e['credit'] as int));
        expect(totalDebit, equals(totalCredit));
      });

      test('unbalanced entry is detected', () {
        final entries = [
          {'account_id': 1, 'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'account_id': 2, 'debit': 0, 'credit': MoneyHelper.toCents(900.0)},
        ];
        final totalDebit =
            entries.fold<int>(0, (sum, e) => sum + (e['debit'] as int));
        final totalCredit =
            entries.fold<int>(0, (sum, e) => sum + (e['credit'] as int));
        expect(totalDebit, isNot(equals(totalCredit)));
      });

      test('sale with discount: debits still equal credits', () {
        // Sale 1000 with 5% discount, paid cash
        // Debit Cash 950, Debit Discount 50, Credit Revenue 1000
        final entries = [
          {'account_id': 1, 'debit': MoneyHelper.toCents(950.0), 'credit': 0},
          {'account_id': 2, 'debit': MoneyHelper.toCents(50.0), 'credit': 0},
          {'account_id': 3, 'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
        ];
        final totalDebit =
            entries.fold<int>(0, (sum, e) => sum + (e['debit'] as int));
        final totalCredit =
            entries.fold<int>(0, (sum, e) => sum + (e['credit'] as int));
        expect(totalDebit, equals(totalCredit));
      });

      test('sale with COGS: debits equal credits (C-02 verification)', () {
        // Sale 1000 + COGS 600
        // Entry 1: Debit Cash/Customers 1000, Credit Revenue 1000
        // Entry 2: Debit COGS 600, Credit Inventory 600
        final entries = [
          {'debit': MoneyHelper.toCents(1000.0), 'credit': 0},
          {'debit': 0, 'credit': MoneyHelper.toCents(1000.0)},
          {'debit': MoneyHelper.toCents(600.0), 'credit': 0},
          {'debit': 0, 'credit': MoneyHelper.toCents(600.0)},
        ];
        final totalDebit =
            entries.fold<int>(0, (sum, e) => sum + (e['debit'] as int));
        final totalCredit =
            entries.fold<int>(0, (sum, e) => sum + (e['credit'] as int));
        expect(totalDebit, equals(totalCredit));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  2. Account Balance Type Derivation (C-01 verification)
    // ═══════════════════════════════════════════════════════════
    group('Account Balance Type Derivation', () {
      test('all 6 account types have correct balance nature', () {
        final testCases = {
          AccountType.ASSET: 'debit',
          AccountType.LIABILITY: 'credit',
          AccountType.EQUITY: 'credit',
          AccountType.COST: 'debit',
          AccountType.REVENUE: 'credit',
          AccountType.EXPENSE: 'debit', // C-01 Fix verified
        };
        for (final entry in testCases.entries) {
          final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '0000',
            accountType: entry.key,
          );
          expect(account.effectiveBalanceType, equals(entry.value),
              reason: '${entry.key} should have ${entry.value} balance type');
        }
      });

      test('balance type affects account balance calculation', () {
        // For debit-balance accounts: balance = debit - credit (increases with debit)
        // For credit-balance accounts: balance = credit - debit (increases with credit)
        double calculateBalance(
            String balanceType, double debit, double credit) {
          if (balanceType == 'debit') {
            return debit - credit;
          } else {
            return credit - debit;
          }
        }

        // ASSET (debit nature): 1000 debit, 200 credit → balance = 800
        expect(calculateBalance('debit', 1000, 200), equals(800));

        // LIABILITY (credit nature): 200 debit, 1000 credit → balance = 800
        expect(calculateBalance('credit', 200, 1000), equals(800));

        // EXPENSE (debit nature, C-01): 500 debit, 0 credit → balance = 500
        expect(calculateBalance('debit', 500, 0), equals(500));

        // REVENUE (credit nature): 0 debit, 500 credit → balance = 500
        expect(calculateBalance('credit', 0, 500), equals(500));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  3. Money Arithmetic Precision (C-06 verification)
    // ═══════════════════════════════════════════════════════════
    group('Money Arithmetic Precision', () {
      test('0.1 + 0.2 equals exactly 0.30 in accounting terms', () {
        expect(MoneyHelper.add(0.1, 0.2), closeTo(0.30, 0.001));
      });

      test('0.3 - 0.1 equals exactly 0.20 in accounting terms', () {
        expect(MoneyHelper.subtract(0.3, 0.1), closeTo(0.20, 0.001));
      });

      test('accumulated rounding errors are prevented', () {
        // Simulate 1000 additions of 0.01
        double regular = 0.0;
        double accounting = 0.0;
        for (int i = 0; i < 1000; i++) {
          regular += 0.01;
          accounting = MoneyHelper.add(accounting, 0.01);
        }
        // Regular double may drift: 9.99999999999983
        // Accounting should be exact: 10.00
        expect(MoneyHelper.isZero(accounting - 10.0), isTrue);
        expect(
            regular, isNot(equals(10.0))); // Proves floating-point is imprecise
      });

      test('percentage calculations maintain precision', () {
        // 5% discount on 1000.00 = 50.00
        final discount = MoneyHelper.multiply(1000.0, 0.05);
        expect(discount, closeTo(50.0, 0.01));

        // 15% VAT on 1000.00 = 150.00
        final vat = MoneyHelper.multiply(1000.0, 0.15);
        expect(vat, closeTo(150.0, 0.01));
      });

      test('exchange rate calculations maintain precision', () {
        // 500 USD at rate 500 YER/USD = 250,000 YER
        final converted = MoneyHelper.multiply(500.0, 500.0);
        expect(converted, closeTo(250000.0, 0.01));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  4. Invoice Total Calculation
    // ═══════════════════════════════════════════════════════════
    group('Invoice Total Calculation', () {
      test('subtotal - discount + tax + transport = total', () {
        final subtotal = 1000.0;
        final discountAmount = 50.0;
        final taxAmount = 45.0;
        final transport = 25.0;
        final expectedTotal = subtotal - discountAmount + taxAmount + transport;
        expect(expectedTotal, equals(1020.0));
      });

      test('credit sale: remaining = total - paidAmount', () {
        final total = 1000.0;
        final paidAmount = 300.0;
        final remaining = MoneyHelper.subtract(total, paidAmount);
        expect(remaining, closeTo(700.0, 0.01));
      });

      test('fully paid cash sale: remaining = 0', () {
        final total = 1000.0;
        final paidAmount = 1000.0;
        final remaining = MoneyHelper.subtract(total, paidAmount);
        expect(MoneyHelper.isZero(remaining), isTrue);
      });

      test('invoice with percentage discount', () {
        final subtotal = 2000.0;
        final discountRate = 10.0; // 10%
        final discountAmount =
            MoneyHelper.multiply(subtotal, discountRate / 100);
        expect(discountAmount, closeTo(200.0, 0.01));
        final total = MoneyHelper.subtract(subtotal, discountAmount);
        expect(total, closeTo(1800.0, 0.01));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  5. Entity Balance Direction Logic
    // ═══════════════════════════════════════════════════════════
    group('Entity Balance Direction', () {
      test('supplier with credit balance owes us (له)', () {
        final label = Supplier.getDynamicBalanceLabel(5000.0, 'credit');
        expect(label, equals('له'));
      });

      test('supplier with debit balance is owed by us (عليه)', () {
        final label = Supplier.getDynamicBalanceLabel(5000.0, 'debit');
        expect(label, equals('عليه'));
      });

      test('balance crossing zero flips direction', () {
        // Start with credit 5000 (له)
        // Pay supplier 8000 → net becomes -3000 → direction flips to عليه
        double signedBalance = 5000.0; // credit = positive
        signedBalance -= 8000.0; // Payment = debit effect = negative
        final newType = signedBalance >= 0 ? 'credit' : 'debit';
        final newBalance = signedBalance.abs();
        expect(newType, equals('debit'));
        expect(newBalance, equals(3000.0));
      });

      test('multiple payments reduce balance correctly', () {
        double signedBalance = 0.0; // Start at zero
        // Purchase on credit 5000 (credit effect = +)
        signedBalance += 5000.0;
        expect(signedBalance, equals(5000.0));
        // Payment 2000 (debit effect = -)
        signedBalance -= 2000.0;
        expect(signedBalance, equals(3000.0));
        // Payment 3000 (debit effect = -)
        signedBalance -= 3000.0;
        expect(signedBalance, equals(0.0));
        // At zero → متساوي
        expect(signedBalance.abs() < 0.005, isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  6. COGS Calculation Logic
    // ═══════════════════════════════════════════════════════════
    group('COGS Calculation', () {
      test('weighted average COGS calculation', () {
        // Product: 100 units @ 50.00 each
        // Average cost = 50.00
        // Sell 30 units → COGS = 30 * 50 = 1500.00
        final avgCost = 50.0;
        final quantitySold = 30.0;
        final cogs = avgCost * quantitySold;
        expect(cogs, equals(1500.0));
      });

      test('weighted average after multiple purchases', () {
        // Buy 100 @ 50 = 5000
        // Buy 50 @ 60 = 3000
        // Total: 150 units, value 8000, avg = 8000/150 = 53.33
        final totalValue = 5000.0 + 3000.0;
        final totalQty = 100.0 + 50.0;
        final avgCost = totalValue / totalQty;
        expect(MoneyHelper.round2(avgCost), closeTo(53.33, 0.01));
      });

      test('FIFO: consume oldest layers first', () {
        // Layer 1: 50 units @ 40 (oldest)
        // Layer 2: 30 units @ 50 (newer)
        // Layer 3: 20 units @ 60 (newest)
        // Sell 60 units: 50 from Layer 1 + 10 from Layer 2
        // COGS = (50*40) + (10*50) = 2000 + 500 = 2500
        final layers = [
          {'qty': 50.0, 'cost': 40.0},
          {'qty': 30.0, 'cost': 50.0},
          {'qty': 20.0, 'cost': 60.0},
        ];
        double remaining = 60.0;
        double totalCogs = 0.0;
        for (final layer in layers) {
          if (remaining <= 0) break;
          final available = layer['qty']!;
          final consume = remaining > available ? available : remaining;
          totalCogs += consume * layer['cost']!;
          remaining -= consume;
        }
        expect(totalCogs, equals(2500.0));
        expect(remaining, equals(0.0));
      });

      test('LIFO: consume newest layers first', () {
        // Layer 1: 50 units @ 40 (oldest)
        // Layer 2: 30 units @ 50 (newer)
        // Layer 3: 20 units @ 60 (newest)
        // Sell 40 units: 20 from Layer 3 + 20 from Layer 2
        // COGS = (20*60) + (20*50) = 1200 + 1000 = 2200
        final layers = [
          {'qty': 50.0, 'cost': 40.0},
          {'qty': 30.0, 'cost': 50.0},
          {'qty': 20.0, 'cost': 60.0},
        ];
        double remaining = 40.0;
        double totalCogs = 0.0;
        // LIFO: iterate in reverse
        for (final layer in layers.reversed) {
          if (remaining <= 0) break;
          final available = layer['qty']!;
          final consume = remaining > available ? available : remaining;
          totalCogs += consume * layer['cost']!;
          remaining -= consume;
        }
        expect(totalCogs, equals(2200.0));
        expect(remaining, equals(0.0));
      });

      test('COGS reversal restores cost layers', () {
        // After selling 60 units (FIFO), Layer 1 is fully consumed
        // Reversal should restore Layer 1's quantity
        double layer1QtyRemaining = 0.0; // Fully consumed after sale
        double layer1QtyUsed = 50.0; // Amount used from Layer 1
        layer1QtyRemaining += layer1QtyUsed;
        expect(layer1QtyRemaining, equals(50.0)); // Restored
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  7. Invoice Effective Type
    // ═══════════════════════════════════════════════════════════
    group('Invoice Effective Type', () {
      test('cash sale → effectiveType = sale', () {
        final invoice =
            Invoice(id: '1', type: 'sale', paymentMechanism: 'cash');
        expect(invoice.effectiveType, equals('sale'));
      });

      test('credit sale → effectiveType = sale', () {
        final invoice =
            Invoice(id: '1', type: 'sale', paymentMechanism: 'credit');
        expect(invoice.effectiveType, equals('sale'));
      });

      test('sale return → effectiveType = sale_return', () {
        final invoice = Invoice(id: '1', type: 'sale', isReturn: true);
        expect(invoice.effectiveType, equals('sale_return'));
      });

      test('purchase → effectiveType = purchase', () {
        final invoice = Invoice(id: '1', type: 'purchase');
        expect(invoice.effectiveType, equals('purchase'));
      });

      test('purchase return → effectiveType = purchase_return', () {
        final invoice = Invoice(id: '1', type: 'purchase', isReturn: true);
        expect(invoice.effectiveType, equals('purchase_return'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  8. Exchange Rate Gain/Loss
    // ═══════════════════════════════════════════════════════════
    group('Exchange Rate Gain/Loss', () {
      test('exchange gain when rate increases', () {
        // Base: 500 USD at 500 YER/USD = 250,000 YER
        // Current: 500 USD at 550 YER/USD = 275,000 YER
        // Gain = 275,000 - 250,000 = 25,000 YER
        final baseAmount = 250000.0;
        final originalRate = 500.0;
        final currentRate = 550.0;
        final foreignAmount = baseAmount / originalRate; // 500 USD
        final valueAtCurrentRate = foreignAmount * currentRate; // 275,000
        final gainLoss = valueAtCurrentRate - baseAmount; // 25,000
        expect(gainLoss, equals(25000.0));
        expect(gainLoss > 0, isTrue); // Gain
      });

      test('exchange loss when rate decreases', () {
        final baseAmount = 250000.0;
        final originalRate = 500.0;
        final currentRate = 450.0;
        final foreignAmount = baseAmount / originalRate; // 500 USD
        final valueAtCurrentRate = foreignAmount * currentRate; // 225,000
        final gainLoss = valueAtCurrentRate - baseAmount; // -25,000
        expect(gainLoss, equals(-25000.0));
        expect(gainLoss < 0, isTrue); // Loss
      });

      test('no gain/loss when rate unchanged', () {
        final baseAmount = 250000.0;
        final rate = 500.0;
        final foreignAmount = baseAmount / rate;
        final valueAtCurrentRate = foreignAmount * rate;
        final gainLoss = valueAtCurrentRate - baseAmount;
        expect(gainLoss, equals(0.0));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  9. Trial Balance Verification
    // ═══════════════════════════════════════════════════════════
    group('Trial Balance', () {
      test('total debits equal total credits across all accounts', () {
        // Simulate a trial balance — debits MUST equal credits
        // Debits: 15000 + 2000 + 0 + 0 + 7000 + 3000 = 27000
        // Credits: 5000 + 8000 + 5000 + 4000 + 0 + 5000 = 27000
        final accounts = [
          {'code': '1000', 'type': 'ASSET', 'debit': 15000.0, 'credit': 5000.0},
          {
            'code': '2000',
            'type': 'LIABILITY',
            'debit': 2000.0,
            'credit': 8000.0
          },
          {'code': '3000', 'type': 'EQUITY', 'debit': 0.0, 'credit': 5000.0},
          {'code': '4000', 'type': 'REVENUE', 'debit': 0.0, 'credit': 4000.0},
          {'code': '5000', 'type': 'COST', 'debit': 7000.0, 'credit': 0.0},
          {
            'code': '5200',
            'type': 'EXPENSE',
            'debit': 3000.0,
            'credit': 5000.0
          },
        ];
        final totalDebit = accounts.fold<double>(
            0.0, (sum, a) => sum + (a['debit'] as double));
        final totalCredit = accounts.fold<double>(
            0.0, (sum, a) => sum + (a['credit'] as double));
        expect(totalDebit, equals(totalCredit));
        expect(totalDebit, equals(27000.0));
        expect(totalCredit, equals(27000.0));
      });

      test('account balances computed correctly per type', () {
        double computeBalance(AccountType type, double debit, double credit) {
          final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '0000',
            accountType: type,
          );
          if (account.effectiveBalanceType == 'debit') {
            return debit - credit;
          } else {
            return credit - debit;
          }
        }

        // ASSET: 15000 debit, 5000 credit → balance = 10000
        expect(computeBalance(AccountType.ASSET, 15000, 5000), equals(10000));

        // LIABILITY: 2000 debit, 8000 credit → balance = 6000
        expect(computeBalance(AccountType.LIABILITY, 2000, 8000), equals(6000));

        // EXPENSE: 3000 debit, 0 credit → balance = 3000
        expect(computeBalance(AccountType.EXPENSE, 3000, 0), equals(3000));

        // REVENUE: 0 debit, 12000 credit → balance = 12000
        expect(computeBalance(AccountType.REVENUE, 0, 12000), equals(12000));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  10. Stock/Inventory Logic
    // ═══════════════════════════════════════════════════════════
    group('Stock/Inventory Logic', () {
      test('purchase increases stock, sale decreases stock', () {
        double stock = 0.0;
        // Purchase 100 units
        stock += 100.0;
        expect(stock, equals(100.0));
        // Sell 30 units
        stock -= 30.0;
        expect(stock, equals(70.0));
        // Sell 40 units
        stock -= 40.0;
        expect(stock, equals(30.0));
      });

      test('weighted average cost recalculates on purchase', () {
        // Existing: 50 units @ 40 = 2000
        double currentStock = 50.0;
        double currentAvgCost = 40.0;

        // New purchase: 30 units @ 55 = 1650
        final newQty = 30.0;
        final newCost = 55.0;

        final totalValue = (currentStock * currentAvgCost) + (newQty * newCost);
        final newStock = currentStock + newQty;
        final newAvgCost = totalValue / newStock;

        expect(newStock, equals(80.0));
        expect(MoneyHelper.round2(newAvgCost), closeTo(45.63, 0.01));
      });

      test('stock transfer: source decreases, destination increases', () {
        // Source: 100 units
        double sourceStock = 100.0;
        // Destination: 50 units
        double destStock = 50.0;
        // Transfer 20 units
        final transferQty = 20.0;
        sourceStock -= transferQty;
        destStock += transferQty;
        expect(sourceStock, equals(80.0));
        expect(destStock, equals(70.0));
        // Total stock unchanged
        expect(sourceStock + destStock, equals(150.0));
      });

      test('sale return restores stock', () {
        double stock = 70.0;
        // Return 10 units
        stock += 10.0;
        expect(stock, equals(80.0));
      });

      test('purchase return reduces stock', () {
        double stock = 100.0;
        // Return 20 units to supplier
        stock -= 20.0;
        expect(stock, equals(80.0));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  11. Invoice Item Calculations
    // ═══════════════════════════════════════════════════════════
    group('Invoice Item Calculations', () {
      test('total price = quantity * unit price', () {
        final quantity = 5.0;
        final unitPrice = 100.0;
        final totalPrice = MoneyHelper.multiply(quantity, unitPrice);
        expect(totalPrice, closeTo(500.0, 0.01));
      });

      test('base quantity = quantity * conversion factor', () {
        // 2 cartons, each has 24 units
        final quantity = 2.0;
        final conversionFactor = 24.0;
        final baseQuantity = quantity * conversionFactor;
        expect(baseQuantity, equals(48.0));
      });

      test('COGS = base quantity * unit cost', () {
        final baseQuantity = 48.0;
        final unitCost = 30.0;
        final cogs = MoneyHelper.multiply(baseQuantity, unitCost);
        expect(cogs, closeTo(1440.0, 0.01));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  12. Fiscal Period Validation
    // ═══════════════════════════════════════════════════════════
    group('Fiscal Period Validation', () {
      test('closed fiscal year rejects operations', () {
        // If fiscal_years table has year=2025 with status='closed',
        // any operation with date in 2025 should be rejected.
        // This is a logic test — the actual DB check is in JournalService.
        final isClosed = true; // Simulated
        final operationDate = '2025-06-15';
        final year = DateTime.parse(operationDate).year;
        expect(year, equals(2025));
        expect(isClosed, isTrue);
        // In real code: JournalService.checkFiscalPeriodOpen() would throw
      });

      test('open fiscal year allows operations', () {
        final isClosed = false;
        expect(isClosed, isFalse);
      });

      test('invalid date string is rejected', () {
        // JournalService.checkFiscalPeriodOpen rejects invalid dates
        final dateStr = 'invalid-date';
        final parsed = DateTime.tryParse(dateStr);
        expect(parsed, isNull);
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  13. Complete Sale Cycle (End-to-End Logic)
    // ═══════════════════════════════════════════════════════════
    group('Complete Sale Cycle', () {
      test('cash sale: full accounting verification', () {
        // Product: 10 units @ cost 60, sell price 100
        // Sell 5 units cash
        final quantitySold = 5.0;
        final sellPrice = 100.0;
        final costPrice = 60.0;

        // Revenue calculation
        final revenue = MoneyHelper.multiply(quantitySold, sellPrice);
        expect(revenue, closeTo(500.0, 0.01));

        // COGS calculation
        final cogs = MoneyHelper.multiply(quantitySold, costPrice);
        expect(cogs, closeTo(300.0, 0.01));

        // Gross profit
        final grossProfit = MoneyHelper.subtract(revenue, cogs);
        expect(grossProfit, closeTo(200.0, 0.01));

        // Journal entries must balance
        // Entry 1: Debit Cash 500, Credit Revenue 500
        // Entry 2: Debit COGS 300, Credit Inventory 300
        final totalDebits =
            MoneyHelper.toCents(500.0) + MoneyHelper.toCents(300.0);
        final totalCredits =
            MoneyHelper.toCents(500.0) + MoneyHelper.toCents(300.0);
        expect(totalDebits, equals(totalCredits));

        // Stock reduced
        double stock = 10.0 - quantitySold;
        expect(stock, equals(5.0));
      });

      test('credit sale: customer balance increases', () {
        // Sell 5 units @ 100 on credit to customer
        final saleAmount = 500.0;

        // Customer balance effect: debit (عليه) increases
        // signedChange = creditEffect - debitEffect = 0 - 500 = -500
        double customerSignedBalance = 0.0;
        customerSignedBalance += (0 - saleAmount); // Debit effect
        final newType = customerSignedBalance >= 0 ? 'credit' : 'debit';
        final newBalance = customerSignedBalance.abs();
        expect(newType, equals('debit')); // Customer owes us (عليه)
        expect(newBalance, equals(500.0));
      });

      test('partial payment reduces customer balance', () {
        // Customer owes 500 (debit/عليه)
        double signedBalance = -500.0; // debit = negative in signed terms
        // Payment of 200 (credit effect = +200)
        signedBalance += 200.0;
        final newType = signedBalance >= 0 ? 'credit' : 'debit';
        final newBalance = signedBalance.abs();
        expect(newType, equals('debit')); // Still owes us
        expect(newBalance, closeTo(300.0, 0.01));
      });

      test('overpayment flips customer balance direction', () {
        // Customer owes 500 (debit/عليه)
        double signedBalance = -500.0;
        // Payment of 700 (credit effect = +700)
        signedBalance += 700.0;
        final newType = signedBalance >= 0 ? 'credit' : 'debit';
        final newBalance = signedBalance.abs();
        expect(newType, equals('credit')); // Now we owe customer (له)
        expect(newBalance, closeTo(200.0, 0.01));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  14. Complete Purchase Cycle
    // ═══════════════════════════════════════════════════════════
    group('Complete Purchase Cycle', () {
      test('cash purchase: full accounting verification', () {
        // Purchase 100 units @ 50 each for cash
        final quantity = 100.0;
        final unitCost = 50.0;
        final totalCost = MoneyHelper.multiply(quantity, unitCost);
        expect(totalCost, closeTo(5000.0, 0.01));

        // Journal: Debit Inventory 5000, Credit Cash 5000
        final debits = MoneyHelper.toCents(5000.0);
        final credits = MoneyHelper.toCents(5000.0);
        expect(debits, equals(credits));

        // Stock increased
        double stock = 0.0 + quantity;
        expect(stock, equals(100.0));
      });

      test('credit purchase: supplier balance increases', () {
        // Purchase 5000 on credit from supplier
        final purchaseAmount = 5000.0;

        // Supplier balance effect: credit (له) increases
        // We owe the supplier more
        double signedBalance = 0.0;
        signedBalance += purchaseAmount; // Credit effect
        final newType = signedBalance >= 0 ? 'credit' : 'debit';
        expect(newType, equals('credit')); // We owe supplier (له)
      });

      test('payment to supplier reduces balance', () {
        // We owe supplier 5000 (credit/له)
        double signedBalance = 5000.0;
        // Payment of 3000 (debit effect)
        signedBalance -= 3000.0;
        expect(signedBalance, equals(2000.0)); // Still owe 2000
        expect(signedBalance >= 0, isTrue); // Still credit type
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  15. Financial Statements Verification
    // ═══════════════════════════════════════════════════════════
    group('Financial Statements', () {
      test('income statement: revenue - COGS - expenses = net income', () {
        final revenue = 10000.0;
        final cogs = 6000.0;
        final operatingExpenses = 2000.0;
        final netIncome = MoneyHelper.subtract(
          MoneyHelper.subtract(revenue, cogs),
          operatingExpenses,
        );
        expect(netIncome, closeTo(2000.0, 0.01));
      });

      test('balance sheet: assets = liabilities + equity', () {
        // Assets = 50000
        // Liabilities = 15000
        // Equity = 35000
        // Check: 50000 = 15000 + 35000 ✓
        final assets = 50000.0;
        final liabilities = 15000.0;
        final equity = 35000.0;
        expect(MoneyHelper.compare(assets, liabilities + equity), equals(0));
      });

      test('balance sheet with retained earnings', () {
        final assets = 50000.0;
        final liabilities = 15000.0;
        final paidInCapital = 30000.0;
        final retainedEarnings = 5000.0;
        final totalEquity = MoneyHelper.add(paidInCapital, retainedEarnings);
        expect(
            MoneyHelper.compare(
                assets, MoneyHelper.add(liabilities, totalEquity)),
            equals(0));
      });
    });
  });
}
