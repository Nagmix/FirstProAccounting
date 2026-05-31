import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../../../core/utils/journal_id_helper.dart';
import '../database_helper.dart';
import '../../models/inventory_cost_layer_model.dart';

class ShiftService {
  final DatabaseHelper _dbHelper;
  ShiftService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Shift (وردية) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> openShift(Map<String, dynamic> shiftMap) async {
    final db = await _db;
    return await db.insert('shifts', MoneyHelper.toCentsMap(shiftMap, MoneyHelper.shiftMoneyFields));
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
    return await db.update('shifts', MoneyHelper.toCentsMap(closeData, MoneyHelper.shiftMoneyFields), where: 'id = ?', whereArgs: [shiftId]);
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
    // Fix #2: Remove double-counting of saleAmount and discountAmount in expected_amount.
    // In SQLite SET clause, total_sales is updated FIRST (total_sales + saleAmount),
    // then expected_amount reads the ALREADY-UPDATED total_sales.
    // So adding saleAmount again would double-count it. Same for discountAmount.
    await db.rawUpdate('''
      UPDATE shifts SET 
        total_sales = total_sales + ?,
        total_returns = total_returns + ?,
        total_discounts = total_discounts + ?,
        transaction_count = transaction_count + 1,
        expected_amount = opening_amount + total_sales - total_returns - total_discounts,
        updated_at = ?
      WHERE id = ?
    ''', [MoneyHelper.toCents(saleAmount), MoneyHelper.toCents(returnAmount), MoneyHelper.toCents(discountAmount), DateTime.now().toIso8601String(), shiftId]);
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
      final taxAmount = MoneyHelper.readMoney(invoice['tax_amount']);

      // C-02: دعم الدفعات الجزئية — استخدام paid_amount و remaining
      final paidAmount = MoneyHelper.readMoney(invoice['paid_amount']);
      final remainingAmount = MoneyHelper.readMoney(invoice['remaining']);
      // المبلغ المدفوع فعلياً: إذا كان cash واستلم جزئياً = paid_amount، إذا كان credit = 0
      final effectivePaid = paymentMechanism == 'credit' ? 0.0 : (paidAmount > 0 ? paidAmount : total);
      final effectiveRemaining = paymentMechanism == 'credit' ? total : (remainingAmount > 0 ? remainingAmount : 0.0);
      final isPartialCash = paymentMechanism == 'cash' && effectivePaid > 0.005 && effectivePaid < total - 0.005;

      await db.transaction((txn) async {
        final journalId = generateUniqueJournalId();

        // تحديد إزاحة كود الحساب حسب العملة
        final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

        // جلب معرفات الحسابات (دفعة واحدة — H-10)
        final accountCodes = [
          (4100 + codeOffset).toString(), // Sales
          (3100 + codeOffset).toString(), // Purchases
          (1200 + codeOffset).toString(), // Customers
          (2100 + codeOffset).toString(), // Suppliers
          (1100 + codeOffset).toString(), // Cash & Banks
          (2300 + codeOffset).toString(), // VAT
        ];
        final placeholders = accountCodes.map((_) => '?').join(',');
        final accountRows = await txn.query(
          'accounts',
          where: 'account_code IN ($placeholders) AND currency = ?',
          whereArgs: [...accountCodes, invoiceCurrency],
        );
        final accountByCode = <String, Map<String, dynamic>>{};
        for (final row in accountRows) {
          final code = row['account_code'] as String?;
          if (code != null) accountByCode[code] = row;
        }
        final salesAccountId = accountByCode[accountCodes[0]]?['id'] as int?;
        final purchasesAccountId = accountByCode[accountCodes[1]]?['id'] as int?;
        final customersAccountId = accountByCode[accountCodes[2]]?['id'] as int?;
        final suppliersAccountId = accountByCode[accountCodes[3]]?['id'] as int?;
        final cashBanksAccountId = accountByCode[accountCodes[4]]?['id'] as int?;
        final vatAccountId = accountByCode[accountCodes[5]]?['id'] as int?;

        // ── C-02: إنشاء القيود المحاسبية مع دعم الدفعات الجزئية ──
        if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
          if (isReturn) {
            // مرتجع مبيعات: مدين المبيعات / دائن النقدية أو العملاء
            final debitAccountId = salesAccountId;
            final creditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
            if (debitAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': debitAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(total),
                'credit': 0,
                'description': 'فاتورة مبيعات - مرتجع - $invoiceId',
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
                'description': 'فاتورة مبيعات - مرتجع - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
            }
          } else if (isPartialCash) {
            // C-02: دفع جزئي — مدين: نقدية (المدفوع) + عملاء (المتبقي) / دائن: مبيعات (الإجمالي)
            if (cashBanksAccountId != null && effectivePaid > 0) {
              await txn.insert('transactions', {
                'account_id': cashBanksAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(effectivePaid),
                'credit': 0,
                'description': 'فاتورة مبيعات (مدفوع) - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, effectivePaid, 0.0, now);
            }
            if (customersAccountId != null && effectiveRemaining > 0) {
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(effectiveRemaining),
                'credit': 0,
                'description': 'فاتورة مبيعات (آجل) - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, effectiveRemaining, 0.0, now);
            }
            if (salesAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(total),
                'description': 'فاتورة مبيعات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
            }
          } else {
            // بيع عادي: كاش كامل أو آجل كامل
            final debitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
            if (debitAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': debitAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(total),
                'credit': 0,
                'description': 'فاتورة مبيعات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
            }
            if (salesAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(total),
                'description': 'فاتورة مبيعات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
            }
          }
        } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
          if (isReturn) {
            // A-04: مرتجع مشتريات — مدين المورد/النقدية، دائن المخزون (وليس المشتريات)
            // في نظام الجرد المستمر، مرتجع المشتريات يقلل المخزون مباشرة
            final debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
            // Resolve inventory account for this currency
            final inventoryCode = (1300 + codeOffset).toString();
            final invRows = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [inventoryCode, invoiceCurrency], limit: 1);
            final returnInvAccountId = invRows.isNotEmpty ? invRows.first['id'] as int : null;

            if (debitAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': debitAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(total),
                'credit': 0,
                'description': 'فاتورة مشتريات - مرتجع - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
            }
            if (returnInvAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': returnInvAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(total),
                'description': 'تخفيض مخزون مرتجع مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, returnInvAccountId, 0.0, total, now);
            }
          } else if (isPartialCash) {
            // C-02: شراء بدفع جزئي — مدين: مشتريات (الإجمالي) / دائن: نقدية (المدفوع) + موردين (المتبقي)
            if (purchasesAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(total),
                'credit': 0,
                'description': 'فاتورة مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
            }
            if (cashBanksAccountId != null && effectivePaid > 0) {
              await txn.insert('transactions', {
                'account_id': cashBanksAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(effectivePaid),
                'description': 'فاتورة مشتريات (مدفوع) - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, effectivePaid, now);
            }
            if (suppliersAccountId != null && effectiveRemaining > 0) {
              await txn.insert('transactions', {
                'account_id': suppliersAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(effectiveRemaining),
                'description': 'فاتورة مشتريات (آجل) - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, effectiveRemaining, now);
            }
          } else {
            // شراء عادي: كاش كامل أو آجل كامل
            if (purchasesAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(total),
                'credit': 0,
                'description': 'فاتورة مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
            }
            final creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
            if (creditAccountId != null && total > 0) {
              await txn.insert('transactions', {
                'account_id': creditAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(total),
                'description': 'فاتورة مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
            }
          }
        }

        // ── C-01: قيود ضريبة القيمة المضافة (VAT) في ترحيل الورديات ──
        if (taxAmount.abs() >= 0.005 && vatAccountId != null) {
          if ((invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') && !isReturn) {
            // مبيعات عليها ضريبة: مدين المبيعات (تخفيض الإيراد) / دائن ضريبة مستحقة
            if (salesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(taxAmount),
                'credit': 0,
                'description': 'ضريبة قيمة مضافة مبيعات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, taxAmount, 0.0, now);
            }
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(taxAmount),
              'description': 'ضريبة قيمة مضافة مستحقة - $invoiceId',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, 0.0, taxAmount, now);
          } else if ((invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') && isReturn) {
            // عكس ضريبة مرتجع مبيعات
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(taxAmount),
              'credit': 0,
              'description': 'عكس ضريبة مرتجع مبيعات - $invoiceId',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, taxAmount, 0.0, now);
            if (salesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(taxAmount),
                'description': 'عكس ضريبة مرتجع مبيعات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, taxAmount, now);
            }
          } else if ((invoiceType == 'purchase' || invoiceType == 'purchase_return') && !isReturn) {
            // مشتريات عليها ضريبة: مدين ضريبة مستحقة / دائن المشتريات (تخفيض التكلفة)
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(taxAmount),
              'credit': 0,
              'description': 'ضريبة قيمة مضافة مشتريات - $invoiceId',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, taxAmount, 0.0, now);
            if (purchasesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(taxAmount),
                'description': 'ضريبة قيمة مضافة مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, taxAmount, now);
            }
          } else if ((invoiceType == 'purchase' || invoiceType == 'purchase_return') && isReturn) {
            // عكس ضريبة مرتجع مشتريات
            if (purchasesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(taxAmount),
                'credit': 0,
                'description': 'عكس ضريبة مرتجع مشتريات - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, taxAmount, 0.0, now);
            }
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(taxAmount),
              'description': 'عكس ضريبة مرتجع مشتريات - $invoiceId',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, 0.0, taxAmount, now);
          }
        }

        // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
        // P-01: Use product-specific account IDs when available
        if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
          final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final defaultCogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
          final defaultInventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

          // Fetch invoice items to calculate COGS, grouped by account pair
          final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
          final cogsGroups = <String, double>{};
          for (final item in invoiceItems) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
            if (productId == null) continue;

            // P-06 + W-07: Prefer stored unit_cost from invoice item (captured at sale time)
            // For FIFO/LIFO products, use the costing engine
            double effectiveCost;
            double itemCogs;
            final storedUnitCost = MoneyHelper.readMoney(item['unit_cost']);
            // Check product's costing method
            final costingMethodRow = await txn.query('products', columns: ['costing_method'], where: 'id = ?', whereArgs: [productId], limit: 1);
            final costingMethodStr = costingMethodRow.isNotEmpty ? (costingMethodRow.first['costing_method'] as String? ?? 'weighted_average') : 'weighted_average';
            final costingMethod = CostingMethodExt.fromValue(costingMethodStr);
            
            if (costingMethod != CostingMethod.weightedAverage && storedUnitCost <= 0) {
              // FIFO/LIFO: use costing engine for accurate COGS
              itemCogs = await _dbHelper.costingEngine.calculateCOGSInTransaction(
                txn,
                productId: productId,
                baseQuantity: baseQuantity,
                invoiceId: invoiceId,
                codeOffset: codeOffset,
              );
            } else {
              if (storedUnitCost > 0) {
                effectiveCost = storedUnitCost;
              } else {
                final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
                if (productRow.isEmpty) continue;
                final averageCost = MoneyHelper.readMoney(productRow.first['average_cost']);
                effectiveCost = averageCost > 0 ? averageCost : MoneyHelper.readMoney(productRow.first['cost_price']);
              }
              itemCogs = effectiveCost * baseQuantity;
            }
            if (itemCogs.abs() < 0.005) continue;

            // P-01: Resolve product-specific accounts
            final productRow = await txn.query('products', columns: ['cogs_account_id', 'inventory_account_id'], where: 'id = ?', whereArgs: [productId], limit: 1);
            final prodCogsId = productRow.isNotEmpty ? productRow.first['cogs_account_id'] as int? : null;
            final prodInvId = productRow.isNotEmpty ? productRow.first['inventory_account_id'] as int? : null;
            final effectiveCogsId = prodCogsId ?? defaultCogsAccountId;
            final effectiveInvId = prodInvId ?? defaultInventoryAccountId;
            final key = '${effectiveCogsId}_${effectiveInvId}';
            cogsGroups[key] = (cogsGroups[key] ?? 0.0) + itemCogs;
          }

          for (final entry in cogsGroups.entries) {
            final totalCogs = entry.value;
            if (totalCogs.abs() < 0.005) continue;
            final parts = entry.key.split('_');
            final cogsAccountId = int.tryParse(parts[0]);
            final inventoryAccountId = int.tryParse(parts[1]);
            if (cogsAccountId == null || inventoryAccountId == null) continue;

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

        // ── Purchase Inventory Transfer Entries ──
        // P-01: Use product-specific account IDs when available
        if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final defaultInvAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;
          final defaultPurchAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;

          final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
          final purchGroups = <String, double>{};
          for (final item in invoiceItems) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
            if (productId == null) continue;

            // Fix #1 (shift): Use unit_price (actual purchase price) for inventory transfer
            // to ensure purchases account (3100) zeros out correctly.
            // unit_price is the actual purchase price per unit, which matches the
            // debit to Purchases account in the original entry.
            //
            // FIX: Use `quantity * unitPrice` (not `baseQuantity * unitPrice`).
            // When purchasing 1 carton at 1500 with conversion_factor=20:
            //   quantity=1 (carton), unitPrice=1500 (per carton)
            //   Total = 1 × 1500 = 1500 (CORRECT)
            //   Old formula: 20 × 1500 = 30000 (WRONG - pieces × carton-price)
            final unitPrice = MoneyHelper.readMoney(item['unit_price']);
            final itemCost = quantity * unitPrice;
            if (itemCost.abs() < 0.005) continue;

            // P-01: Resolve product-specific accounts
            final productRow = await txn.query('products', columns: ['inventory_account_id', 'purchase_account_id'], where: 'id = ?', whereArgs: [productId], limit: 1);
            final prodInvId = productRow.isNotEmpty ? productRow.first['inventory_account_id'] as int? : null;
            final prodPurchId = productRow.isNotEmpty ? productRow.first['purchase_account_id'] as int? : null;
            final effectiveInvId = prodInvId ?? defaultInvAccountId;
            final effectivePurchId = prodPurchId ?? defaultPurchAccountId;
            final key = '${effectiveInvId}_${effectivePurchId}';
            purchGroups[key] = (purchGroups[key] ?? 0.0) + itemCost;
          }

          for (final entry in purchGroups.entries) {
            final totalPurchaseCost = entry.value;
            if (totalPurchaseCost.abs() < 0.005) continue;
            final parts = entry.key.split('_');
            final invAccountId = int.tryParse(parts[0]);
            final purchAccountId = int.tryParse(parts[1]);
            if (invAccountId == null || purchAccountId == null) continue;

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
              // A-04: Purchase return inventory transfer now handled in main entry
              // (Debit Cash/Supplier, Credit Inventory directly). No separate transfer needed.
            }
          }
        }

        // ── Transport Charges ──
        // NOTE: Transport charges are already included in `total` (total = subtotal - discount + tax + transportCharges).
        // The main journal entries and cash box update above already account for transport correctly.
        // No separate transport journal entries are needed here to avoid double-counting.

        // ── C-03 + M-03: تحديث رصيد العميل/المورد مع دعم الدفعات الجزئية ──
        if (invoice['customer_id'] != null) {
          final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'pos' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
          // C-02/M-03: الدفع الجزئي — المتبقي يُضاف لرصيد العميل
          final customerAmount = isPartialCash ? effectiveRemaining : (paymentMechanism == 'credit' ? total : 0.0);
          if (customerAmount.abs() >= 0.005) {
            if (isDebit) {
              await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoice['customer_id']]);
            } else {
              await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoice['customer_id']]);
            }
          }
        }

        if (invoice['supplier_id'] != null) {
          final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
          // C-02/M-03: الدفع الجزئي — المتبقي يُضاف لرصيد المورد
          final supplierAmount = isPartialCash ? effectiveRemaining : (paymentMechanism == 'credit' ? total : 0.0);
          if (supplierAmount.abs() >= 0.005) {
            if (isCreditToSupplier) {
              await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoice['supplier_id']]);
            } else {
              await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoice['supplier_id']]);
            }
          }
        }

        // ── C-03: تحديث رصيد الصندوق بالمبلغ المدفوع فعلياً وليس الإجمالي ──
        if (cashBoxId != null) {
          final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
          // C-03: استخدام effectivePaid بدل total — لمنع تضخم الصندوق في حالات البيع الآجل
          final cashAmount = paymentMechanism == 'credit' ? 0.0 : (isPartialCash ? effectivePaid : total);
          if (cashAmount.abs() >= 0.005) {
            if (isCashIn) {
              await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
            } else {
              await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
            }
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
    return await db.insert('held_orders', MoneyHelper.toCentsMap(order, ['discount']));
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
