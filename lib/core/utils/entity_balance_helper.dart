import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';

/// EntityBalanceHelper — Unified balance update logic for entities
/// (customers, suppliers, employees) that correctly handles the
/// balance_type flip when the balance crosses zero.
///
/// Convention:
///   balance column = MAGNITUDE (always >= 0)
///   balance_type   = DIRECTION ('credit' = له, 'debit' = عليه)
///
///   Signed value:  credit → +balance, debit → -balance
///
///   For customers:
///     +positive (credit/له) = we owe the customer
///     -negative (debit/عليه) = customer owes us
///
///   For suppliers:
///     +positive (credit/له) = we owe the supplier
///     -negative (debit/عليه) = supplier owes us
class EntityBalanceHelper {
  EntityBalanceHelper._();

  /// Apply a signed change to an entity's balance, flipping balance_type
  /// if the balance crosses zero.
  ///
  /// [txn] - Database transaction
  /// [tableName] - 'customers', 'suppliers', or 'employees'
  /// [entityId] - Row ID
  /// [signedChange] - The change to apply in signed terms:
  ///   - Positive = increases credit (له) position
  ///   - Negative = increases debit (عليه) position
  /// [now] - Current timestamp for updated_at
  static Future<void> applyBalanceChange({
    required Transaction txn,
    required String tableName,
    required int entityId,
    required double signedChange,
    required String now,
  }) async {
    if (signedChange.abs() < 0.005) return; // No meaningful change

    final rows = await txn.query(
      tableName,
      where: 'id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final currentBalance = MoneyHelper.readMoney(rows.first['balance']);
    final currentType = rows.first['balance_type'] as String? ?? 'credit';

    // Convert to signed value
    double signedBalance =
        currentType == 'credit' ? currentBalance : -currentBalance;

    // Apply the change
    signedBalance += signedChange;

    // Convert back to magnitude + direction
    final newBalance = signedBalance.abs();
    final newType = signedBalance >= 0 ? 'credit' : 'debit';

    await txn.update(
      tableName,
      {
        'balance': MoneyHelper.toCents(newBalance),
        'balance_type': newType,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  /// Apply balance change for a customer based on the accounting effect.
  ///
  /// [creditEffect] - Amount that increases the customer's credit (له) position
  ///   e.g., receipt from customer reduces what they owe us → credit effect
  /// [debitEffect] - Amount that increases the customer's debit (عليه) position
  ///   e.g., sale invoice on credit → they owe us more → debit effect
  static Future<void> applyCustomerBalanceChange({
    required Transaction txn,
    required int customerId,
    required double creditEffect,
    required double debitEffect,
    required String now,
  }) async {
    // In signed terms: credit increases (+), debit decreases (-)
    final signedChange = creditEffect - debitEffect;
    await applyBalanceChange(
      txn: txn,
      tableName: 'customers',
      entityId: customerId,
      signedChange: signedChange,
      now: now,
    );
  }

  /// Apply balance change for a supplier based on the accounting effect.
  ///
  /// [creditEffect] - Amount that increases the supplier's credit (له) position
  ///   e.g., purchase invoice on credit → we owe them more → credit effect
  /// [debitEffect] - Amount that increases the supplier's debit (عليه) position
  ///   e.g., payment to supplier reduces what we owe → debit effect
  static Future<void> applySupplierBalanceChange({
    required Transaction txn,
    required int supplierId,
    required double creditEffect,
    required double debitEffect,
    required String now,
  }) async {
    // In signed terms: credit increases (+), debit decreases (-)
    final signedChange = creditEffect - debitEffect;
    await applyBalanceChange(
      txn: txn,
      tableName: 'suppliers',
      entityId: supplierId,
      signedChange: signedChange,
      now: now,
    );
  }

  /// Apply balance change for an employee based on the accounting effect.
  ///
  /// [creditEffect] - Amount that increases the employee's credit (له) position
  ///   e.g., salary payment → employee earns money → credit effect
  /// [debitEffect] - Amount that increases the employee's debit (عليه) position
  ///   e.g., advance payment → employee owes money → debit effect
  static Future<void> applyEmployeeBalanceChange({
    required Transaction txn,
    required int employeeId,
    required double creditEffect,
    required double debitEffect,
    required String now,
  }) async {
    final signedChange = creditEffect - debitEffect;
    await applyBalanceChange(
      txn: txn,
      tableName: 'employees',
      entityId: employeeId,
      signedChange: signedChange,
      now: now,
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Convenience methods for common operations
  // ══════════════════════════════════════════════════════════════

  /// Customer: Sale invoice on credit → customer owes us more (debit effect)
  static Future<void> customerSaleOnCredit({
    required Transaction txn,
    required int customerId,
    required double amount,
    required String now,
  }) async {
    await applyCustomerBalanceChange(
      txn: txn,
      customerId: customerId,
      creditEffect: 0,
      debitEffect: amount,
      now: now,
    );
  }

  /// Customer: Sale return → we owe customer more (credit effect)
  static Future<void> customerSaleReturn({
    required Transaction txn,
    required int customerId,
    required double amount,
    required String now,
  }) async {
    await applyCustomerBalanceChange(
      txn: txn,
      customerId: customerId,
      creditEffect: amount,
      debitEffect: 0,
      now: now,
    );
  }

  /// Customer: Receipt (سند قبض) → customer pays us → reduces what they owe (credit effect)
  static Future<void> customerReceipt({
    required Transaction txn,
    required int customerId,
    required double amount,
    required String now,
  }) async {
    await applyCustomerBalanceChange(
      txn: txn,
      customerId: customerId,
      creditEffect: amount,
      debitEffect: 0,
      now: now,
    );
  }

  /// Customer: Payment (سند صرف) → we pay customer → they owe us more (debit effect)
  static Future<void> customerPayment({
    required Transaction txn,
    required int customerId,
    required double amount,
    required String now,
  }) async {
    await applyCustomerBalanceChange(
      txn: txn,
      customerId: customerId,
      creditEffect: 0,
      debitEffect: amount,
      now: now,
    );
  }

  /// Supplier: Purchase invoice on credit → we owe supplier more (credit effect)
  static Future<void> supplierPurchaseOnCredit({
    required Transaction txn,
    required int supplierId,
    required double amount,
    required String now,
  }) async {
    await applySupplierBalanceChange(
      txn: txn,
      supplierId: supplierId,
      creditEffect: amount,
      debitEffect: 0,
      now: now,
    );
  }

  /// Supplier: Purchase return → supplier owes us more (debit effect)
  static Future<void> supplierPurchaseReturn({
    required Transaction txn,
    required int supplierId,
    required double amount,
    required String now,
  }) async {
    await applySupplierBalanceChange(
      txn: txn,
      supplierId: supplierId,
      creditEffect: 0,
      debitEffect: amount,
      now: now,
    );
  }

  /// Supplier: Payment (سند صرف) → we pay supplier → reduces what we owe (debit effect)
  static Future<void> supplierPayment({
    required Transaction txn,
    required int supplierId,
    required double amount,
    required String now,
  }) async {
    await applySupplierBalanceChange(
      txn: txn,
      supplierId: supplierId,
      creditEffect: 0,
      debitEffect: amount,
      now: now,
    );
  }

  /// Supplier: Receipt (سند قبض) → supplier pays us (e.g., refund/return)
  /// Accounting entry: Debit Cash, Credit Suppliers → supplier account is CREDITED
  /// This INCREASES the supplier's credit position (له) because:
  ///   - If supplier refunds us for a return, we now owe them more (credit increases)
  ///   - In signed terms: signedChange = +amount (credit effect)
  static Future<void> supplierReceipt({
    required Transaction txn,
    required int supplierId,
    required double amount,
    required String now,
  }) async {
    await applySupplierBalanceChange(
      txn: txn,
      supplierId: supplierId,
      creditEffect: amount,
      debitEffect: 0,
      now: now,
    );
  }
}
