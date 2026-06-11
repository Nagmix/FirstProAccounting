import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/models/account_model.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Account Model Unit Tests
/// Tests the Account domain model including:
/// - Construction and default values
/// - effectiveBalanceType derivation (critical accounting logic)
/// - currencySymbol mapping
/// - toMap/fromMap serialization round-trip
/// - copyWith functionality
void main() {
  group('Account Model', () {
    // ═══════════════════════════════════════════════════════════
    //  Construction and Defaults
    // ═══════════════════════════════════════════════════════════
    group('construction', () {
      test('creates account with required fields only', () {
        final account =
            Account(nameAr: 'النقدية', nameEn: 'Cash', accountCode: '1000');
        expect(account.nameAr, equals('النقدية'));
        expect(account.nameEn, equals('Cash'));
        expect(account.accountCode, equals('1000'));
        expect(account.id, isNull);
        expect(account.balance, equals(0.0));
        expect(account.currency, equals('YER'));
        expect(account.isActive, isTrue);
        expect(account.isSystem, isFalse);
      });

      test('creates account with all fields', () {
        final account = Account(
          id: 1,
          nameAr: 'النقدية',
          nameEn: 'Cash',
          parentId: 5,
          accountCode: '1100',
          accountType: AccountType.ASSET,
          balance: 5000.0,
          currency: 'SAR',
          debtCeiling: 10000.0,
          balanceType: 'debit',
          isActive: true,
          isSystem: true,
        );
        expect(account.id, equals(1));
        expect(account.balance, equals(5000.0));
        expect(account.currency, equals('SAR'));
        expect(account.debtCeiling, equals(10000.0));
        expect(account.balanceType, equals('debit'));
        expect(account.isSystem, isTrue);
      });

      test('defaults balanceType to auto', () {
        final account =
            Account(nameAr: 'Test', nameEn: 'Test', accountCode: '1000');
        expect(account.balanceType, equals('auto'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  effectiveBalanceType — CRITICAL Accounting Logic
    // ═══════════════════════════════════════════════════════════
    group('effectiveBalanceType', () {
      test('ASSET accounts have debit nature', () {
        final account = Account(
          nameAr: 'النقدية',
          nameEn: 'Cash',
          accountCode: '1000',
          accountType: AccountType.ASSET,
        );
        expect(account.effectiveBalanceType, equals('debit'));
      });

      test('COST accounts have debit nature', () {
        final account = Account(
          nameAr: 'تكلفة البضاعة',
          nameEn: 'COGS',
          accountCode: '5000',
          accountType: AccountType.COST,
        );
        expect(account.effectiveBalanceType, equals('debit'));
      });

      test('EXPENSE accounts have debit nature (Fix C-01)', () {
        // CRITICAL: Before C-01 fix, EXPENSE was returning 'credit' — WRONG!
        // Expenses increase with debit, so they must be debit nature.
        final account = Account(
          nameAr: 'مصاريف إدارية',
          nameEn: 'Admin Expenses',
          accountCode: '5200',
          accountType: AccountType.EXPENSE,
        );
        expect(account.effectiveBalanceType, equals('debit'));
      });

      test('LIABILITY accounts have credit nature', () {
        final account = Account(
          nameAr: 'الدائنون',
          nameEn: 'Payables',
          accountCode: '2000',
          accountType: AccountType.LIABILITY,
        );
        expect(account.effectiveBalanceType, equals('credit'));
      });

      test('EQUITY accounts have credit nature', () {
        final account = Account(
          nameAr: 'رأس المال',
          nameEn: 'Capital',
          accountCode: '3000',
          accountType: AccountType.EQUITY,
        );
        expect(account.effectiveBalanceType, equals('credit'));
      });

      test('REVENUE accounts have credit nature', () {
        final account = Account(
          nameAr: 'إيرادات المبيعات',
          nameEn: 'Sales Revenue',
          accountCode: '4000',
          accountType: AccountType.REVENUE,
        );
        expect(account.effectiveBalanceType, equals('credit'));
      });

      test('explicit balanceType overrides auto-derivation', () {
        final account = Account(
          nameAr: 'Test', nameEn: 'Test', accountCode: '1000',
          accountType: AccountType.ASSET,
          balanceType: 'credit', // Explicitly set, not auto
        );
        expect(account.effectiveBalanceType, equals('credit'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  currencySymbol — Currency Display
    // ═══════════════════════════════════════════════════════════
    group('currencySymbol', () {
      test('YER returns ر.ي', () {
        final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '1000',
            currency: 'YER');
        expect(account.currencySymbol, equals('ر.ي'));
      });

      test('SAR returns ر.س', () {
        final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '1000',
            currency: 'SAR');
        expect(account.currencySymbol, equals('ر.س'));
      });

      test(r'USD returns $', () {
        final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '1000',
            currency: 'USD');
        expect(account.currencySymbol, equals(r'$'));
      });

      test('unknown currency defaults to ر.ي', () {
        final account = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '1000',
            currency: 'EUR');
        expect(account.currencySymbol, equals('ر.ي'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  toMap / fromMap — Serialization
    // ═══════════════════════════════════════════════════════════
    group('serialization', () {
      test('toMap returns human-readable doubles', () {
        final account = Account(
          nameAr: 'النقدية',
          nameEn: 'Cash',
          accountCode: '1000',
          balance: 150.75,
          debtCeiling: 5000.50,
        );
        final map = account.toMap();
        expect(map['balance'], equals(150.75));
        expect(map['debt_ceiling'], equals(5000.50));
      });

      test('toMap saves effectiveBalanceType (not auto)', () {
        final account = Account(
          nameAr: 'Test',
          nameEn: 'Test',
          accountCode: '1000',
          accountType: AccountType.ASSET,
          balanceType: 'auto',
        );
        final map = account.toMap();
        expect(map['balance_type'], equals('debit')); // Derived, not 'auto'
      });

      test('toMap converts boolean fields to 0/1', () {
        final active = Account(
            nameAr: 'Test',
            nameEn: 'Test',
            accountCode: '1000',
            isActive: true,
            isSystem: false);
        expect(active.toMap()['is_active'], equals(1));
        expect(active.toMap()['is_system'], equals(0));
      });

      test('fromMap reads cents as double correctly', () {
        final map = {
          'id': 1,
          'name_ar': 'النقدية',
          'name_en': 'Cash',
          'parent_id': null,
          'account_code': '1000',
          'account_type': 'ASSET',
          'balance': 15075, // cents
          'currency': 'YER',
          'linked_cash_box_id': null,
          'is_active': 1,
          'debt_ceiling': 500050, // cents
          'balance_type': 'debit',
          'is_system': 0,
          'created_at': '2026-01-01T00:00:00.000',
          'updated_at': '2026-01-01T00:00:00.000',
        };
        final account = Account.fromMap(map);
        expect(account.balance, closeTo(150.75, 0.001));
        expect(account.debtCeiling, closeTo(5000.50, 0.001));
      });

      test('round-trip via toCentsMap preserves values', () {
        final original = Account(
          id: 1,
          nameAr: 'النقدية',
          nameEn: 'Cash',
          accountCode: '1100',
          accountType: AccountType.ASSET,
          balance: 5000.75,
          currency: 'SAR',
          debtCeiling: 10000.50,
          balanceType: 'debit',
          isActive: true,
          isSystem: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final dbMap = MoneyHelper.toCentsMap(original.toMap(), MoneyHelper.accountMoneyFields);
        final restored = Account.fromMap(dbMap);
        expect(restored.id, equals(original.id));
        expect(restored.nameAr, equals(original.nameAr));
        expect(restored.nameEn, equals(original.nameEn));
        expect(restored.accountCode, equals(original.accountCode));
        expect(restored.accountType, equals(original.accountType));
        expect(restored.balance, closeTo(original.balance, 0.01));
        expect(restored.currency, equals(original.currency));
        expect(restored.debtCeiling, closeTo(original.debtCeiling, 0.01));
        expect(restored.balanceType, equals('debit')); // Derived
        expect(restored.isActive, equals(original.isActive));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  AccountType helpers
    // ═══════════════════════════════════════════════════════════
    group('AccountType helpers', () {
      test('accountTypeAr returns correct Arabic names', () {
        expect(Account.accountTypeAr(AccountType.ASSET), equals('الأصول'));
        expect(Account.accountTypeAr(AccountType.LIABILITY), equals('الخصوم'));
        expect(
            Account.accountTypeAr(AccountType.EQUITY), equals('حقوق الملكية'));
        expect(Account.accountTypeAr(AccountType.COST), equals('التكاليف'));
        expect(Account.accountTypeAr(AccountType.REVENUE), equals('الإيرادات'));
        expect(Account.accountTypeAr(AccountType.EXPENSE), equals('المصاريف'));
      });
    });

    // ═══════════════════════════════════════════════════════════
    //  copyWith
    // ═══════════════════════════════════════════════════════════
    group('copyWith', () {
      test('copies with specific fields changed', () {
        final original = Account(
          id: 1,
          nameAr: 'النقدية',
          nameEn: 'Cash',
          accountCode: '1000',
          balance: 5000.0,
        );
        final modified = original.copyWith(balance: 6000.0, nameAr: 'البنك');
        expect(modified.balance, equals(6000.0));
        expect(modified.nameAr, equals('البنك'));
        expect(modified.nameEn, equals('Cash')); // Unchanged
        expect(modified.id, equals(1)); // Unchanged
      });

      test('copyWith preserves original when no changes', () {
        final original = Account(
          id: 1,
          nameAr: 'النقدية',
          nameEn: 'Cash',
          accountCode: '1000',
        );
        final copy = original.copyWith();
        expect(copy.nameAr, equals(original.nameAr));
        expect(copy.accountCode, equals(original.accountCode));
      });
    });
  });
}
