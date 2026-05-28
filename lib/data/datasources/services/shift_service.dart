import 'package:sqflite/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class ShiftService {
  final DatabaseHelper _dbHelper;
  ShiftService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Shift (وردية) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> openShift(Map<String, dynamic> shiftMap) async {
    final db = await _db;
    return await db.insert('shifts', shiftMap);
  }

  Future<Map<String, dynamic>?> getActiveShift(int cashBoxId) async {
    final db = await _db;
    final results = await db.query('shifts', where: 'cash_box_id = ? AND status = ?', whereArgs: [cashBoxId, 'open'], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getActiveShiftForCashier(int? cashierId) async {
    final db = await _db;
    if (cashierId == null) return null;
    final results = await db.query('shifts', where: 'cashier_id = ? AND status = ?', whereArgs: [cashierId, 'open'], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> closeShift(int shiftId, Map<String, dynamic> closeData) async {
    final db = await _db;
    return await db.update('shifts', closeData, where: 'id = ?', whereArgs: [shiftId]);
  }

  Future<List<Map<String, dynamic>>> getAllShifts({String orderBy = 'opened_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT s.*, cb.name AS cash_box_name
      FROM shifts s
      LEFT JOIN cash_boxes cb ON s.cash_box_id = cb.id
      ORDER BY s.$orderBy
    ''');
  }

  Future<String> getNextShiftNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'SH-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(shift_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM shifts WHERE shift_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  Future<void> updateShiftTotals(int shiftId, double saleAmount, double returnAmount, double discountAmount) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE shifts SET 
        total_sales = total_sales + ?,
        total_returns = total_returns + ?,
        total_discounts = total_discounts + ?,
        transaction_count = transaction_count + 1,
        expected_amount = opening_amount + total_sales + ? - total_returns - total_discounts - ?,
        updated_at = ?
      WHERE id = ?
    ''', [MoneyHelper.toCents(saleAmount), MoneyHelper.toCents(returnAmount), MoneyHelper.toCents(discountAmount), MoneyHelper.toCents(saleAmount), MoneyHelper.toCents(discountAmount), DateTime.now().toIso8601String(), shiftId]);
  }

  // ══════════════════════════════════════════════════════════════
  //  v12: Shift Invoice & Posting methods
  // ══════════════════════════════════════════════════════════════

  /// جلب جميع فواتير الوردية المحددة
  /// Get all invoices for a specific shift.
  Future<List<Map<String, dynamic>>> getShiftInvoices(int shiftId) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT i.*,
        CASE
          WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل')
          WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد')
          ELSE 'بدون عميل'
        END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      WHERE i.shift_id = ?
      ORDER BY i.created_at DESC
    ''', [shiftId]);
  }

  /// ترحيل جميع الفواتير المعلقة في وردية محددة
  /// Post all pending invoices in a shift by creating journal entries.
  ///
  /// عند إقفال الوردية، يتم إنشاء القيود المحاسبية لجميع الفواتير
  /// التي لم يتم ترحيلها (is_posted = 0) وتحديث حالتها إلى مرحلة (is_posted = 1).
  Future<int> postShiftInvoices(int shiftId) async {
    final db = await _db;
    int postedCount = 0;
    final now = DateTime.now().toIso8601String();

    // جلب جميع الفواتير المعلقة في الوردية
    final pendingInvoices = await db.query(
      'invoices',
      where: 'shift_id = ? AND is_posted = ?',
      whereArgs: [shiftId, 0],
    );

    for (final invoice in pendingInvoices) {
      final invoiceId = invoice['id'] as String;
      final total = MoneyHelper.readMoney(invoice['total']);
      final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
      final invoiceType = (invoice['type'] as String?) ?? 'sale';
      final isReturn = (invoice['is_return'] as int?) == 1;
      final paymentMechanism = (invoice['payment_mechanism'] as String?) ?? 'cash';
      final cashBoxId = invoice['cash_box_id'] as int?;
      final transportCharges = MoneyHelper.readMoney(invoice['transport_charges']);

      await db.transaction((txn) async {
        final journalId = DateTime.now().millisecondsSinceEpoch;

        // تحديد إزاحة كود الحساب حسب العملة
        final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

        // جلب معرفات الحسابات
        final salesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(4100 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency], limit: 1);

        final salesAccountId = salesAccount.isNotEmpty ? salesAccount.first['id'] as int : null;
        final purchasesAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;
        final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
        final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
        final cashBanksAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;

        int? debitAccountId;
        int? creditAccountId;

        if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
          if (isReturn) {
            debitAccountId = salesAccountId;
            creditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          } else {
            debitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
            creditAccountId = salesAccountId;
          }
        } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
          if (isReturn) {
            debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
            creditAccountId = purchasesAccountId;
          } else {
            debitAccountId = purchasesAccountId;
            creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          }
        }

        // إنشاء القيود المحاسبية
        if (debitAccountId != null && total > 0) {
          await txn.insert('transactions', {
            'account_id': debitAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(total),
            'credit': 0,
            'description': '${(invoiceType == 'sale' || invoiceType == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
        }

        if (creditAccountId != null && total > 0) {
          await txn.insert('transactions', {
            'account_id': creditAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(total),
            'description': '${(invoiceType == 'sale' || invoiceType == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
        }

        // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
        if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
          final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final cogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
          final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

          if (cogsAccountId != null && inventoryAccountId != null) {
            // Fetch invoice items to calculate COGS
            final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
            double totalCogs = 0.0;
            for (final item in invoiceItems) {
              final productId = (item['product_id'] as num?)?.toInt();
              final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
              final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
              if (productId == null) continue;

              final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
              if (productRow.isEmpty) continue;
              final averageCost = MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = averageCost > 0 ? averageCost : MoneyHelper.readMoney(productRow.first['cost_price']);
              // COGS must use base_quantity (not quantity) because average_cost is per base unit
              totalCogs += effectiveCost * baseQuantity;
            }

            if (totalCogs > 0) {
              if (!isReturn) {
                await txn.insert('transactions', {
                  'account_id': cogsAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(totalCogs),
                  'credit': 0,
                  'description': 'تكلفة بضاعة مباعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(totalCogs),
                  'description': 'تخفيض مخزون - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
              } else {
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(totalCogs),
                  'credit': 0,
                  'description': 'إعادة مخزون مرتجع - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': cogsAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(totalCogs),
                  'description': 'عكس تكلفة بضاعة مرتجعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
              }
            }
          }
        }

        // ── Purchase Inventory Transfer Entries ──
        if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final invAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;
          final purchAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;

          if (invAccountId != null && purchAccountId != null) {
            final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
            double totalPurchaseCost = 0.0;
            for (final item in invoiceItems) {
              final productId = (item['product_id'] as num?)?.toInt();
              final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
              if (productId == null) continue;
              final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
              if (productRow.isEmpty) continue;
              final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = avgCost > 0 ? avgCost : MoneyHelper.readMoney(productRow.first['cost_price']);
              totalPurchaseCost += effectiveCost * baseQuantity;
            }

            if (totalPurchaseCost > 0) {
              if (!isReturn) {
                await txn.insert('transactions', {
                  'account_id': invAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(totalPurchaseCost),
                  'credit': 0,
                  'description': 'إضافة مخزون مشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': purchAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(totalPurchaseCost),
                  'description': 'تحويل من حساب المشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccountId, totalPurchaseCost, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchAccountId, 0.0, totalPurchaseCost, now);
              } else {
                await txn.insert('transactions', {
                  'account_id': purchAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(totalPurchaseCost),
                  'credit': 0,
                  'description': 'عكس تحويل مشتريات مرتجعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': invAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(totalPurchaseCost),
                  'description': 'تخفيض مخزون مرتجع مشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchAccountId, totalPurchaseCost, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccountId, 0.0, totalPurchaseCost, now);
              }
            }
          }
        }

        // ── Transport Charges ──
        // NOTE: Transport charges are already included in `total` (total = subtotal - discount + tax + transportCharges).
        // The main journal entries and cash box update above already account for transport correctly.
        // No separate transport journal entries are needed here to avoid double-counting.

        // تحديث رصيد العميل/المورد
        // NOTE: `total` already includes transport charges, so no need to add them again
        if (invoice['customer_id'] != null) {
          final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'pos' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
          // For credit payments, customer owes the full total (already includes transport)
          // For cash payments, customer balance should not change (they paid)
          final customerAmount = paymentMechanism == 'credit' ? total : 0.0;
          if (isDebit) {
            await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoice['customer_id']]);
          } else {
            await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoice['customer_id']]);
          }
        }

        if (invoice['supplier_id'] != null) {
          final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
          // For credit purchases, supplier is owed the full total (already includes transport)
          // For cash purchases, supplier balance should not change (we paid)
          final supplierAmount = paymentMechanism == 'credit' ? total : 0.0;
          if (isCreditToSupplier) {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoice['supplier_id']]);
          } else {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoice['supplier_id']]);
          }
        }

        // تحديث رصيد الصندوق
        if (cashBoxId != null) {
          final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
          if (isCashIn) {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(total), now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(total), now, cashBoxId]);
          }
        }

        // تحديث حالة الفاتورة إلى مرحلة
        await txn.update('invoices', {'is_posted': 1}, where: 'id = ?', whereArgs: [invoiceId]);
      });

      postedCount++;
    }

    return postedCount;
  }

  // ══════════════════════════════════════════════════════════════
  //  v33: Held Orders (POS) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertHeldOrder(Map<String, dynamic> order) async {
    final db = await _db;
    return await db.insert('held_orders', order);
  }

  Future<List<Map<String, dynamic>>> getHeldOrders({int? shiftId}) async {
    final db = await _db;
    if (shiftId != null) {
      return await db.query('held_orders', where: 'shift_id = ?', whereArgs: [shiftId], orderBy: 'created_at DESC');
    }
    return await db.query('held_orders', orderBy: 'created_at DESC');
  }

  Future<int> deleteHeldOrder(int id) async {
    final db = await _db;
    return await db.delete('held_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHeldOrders({int? shiftId}) async {
    final db = await _db;
    if (shiftId != null) {
      await db.delete('held_orders', where: 'shift_id = ?', whereArgs: [shiftId]);
    } else {
      await db.delete('held_orders');
    }
  }
}
