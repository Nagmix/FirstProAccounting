import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../../models/invoice_model.dart';
import '../database_helper.dart';

class InvoiceRepository {
  final DatabaseHelper _dbHelper;
  InvoiceRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Invoice CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertInvoiceWithItems(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items,
  ) async {
    // H-12: تحقق من الفترة المالية قبل إدراج فاتورة
    final invoiceDate = invoiceMap['created_at'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(invoiceDate);
    final db = await _db;
    await db.transaction((txn) async {
      final dbInvoiceMap = MoneyHelper.toCentsMap(invoiceMap, MoneyHelper.invoiceMoneyFields);
      await txn.insert('invoices', dbInvoiceMap);
      for (final item in items) {
        final dbItem = MoneyHelper.toCentsMap(item, MoneyHelper.invoiceItemMoneyFields);
        await txn.insert('invoice_items', dbItem);
      }
    });
  }

  /// Save invoice and post journal entries to the chart of accounts.
  /// [transportCharges] - optional transport charges that generate additional journal entries.
  /// [deferPosting] - if true, skip journal entries (for POS deferred posting until shift close).
  Future<void> saveInvoiceWithJournalEntries(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items, {
    required String invoiceType,
    required String paymentMechanism,
    required bool isReturn,
    int? cashBoxId,
    double transportCharges = 0.0,
    bool deferPosting = false,
    double? paidAmount,
  }) async {
    try {
    final db = await _db;
    final total = MoneyHelper.readMoney(invoiceMap['total']);
    final invoiceCurrency = (invoiceMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    // ── التحقق من قفل الفترة المحاسبية ──
    final invoiceDate = invoiceMap['date'] as String? ?? invoiceMap['created_at'] as String? ?? now;
    await _dbHelper.journal.checkFiscalPeriodOpen(invoiceDate);

    // Check if the invoice date falls in a closed fiscal year
    final isClosed = await _dbHelper.isDateInClosedPeriod(DateTime.parse(invoiceDate));
    if (isClosed) {
      throw Exception('لا يمكن إضافة فاتورة في سنة مالية مغلقة');
    }

    await db.transaction((txn) async {
      // Convert money fields to cents before inserting (UI sends raw doubles)
      final dbInvoiceMap = MoneyHelper.toCentsMap(invoiceMap, MoneyHelper.invoiceMoneyFields);
      await txn.insert('invoices', dbInvoiceMap);

      // Insert invoice items (convert money fields to cents)
      // P-06: Also store unit_cost (average cost at time of sale) for accurate deferred COGS
      for (final item in items) {
        // Enrich item with unit_cost from product's average_cost if not already set
        final productId = (item['product_id'] as num?)?.toInt();
        if (productId != null && !item.containsKey('unit_cost')) {
          final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
          if (productRow.isNotEmpty) {
            final avgCost = MoneyHelper.readMoney(productRow.first['average_cost']);
            final effectiveCost = avgCost > 0 ? avgCost : MoneyHelper.readMoney(productRow.first['cost_price']);
            item['unit_cost'] = effectiveCost;
          }
        }
        final dbItem = MoneyHelper.toCentsMap(item, MoneyHelper.invoiceItemMoneyFields);
        await txn.insert('invoice_items', dbItem);
      }

      // ── Stock management ──
      // Sale/POS: decrement stock; Purchase: increment stock; Returns do the opposite
      // Also logs stock movements and updates weighted average cost on purchases

      // ── M-05: حساب إجمالي الكميات الأساسية لتوزيع مصاريف النقل ──
      double totalBaseQuantityForTransport = 0.0;
      if (transportCharges > 0) {
        for (final item in items) {
          final bq = (item['base_quantity'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
          totalBaseQuantityForTransport += bq;
        }
      }

      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        // Use base_quantity for stock deduction (always in base unit)
        // Falls back to quantity for backward compat with old invoice items
        final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
        final unitPrice = MoneyHelper.readMoney(item['unit_price']);
        final invoiceIdStr = invoiceMap['id'] as String? ?? '';
        if (productId == null) continue;

        // Get product's average cost for stock movement logging
        final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        final averageCost = prodRow.isNotEmpty ? MoneyHelper.readMoney(prodRow.first['average_cost']) : 0.0;
        final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Sale: stock leaves warehouse (always in base units)
            if (allowNeg) {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            } else {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            }
            // Log stock movement (use average cost, not selling price)
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'sale',
              'quantity': -baseQuantity,
              'reference_type': invoiceType,
              'reference_id': invoiceIdStr,
              'unit_cost': MoneyHelper.toCents(averageCost),
              'created_at': now,
            });
          } else {
            // Sale return: stock returns to warehouse (always in base units)
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [baseQuantity, now, productId],
            );
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'return',
              'quantity': baseQuantity,
              'reference_type': 'sale_return',
              'reference_id': invoiceIdStr,
              'unit_cost': MoneyHelper.toCents(averageCost),
              'created_at': now,
            });
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Purchase: stock enters warehouse (always in base units)
            // ── A-07: Read current_stock BEFORE updating to ensure accurate weighted average cost ──
            final preUpdateProductRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            final oldStock = preUpdateProductRow.isNotEmpty
                ? (preUpdateProductRow.first['current_stock'] as num?)?.toDouble() ?? 0.0
                : 0.0;
            final currentAvgCost = preUpdateProductRow.isNotEmpty
                ? MoneyHelper.readMoney(preUpdateProductRow.first['average_cost'])
                : 0.0;

            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [baseQuantity, now, productId],
            );
            // ── M-05: تحديث متوسط التكلفة المرجح مع مصاريف الاستلام ──
            // حسب IAS 2: تكلفة المخزون تشمل كل تكاليف الشراء بما فيها النقل والتأمين
            // المبلغ الإجمالي لكل وحدة = سعر الشراء + الحصة النسبية من مصاريف النقل
            final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isNotEmpty) {
              final currentStock = (productRow.first['current_stock'] as num?)?.toDouble() ?? 0.0;
              // A-07: oldStock is now read BEFORE the stock update above, no need to recompute
              // M-05: توزيع مصاريف النقل على الكميات المشتراة (تناسبياً)
              // حسب IAS 2: تكلفة المخزون تشمل كل تكاليف الشراء بما فيها النقل والتأمين
              //
              // FIX: Use `quantity * unitPrice` for total purchase value (not `baseQuantity * unitPrice`).
              // When purchasing 1 carton at 1500 with conversion_factor=20:
              //   - quantity = 1 (carton), unitPrice = 1500 (per carton)
              //   - baseQuantity = 20 (pieces)
              //   - Total value = 1 * 1500 = 1500 (CORRECT)
              //   - Old formula: 20 * 1500 = 30000 (WRONG - pieces × carton-price)
              // Average cost per BASE UNIT = totalValue / baseQuantity
              double itemTransportShare = 0.0;
              if (transportCharges > 0 && totalBaseQuantityForTransport > 0) {
                itemTransportShare = (baseQuantity / totalBaseQuantityForTransport) * transportCharges;
              }
              final totalPurchaseValue = (quantity * unitPrice) + itemTransportShare;
              final newTotalValue = (oldStock * currentAvgCost) + totalPurchaseValue;
              final newTotalStock = currentStock; // already includes new qty (in base units)
              final newAvgCost = newTotalStock > 0 ? newTotalValue / newTotalStock : (baseQuantity > 0 ? totalPurchaseValue / baseQuantity : unitPrice);
              await txn.update(
                'products',
                {
                  'average_cost': MoneyHelper.toCents(newAvgCost),
                  'cost_price': MoneyHelper.toCents(newAvgCost),
                  'updated_at': now,
                },
                where: 'id = ?',
                whereArgs: [productId],
              );
            }
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'purchase',
              'quantity': baseQuantity,
              'reference_type': 'purchase',
              'reference_id': invoiceIdStr,
              'unit_cost': MoneyHelper.toCents(unitPrice),
              'created_at': now,
            });
          } else {
            // Purchase return: stock leaves warehouse (always in base units)
            // Check if product allows negative stock
            final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;
            if (allowNeg) {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            } else {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            }
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'return',
              'quantity': -baseQuantity,
              'reference_type': 'purchase_return',
              'reference_id': invoiceIdStr,
              'unit_cost': MoneyHelper.toCents(unitPrice),
              'created_at': now,
            });
          }
        }
      }

      // ── Deferred posting: skip journal entries for POS invoices ──
      // Journal entries will be created by postShiftInvoices() when the shift is closed.
      // This prevents double-posting (once at sale time and again at shift close).
      if (deferPosting) {
        return; // Stock already updated above; journal entries deferred to shift close.
      }

      // Post journal entries
      final journalId = generateUniqueJournalId();

      // ── Partial payment handling ──
      // When paidAmount is provided and < total with cash mechanism, create split journal entries:
      // Sale: Debit cash (paid) + Debit customer (remaining) = Credit sales (total)
      // Purchase: Debit purchases (total) = Credit cash (paid) + Credit supplier (remaining)
      final effectivePaid = paidAmount ?? (paymentMechanism == 'credit' ? 0.0 : total);
      final isPartialCash = paymentMechanism == 'cash' && effectivePaid < total - 0.005 && effectivePaid > 0.005;
      final remainingAmount = total - effectivePaid;

      // ── Multi-currency: Journal entries should be in base currency (YER) ──
      // When the invoice is in a foreign currency, convert amounts to YER
      // using the invoice's exchange rate, and use YER accounts.
      final exchangeRate = (invoiceMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final bool needsYerConversion = invoiceCurrency != 'YER' && exchangeRate > 0;
      final double journalTotal = needsYerConversion ? total * exchangeRate : total;
      final double journalEffectivePaid = needsYerConversion ? effectivePaid * exchangeRate : effectivePaid;
      final double journalRemainingAmount = needsYerConversion ? remainingAmount * exchangeRate : remainingAmount;
      // Always use YER accounts when converting; otherwise use currency-specific accounts
      final int codeOffset = needsYerConversion ? 0 : (invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0));
      final String journalCurrency = needsYerConversion ? 'YER' : invoiceCurrency;

      // Batch-fetch all required accounts in a single query (H-10: N+1 optimization)
      final accountCodes = [
        (4100 + codeOffset).toString(), // Sales
        (3100 + codeOffset).toString(), // Purchases
        (1200 + codeOffset).toString(), // Customers
        (2100 + codeOffset).toString(), // Suppliers
        (1100 + codeOffset).toString(), // Cash & Banks
      ];
      final placeholders = accountCodes.map((_) => '?').join(',');
      final accountRows = await txn.query(
        'accounts',
        where: 'account_code IN ($placeholders) AND currency = ?',
        whereArgs: [...accountCodes, journalCurrency],
      );
      // Build a lookup map: account_code -> row
      final accountByCode = <String, Map<String, dynamic>>{};
      for (final row in accountRows) {
        final code = row['account_code'] as String?;
        if (code != null) accountByCode[code] = row;
      }
      final salesAccount = accountByCode[accountCodes[0]] != null ? [accountByCode[accountCodes[0]]!] : <Map<String, dynamic>>[];
      final purchasesAccount = accountByCode[accountCodes[1]] != null ? [accountByCode[accountCodes[1]]!] : <Map<String, dynamic>>[];
      final customersAccount = accountByCode[accountCodes[2]] != null ? [accountByCode[accountCodes[2]]!] : <Map<String, dynamic>>[];
      final suppliersAccount = accountByCode[accountCodes[3]] != null ? [accountByCode[accountCodes[3]]!] : <Map<String, dynamic>>[];
      final cashBanksAccount = accountByCode[accountCodes[4]] != null ? [accountByCode[accountCodes[4]]!] : <Map<String, dynamic>>[];

      final salesAccountId = salesAccount.isNotEmpty ? salesAccount.first['id'] as int : null;
      final purchasesAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;
      final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
      final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
      final cashBanksAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
        if (isReturn) {
          // Sale Return: Debit Sales Revenue, Credit Customer/Cash
          final debitAccountId = salesAccountId;
          final creditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;

          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalTotal),
              'credit': 0,
              'description': 'فاتورة مبيعات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, journalTotal, 0.0, now);
          }
          if (creditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': creditAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalTotal),
              'description': 'فاتورة مبيعات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, journalTotal, now);
          }
        } else if (isPartialCash) {
          // Sale with partial cash: Debit cash (paid) + Debit customer (remaining), Credit sales (total)
          if (cashBanksAccountId != null && effectivePaid > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalEffectivePaid),
              'credit': 0,
              'description': 'فاتورة مبيعات (مدفوع) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, journalEffectivePaid, 0.0, now);
          }
          if (customersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalRemainingAmount),
              'credit': 0,
              'description': 'فاتورة مبيعات (آجل) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, journalRemainingAmount, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalTotal),
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, journalTotal, now);
          }
        } else {
          // Normal sale: full cash or full credit
          final debitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalTotal),
              'credit': 0,
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, journalTotal, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalTotal),
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, journalTotal, now);
          }
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isReturn) {
          // A-04: Purchase Return: Debit Cash/Supplier, Credit Inventory (not Purchases)
          // In perpetual inventory, purchase returns directly reduce inventory,
          // not the purchases clearing account.
          final debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          // Resolve inventory account for this currency
          final inventoryCode = (1300 + codeOffset).toString();
          final invRows = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [inventoryCode, journalCurrency], limit: 1);
          final returnInventoryAccountId = invRows.isNotEmpty ? invRows.first['id'] as int : null;

          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalTotal),
              'credit': 0,
              'description': 'فاتورة مشتريات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, debitAccountId, journalTotal, 0.0, now);
          }
          if (returnInventoryAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': returnInventoryAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalTotal),
              'description': 'تخفيض مخزون مرتجع مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, returnInventoryAccountId, 0.0, journalTotal, now);
          }
        } else if (isPartialCash) {
          // Purchase with partial cash: Debit purchases (total), Credit cash (paid) + Credit supplier (remaining)
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalTotal),
              'credit': 0,
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, journalTotal, 0.0, now);
          }
          if (cashBanksAccountId != null && effectivePaid > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalEffectivePaid),
              'description': 'فاتورة مشتريات (مدفوع) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, journalEffectivePaid, now);
          }
          if (suppliersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalRemainingAmount),
              'description': 'فاتورة مشتريات (آجل) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, journalRemainingAmount, now);
          }
        } else {
          // Normal purchase: full cash or full credit
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(journalTotal),
              'credit': 0,
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, journalTotal, 0.0, now);
          }
          final creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (creditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': creditAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(journalTotal),
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, journalTotal, now);
          }
        }
      }

      // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
      // P-01: Use product-specific account IDs when available, fall back to default accounts.
      // Group items by (cogs_account_id, inventory_account_id) to create aggregate entries per group.
      if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
        // Resolve default COGS + Inventory account IDs
        final cogsCode = (3200 + codeOffset).toString();
        final inventoryCode = (1300 + codeOffset).toString();
        final cogsInventoryRows = await txn.query(
          'accounts',
          where: 'account_code IN (?, ?) AND currency = ?',
          whereArgs: [cogsCode, inventoryCode, journalCurrency],
        );
        final defaultCogsAccountId = cogsInventoryRows.where((r) => r['account_code'] == cogsCode).firstOrNull?['id'] as int?;
        final defaultInventoryAccountId = cogsInventoryRows.where((r) => r['account_code'] == inventoryCode).firstOrNull?['id'] as int?;

        // Group items by their effective (cogs_account, inventory_account) pair
        final cogsGroups = <String, double>{};
        for (final item in items) {
          final productId = (item['product_id'] as num?)?.toInt();
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
          if (productId == null) continue;

          final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
          if (productRow.isEmpty) continue;
          final averageCost = MoneyHelper.readMoney(productRow.first['average_cost']);
          final effectiveCost = averageCost > 0 ? averageCost : MoneyHelper.readMoney(productRow.first['cost_price']);
          final itemCogs = effectiveCost * baseQuantity;
          if (itemCogs.abs() < 0.005) continue;

          // P-01: Use product-specific accounts when set, otherwise default
          final prodCogsId = productRow.first['cogs_account_id'] as int?;
          final prodInvId = productRow.first['inventory_account_id'] as int?;
          // B-05: Skip items where required account IDs are unavailable
          final effectiveCogsId = prodCogsId ?? defaultCogsAccountId;
          final effectiveInvId = prodInvId ?? defaultInventoryAccountId;
          if (effectiveCogsId == null || effectiveInvId == null) continue;
          final key = '${effectiveCogsId}_$effectiveInvId';
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
            // Sale: Debit COGS, Credit Inventory
            await txn.insert('transactions', {
              'account_id': cogsAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalCogs),
              'credit': 0,
              'description': 'تكلفة بضاعة مباعة - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': inventoryAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalCogs),
              'description': 'تخفيض مخزون - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
          } else {
            // Sale return: Debit Inventory, Credit COGS (reverse)
            await txn.insert('transactions', {
              'account_id': inventoryAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalCogs),
              'credit': 0,
              'description': 'إعادة مخزون مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': cogsAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalCogs),
              'description': 'عكس تكلفة بضاعة مرتجعة - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
          }
        }
      }

      // ── Purchase Inventory Transfer Entries ──
      // P-01: Use product-specific account IDs when available, fall back to default accounts.
      // Group items by (inventory_account_id, purchase_account_id) to create aggregate entries per group.
      if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
        // Resolve default Inventory + Purchases account IDs
        final inventoryCode = (1300 + codeOffset).toString();
        final purchasesCode = (3100 + codeOffset).toString();
        final invPurchRows = await txn.query(
          'accounts',
          where: 'account_code IN (?, ?) AND currency = ?',
          whereArgs: [inventoryCode, purchasesCode, journalCurrency],
        );
        final defaultInventoryAccountId = invPurchRows.where((r) => r['account_code'] == inventoryCode).firstOrNull?['id'] as int?;
        final defaultPurchasesAccountId = invPurchRows.where((r) => r['account_code'] == purchasesCode).firstOrNull?['id'] as int?;

        // Group items by their effective (inventory_account, purchase_account) pair
        // Fix #1: Use unitPrice (actual purchase price) instead of average_cost
        // to ensure purchases account (3100) zeros out correctly.
        // Entry 1: Debit Purchases = unitPrice × qty, Credit Cash/Supplier = unitPrice × qty
        // Entry 2: Debit Inventory = unitPrice × qty, Credit Purchases = unitPrice × qty
        // If average_cost ≠ unitPrice, the purchases account won't zero out.
        final purchGroups = <String, double>{};
        for (final item in items) {
          final productId = (item['product_id'] as num?)?.toInt();
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          final unitPrice = MoneyHelper.readMoney(item['unit_price']);
          if (productId == null) continue;
          final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
          if (productRow.isEmpty) continue;
          // Fix #1: Use unitPrice (actual purchase price) for inventory transfer entry
          // FIX: Use `quantity * unitPrice` (not `baseQuantity * unitPrice`).
          // When purchasing 1 carton at 1500 with conversion_factor=20:
          //   quantity=1, unitPrice=1500, baseQuantity=20
          //   Total = 1 × 1500 = 1500 (CORRECT), not 20 × 1500 = 30000 (WRONG)
          final itemCost = quantity * unitPrice;
          if (itemCost.abs() < 0.005) continue;

          // P-01: Use product-specific accounts when set, otherwise default
          final prodInvId = productRow.first['inventory_account_id'] as int?;
          final prodPurchId = productRow.first['purchase_account_id'] as int?;
          // B-05: Skip items where required account IDs are unavailable
          final effectiveInvId = prodInvId ?? defaultInventoryAccountId;
          final effectivePurchId = prodPurchId ?? defaultPurchasesAccountId;
          if (effectiveInvId == null || effectivePurchId == null) continue;
          final key = '${effectiveInvId}_$effectivePurchId';
          purchGroups[key] = (purchGroups[key] ?? 0.0) + itemCost;
        }

        for (final entry in purchGroups.entries) {
          final totalPurchaseCost = entry.value;
          if (totalPurchaseCost.abs() < 0.005) continue;
          final parts = entry.key.split('_');
          final inventoryAccountId = int.tryParse(parts[0]);
          final purchasesAccountId = int.tryParse(parts[1]);
          if (inventoryAccountId == null || purchasesAccountId == null) continue;

          if (!isReturn) {
            // Purchase: Debit Inventory (goods come in), Credit Purchases (transfer from purchases account)
            await txn.insert('transactions', {
              'account_id': inventoryAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalPurchaseCost),
              'credit': 0,
              'description': 'إضافة مخزون مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalPurchaseCost),
              'description': 'تحويل من حساب المشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, totalPurchaseCost, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, totalPurchaseCost, now);
          } else {
            // A-04: Purchase return inventory transfer is now handled in the main entry
            // (Debit Cash/Supplier, Credit Inventory directly). No separate transfer needed.
            // The main entry already credits Inventory at total amount, which covers
            // both the cost reversal and the inventory reduction.
          }
        }
      }

      // ── P-02: VAT Journal Entries (ضريبة القيمة المضافة) ──
      // Separate the VAT amount from the total into a VAT control account.
      // For sales: part of the cash/customer debit is already allocated to total;
      // we need to split: the sales credit includes VAT, so we reduce sales and credit VAT.
      // Approach: Debit Sales (reduce by VAT), Credit VAT Payable (for sales)
      // For purchases: Debit VAT Receivable, Credit Purchases (reduce by VAT)
      final taxAmount = MoneyHelper.readMoney(invoiceMap['tax_amount']);
      if (taxAmount.abs() >= 0.005) {
        // P-01: Use invoice-level VAT account or product-level if all products share the same one
        // For simplicity, use the default VAT account (2300 + offset)
        final vatCode = (2300 + codeOffset).toString();
        final vatRows = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [vatCode, journalCurrency],
          limit: 1,
        );
        final vatAccountId = vatRows.isNotEmpty ? vatRows.first['id'] as int : null;

        if (vatAccountId != null) {
          final yerTax = needsYerConversion ? taxAmount * exchangeRate : taxAmount;
          if ((invoiceType == 'sale' || invoiceType == 'pos') && !isReturn) {
            // Sales VAT: Debit Sales (reduce revenue by VAT amount), Credit VAT Payable
            if (salesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(yerTax),
                'credit': 0,
                'description': 'ضريبة قيمة مضافة مبيعات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, yerTax, 0.0, now);
            }
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(yerTax),
              'description': 'ضريبة قيمة مضافة مستحقة - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, 0.0, yerTax, now);
          } else if (invoiceType == 'sale_return' || (invoiceType == 'sale' && isReturn)) {
            // Sales Return VAT: Debit VAT Payable, Credit Sales (restore revenue)
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(yerTax),
              'credit': 0,
              'description': 'عكس ضريبة مرتجع مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, yerTax, 0.0, now);
            if (salesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(yerTax),
                'description': 'عكس ضريبة مرتجع مبيعات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, yerTax, now);
            }
          } else if (invoiceType == 'purchase' && !isReturn) {
            // Purchase VAT: Debit VAT Receivable, Credit Purchases (reduce expense)
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(yerTax),
              'credit': 0,
              'description': 'ضريبة قيمة مضافة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, yerTax, 0.0, now);
            if (purchasesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(yerTax),
                'description': 'ضريبة قيمة مضافة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, yerTax, now);
            }
          } else if (invoiceType == 'purchase_return' || (invoiceType == 'purchase' && isReturn)) {
            // Purchase Return VAT: Debit Purchases, Credit VAT Receivable
            if (purchasesAccountId != null) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(yerTax),
                'credit': 0,
                'description': 'عكس ضريبة مرتجع مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, yerTax, 0.0, now);
            }
            await txn.insert('transactions', {
              'account_id': vatAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(yerTax),
              'description': 'عكس ضريبة مرتجع مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, vatAccountId, 0.0, yerTax, now);
          }
        }
      }

      // ── M-01 + M-02: قيود الخصومات والنقل المستقلة ──
      // حسب المعايير المحاسبية: يجب الإفصاح عن الإيرادات الإجمالية والخصومات بشكل منفصل
      // ومصاريف/إيرادات النقل في حساب مستقل بدل تضمينها في المبيعات

      // M-01: الخصومات — إنشاء قيد مستقل لحساب "خصم مسموح به"
      final discountAmount = MoneyHelper.readMoney(invoiceMap['discount_amount']);
      if (discountAmount.abs() >= 0.005 && (invoiceType == 'sale' || invoiceType == 'pos') && !isReturn) {
        // البحث عن حساب خصم مسموح به (4500+offset) أو إنشاؤه
        final discountCode = (4500 + codeOffset).toString();
        final discountAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [discountCode, journalCurrency],
          limit: 1,
        );
        int? discountAccountId;
        if (discountAccount.isNotEmpty) {
          discountAccountId = discountAccount.first['id'] as int;
        } else {
          discountAccountId = await txn.insert('accounts', {
            'name_ar': 'خصم مسموح به ($journalCurrency)',
            'name_en': 'Discount Allowed ($journalCurrency)',
            'account_code': discountCode,
            'account_type': 'EXPENSE',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'debit',
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        final yerDiscount = needsYerConversion ? discountAmount * exchangeRate : discountAmount;
        // مدين: خصم مسموح به (مصروف) / دائن: المبيعات (تخفيض الإيراد بقيمة الخصم)
        // المبيعات أعلاه سُجلت بالإجمالي (شامل الخصم)، هنا نعكس الخصم
        if (discountAccountId != null) {
          await txn.insert('transactions', {
            'account_id': discountAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(yerDiscount),
            'credit': 0,
            'description': 'خصم مسموح به - ${invoiceMap['id']}',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, discountAccountId, yerDiscount, 0.0, now);
        }
        if (salesAccountId != null) {
          await txn.insert('transactions', {
            'account_id': salesAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(yerDiscount),
            'description': 'تخفيض مبيعات بقيمة الخصم - ${invoiceMap['id']}',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, yerDiscount, now);
        }
      }

      // ── B-02: Purchase Discount (خصم مكتسب) ──
      // For purchase returns with discounts, record the discount earned
      if (discountAmount.abs() >= 0.005 && (invoiceType == 'purchase') && !isReturn) {
        final purchaseDiscountCode = (4600 + codeOffset).toString();
        var purchaseDiscountRows = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [purchaseDiscountCode, journalCurrency],
          limit: 1,
        );
        int? purchaseDiscountAccountId;
        if (purchaseDiscountRows.isNotEmpty) {
          purchaseDiscountAccountId = purchaseDiscountRows.first['id'] as int;
        } else {
          purchaseDiscountAccountId = await txn.insert('accounts', {
            'name_ar': 'خصم مشتريات مكتسب ($journalCurrency)',
            'name_en': 'Purchase Discount Earned ($journalCurrency)',
            'account_code': purchaseDiscountCode,
            'account_type': 'REVENUE',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'credit',
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }
        if (purchaseDiscountAccountId != null && purchasesAccountId != null) {
          final yerDiscount = needsYerConversion ? discountAmount * exchangeRate : discountAmount;
          // Debit Suppliers/Cash (reduce payable), Credit Purchase Discount Earned
          await txn.insert('transactions', {
            'account_id': purchaseDiscountAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(yerDiscount),
            'description': 'خصم مشتريات مكتسب - ${invoiceMap['id']}',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchaseDiscountAccountId, 0.0, yerDiscount, now);
          // Reduce the supplier/cash payable by the discount
          final discountDebitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (discountDebitAccountId != null) {
            await txn.insert('transactions', {
              'account_id': discountDebitAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(yerDiscount),
              'credit': 0,
              'description': 'خصم مشتريات - تخفيض المستحق - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, discountDebitAccountId, yerDiscount, 0.0, now);
          }
        }
      }

      // M-02: مصاريف/إيرادات النقل — إنشاء قيد مستقل لحساب "أجور النقل"
      if (transportCharges.abs() >= 0.005 && (invoiceType == 'sale' || invoiceType == 'pos') && !isReturn) {
        final transportCode = (5200 + codeOffset).toString();
        final transportAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [transportCode, journalCurrency],
          limit: 1,
        );
        int? transportAccountId;
        if (transportAccount.isNotEmpty) {
          transportAccountId = transportAccount.first['id'] as int;
        } else {
          transportAccountId = await txn.insert('accounts', {
            'name_ar': 'أجور النقل ($journalCurrency)',
            'name_en': 'Transport Charges ($journalCurrency)',
            'account_code': transportCode,
            'account_type': 'EXPENSE',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'debit',
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        final yerTransport = needsYerConversion ? transportCharges * exchangeRate : transportCharges;
        // مدين: أجور النقل (مصروف) / دائن: المبيعات (تخفيض الإيراد بقيمة النقل)
        // المبيعات أعلاه سُجلت بالإجمالي (شامل النقل)، هنا نفصل النقل
        if (transportAccountId != null) {
          await txn.insert('transactions', {
            'account_id': transportAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(yerTransport),
            'credit': 0,
            'description': 'مصاريف نقل - ${invoiceMap['id']}',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, transportAccountId, yerTransport, 0.0, now);
        }
        if (salesAccountId != null) {
          await txn.insert('transactions', {
            'account_id': salesAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(yerTransport),
            'description': 'تخفيض مبيعات بقيمة النقل - ${invoiceMap['id']}',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, yerTransport, now);
        }
      }

      // ── Validate journal balance (C-03): debits must equal credits ──
      final journalEntries = await txn.query(
        'transactions',
        where: 'journal_id = ?',
        whereArgs: [journalId],
      );
      _dbHelper.journal.validateJournalBalance(journalEntries);

      // ── A-02: Mark invoice as posted to prevent double-posting in shift close ──
      // When journal entries are created directly (not deferred), mark the invoice as posted
      // so that postShiftInvoices() won't re-process it.
      await txn.update('invoices', {'is_posted': 1}, where: 'id = ?', whereArgs: [invoiceMap['id']]);

      // Update customer/supplier balance
      // For full cash payments: entity balance should NOT change (they already paid in full)
      // For partial cash: only the remaining unpaid amount affects entity balance
      // For credit: entity owes the full amount (total already includes transport)
      if (invoiceMap['customer_id'] != null) {
        final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        double customerAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: entity balance should NOT change (already paid)
          customerAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: only the remaining amount is owed by the customer
          customerAmount = remainingAmount;
        } else {
          // Credit mechanism: entity owes the full amount (total already includes transport)
          customerAmount = total;
        }
        if (isDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoiceMap['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerAmount), now, invoiceMap['customer_id']]);
        }
      }

      // Supplier balance logic:
      // For full cash payments: entity balance should NOT change (they already paid in full)
      // For partial cash: only the remaining unpaid amount affects entity balance
      // For credit: entity is owed the full amount (total already includes transport)
      if (invoiceMap['supplier_id'] != null) {
        final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        double supplierAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: entity balance should NOT change (already paid)
          supplierAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: only the remaining amount is owed to the supplier
          supplierAmount = remainingAmount;
        } else {
          // Credit mechanism: entity is owed the full amount (total already includes transport)
          supplierAmount = total;
        }
        if (isCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoiceMap['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierAmount), now, invoiceMap['supplier_id']]);
        }
      }

      // Update cash box balance (total already includes transport charges)
      if (cashBoxId != null) {
        // For partial payments, only update cash box with the paid amount
        final cashAmount = isPartialCash ? effectivePaid : total;
        final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn);
        // Check cash box balance_type to determine direction
        final cbRow = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        final cbBalanceType = cbRow.isNotEmpty ? (cbRow.first['balance_type'] as String? ?? 'credit') : 'credit';
        if (cbBalanceType == 'credit') {
          // Credit-type (له): money in increases balance, money out decreases
          if (isCashIn) {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
          }
        } else {
          // Debit-type (عليه): money in decreases balance (less owed), money out increases balance (more owed)
          if (isCashIn) {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
          }
        }
      }
    });
    } catch (e) {
      // If the error is already a closed-fiscal-year message, pass it through
      final msg = e.toString();
      if (msg.contains('سنة مالية مغلقة') || msg.contains('فترة مغلقة')) {
        rethrow;
      }
      // Log the error for audit trail
      await _dbHelper.logAuditEvent(
        action: 'error',
        tableName: 'invoices',
        recordId: int.tryParse(invoiceMap['id']?.toString() ?? ''),
        recordType: invoiceType,
        oldValues: 'خطأ أثناء حفظ الفاتورة: $e',
      );
      throw Exception('حدث خطأ أثناء حفظ الفاتورة: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllInvoices({String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final db = await _db;
    String limitClause = '';
    final args = <dynamic>[];
    if (limit != null) {
      limitClause = ' LIMIT ?';
      args.add(limit);
      if (offset > 0) {
        limitClause += ' OFFSET ?';
        args.add(offset);
      }
    }
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
      ORDER BY i.$orderBy$limitClause
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getInvoicesByType(String type) async {
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
      WHERE i.type = ?
      ORDER BY i.created_at DESC
    ''', [type]);
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceId) async {
    final db = await _db;
    return await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  /// Get a single invoice by its ID.
  Future<Map<String, dynamic>?> getInvoiceById(String invoiceId) async {
    final db = await _db;
    final results = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all return invoices linked to a specific original invoice.
  Future<List<Map<String, dynamic>>> getLinkedReturns(String invoiceId) async {
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
      WHERE i.original_invoice_id = ?
      ORDER BY i.created_at DESC
    ''', [invoiceId]);
  }

  /// Soft-delete an invoice by setting status to 'cancelled'.
  /// Does NOT reverse journal entries — use [cancelInvoice] for full reversal.
  Future<int> deleteInvoice(String id) async {
    final db = await _db;
    return await db.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete an invoice and all its related records (CASCADE behavior).
  /// M-14: Ensures data consistency when deleting invoices.
  /// Fix #8: Use reference-based deletion instead of LIKE text search.
  Future<int> deleteInvoiceWithCascade(String invoiceId) async {
    final db = await _db;
    return await db.transaction((txn) async {
      // Delete stock movements linked to this invoice
      await txn.delete('stock_movements', where: 'reference_id = ?', whereArgs: [invoiceId]);
      // Delete invoice items
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      // Delete journal transactions (by finding journal_ids used by this invoice)
      // Fix #8: Instead of LIKE search on description (which could match wrong invoices),
      // find journal_ids from stock_movements (already deleted above, so use transactions
      // with description containing the exact invoice ID as a reference).
      // Better approach: find all distinct journal_ids from transactions that reference
      // this invoice in their description with the exact pattern '- invoiceId'
      // This is more precise than LIKE '%invoiceId%' which could match partial IDs.
      final journalIdRows = await txn.rawQuery(
        "SELECT DISTINCT journal_id FROM transactions WHERE description LIKE ? OR description LIKE ?",
        ['% - $invoiceId', '%$invoiceId%'],
      );
      final journalIds = journalIdRows.map((t) => t['journal_id']).toSet();
      for (final journalId in journalIds) {
        await txn.delete('transactions', where: 'journal_id = ?', whereArgs: [journalId]);
      }
      // Also reverse account balances for deleted transactions
      // (Accounts will be recalculated on next reconciliation)
      // Finally delete the invoice
      return await txn.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    });
  }

  /// Record a payment against an existing invoice.
  /// Updates invoice paid_amount/remaining/status, creates journal entries,
  /// updates customer/supplier balance, and updates cash box balance.
  Future<void> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    required int cashBoxId,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // 1. Get the invoice
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    final currentRemaining = MoneyHelper.readMoney(invoice['remaining']);
    final currentPaid = MoneyHelper.readMoney(invoice['paid_amount']);
    final total = MoneyHelper.readMoney(invoice['total']);
    final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
    final invoiceType = (invoice['type'] as String?) ?? 'sale';
    final customerId = invoice['customer_id'] as int?;
    final supplierId = invoice['supplier_id'] as int?;

    // 2. Validate amount doesn't exceed remaining
    if (amount <= 0) return;
    final paymentAmount = amount > currentRemaining ? currentRemaining : amount;
    final newPaid = currentPaid + paymentAmount;
    final newRemaining = total - newPaid;

    // 3. Determine new status
    String newStatus;
    if (newRemaining <= 0.005) {
      newStatus = 'paid';
    } else if (newPaid > 0) {
      newStatus = 'partial';
    } else {
      newStatus = 'unpaid';
    }

    await db.transaction((txn) async {
      // 4. Update invoice paid_amount, remaining, status
      await txn.update(
        'invoices',
        {
          'paid_amount': newPaid,
          'remaining': newRemaining > 0 ? newRemaining : 0.0,
          'status': newStatus,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // 5. Create journal entries
      final journalId = generateUniqueJournalId();
      final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

      final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency], limit: 1);

      final cashBanksAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
      final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;

      // For sale invoices: Debit cash, Credit customer (customer owes less)
      // For purchase invoices: Debit supplier, Credit cash (we owe supplier less)
      if (invoiceType == 'sale' || invoiceType == 'sale_return') {
        // Sale: customer is paying us → Debit cash, Credit customer account
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(paymentAmount),
            'credit': 0,
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, paymentAmount, 0.0, now);
        }
        if (customersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': customersAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(paymentAmount),
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, paymentAmount, now);
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        // Purchase: we are paying supplier → Debit supplier, Credit cash
        if (suppliersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': suppliersAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(paymentAmount),
            'credit': 0,
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, paymentAmount, 0.0, now);
        }
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(paymentAmount),
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, paymentAmount, now);
        }
      }

      // 6. Update customer balance (customer owes less after payment)
      if (customerId != null) {
        await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(paymentAmount), now, customerId]);
      }

      // 7. Update supplier balance (we owe less after payment)
      if (supplierId != null) {
        await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(paymentAmount), now, supplierId]);
      }

      // 8. Update cash box balance
      if (invoiceType == 'sale' || invoiceType == 'sale_return') {
        // Sale: cash comes in
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(paymentAmount), now, cashBoxId]);
      } else {
        // Purchase: cash goes out
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(paymentAmount), now, cashBoxId]);
      }
    });
  }

  /// Cancel an invoice: soft-delete + reversal journal entries + balance reversals + stock restore.
  Future<void> cancelInvoice(String id) async {
    try {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Fetch invoice
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    // Already cancelled — nothing to do
    if ((invoice['status'] as String?) == 'cancelled') return;

    // Check if the invoice date falls in a closed fiscal year
    final invoiceDate = invoice['date'] as String? ?? invoice['created_at'] as String;
    final isClosed = await _dbHelper.isDateInClosedPeriod(DateTime.parse(invoiceDate));
    if (isClosed) {
      throw Exception('لا يمكن إلغاء فاتورة في سنة مالية مغلقة');
    }

    final total = MoneyHelper.readMoney(invoice['total']);
    final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
    final invoiceType = (invoice['type'] as String?) ?? 'sale';
    final isReturn = (invoice['is_return'] as int?) == 1;
    final paymentMechanism = (invoice['payment_mechanism'] as String?) ?? 'cash';
    final cashBoxId = invoice['cash_box_id'] as int?;
    final transportCharges = MoneyHelper.readMoney(invoice['transport_charges']);

    // Fetch items for stock reversal
    final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);

    await db.transaction((txn) async {
      // 1. Set status to cancelled
      await txn.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [id]);

      // 2. Create reversal journal entries
      final journalId = generateUniqueJournalId();
      final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

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

      // Determine original debit/credit accounts and handle partial payments
      // Check for partial payment (same logic as saveInvoiceWithJournalEntries)
      final paidAmount = MoneyHelper.readMoney(invoice['paid_amount']);
      final remainingAmount = MoneyHelper.readMoney(invoice['remaining']);
      final isPartialCash = paymentMechanism == 'cash' && paidAmount > 0.005 && remainingAmount > 0.005;

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
        if (isPartialCash && !isReturn) {
          // Reverse partial cash sale: Credit Cash (paid), Credit Customer (remaining), Debit Sales (total)
          if (cashBanksAccountId != null && paidAmount > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(paidAmount),
              'description': 'إلغاء فاتورة مبيعات (مدفوع) - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, paidAmount, now);
          }
          if (customersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(remainingAmount),
              'description': 'إلغاء فاتورة مبيعات (آجل) - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, remainingAmount, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(total),
              'credit': 0,
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, total, 0.0, now);
          }
        } else if (isReturn) {
          // Reverse sale return: Debit Customer/Cash (original credit), Credit Sales (original debit)
          final originalCreditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (originalCreditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalCreditAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(total),
              'credit': 0,
              'description': 'إلغاء فاتورة مبيعات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, originalCreditAccountId, total, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(total),
              'description': 'إلغاء فاتورة مبيعات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
          }
        } else {
          // Normal reversal (full cash or full credit): swap debit/credit
          final originalDebitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(total),
              'credit': 0,
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, salesAccountId, total, 0.0, now);
          }
          if (originalDebitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalDebitAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(total),
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, originalDebitAccountId, 0.0, total, now);
          }
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isPartialCash && !isReturn) {
          // Reverse partial cash purchase: Debit Cash (paid), Debit Supplier (remaining), Credit Purchases (total)
          if (cashBanksAccountId != null && paidAmount > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(paidAmount),
              'credit': 0,
              'description': 'إلغاء فاتورة مشتريات (مدفوع) - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cashBanksAccountId, paidAmount, 0.0, now);
          }
          if (suppliersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(remainingAmount),
              'credit': 0,
              'description': 'إلغاء فاتورة مشتريات (آجل) - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, suppliersAccountId, remainingAmount, 0.0, now);
          }
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(total),
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, total, now);
          }
        } else if (isReturn) {
          // Reverse purchase return: Debit Purchases (original credit), Credit Cash/Supplier (original debit)
          final originalDebitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(total),
              'credit': 0,
              'description': 'إلغاء فاتورة مشتريات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
          }
          if (originalDebitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalDebitAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(total),
              'description': 'إلغاء فاتورة مشتريات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, originalDebitAccountId, 0.0, total, now);
          }
        } else {
          // Normal reversal (full cash or full credit): swap debit/credit
          final originalCreditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (originalCreditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalCreditAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(total),
              'credit': 0,
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, originalCreditAccountId, total, 0.0, now);
          }
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(total),
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, total, now);
          }
        }
      }

      // 2b. Reverse COGS journal entries (for sale invoices)
      if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
        final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final cogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
        final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

        if (cogsAccountId != null && inventoryAccountId != null) {
          double totalCogs = 0.0;
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            if (productId == null) continue;

            // Fix #7: Use stored unit_cost from invoice_items (captured at sale time)
            // and base_quantity (for multi-unit products) instead of current cost_price.
            // This ensures COGS reversal matches the original COGS entry exactly.
            final storedUnitCost = MoneyHelper.readMoney(item['unit_cost']);
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
            
            if (storedUnitCost > 0) {
              totalCogs += storedUnitCost * baseQuantity;
            } else {
              // Fallback to current cost_price if unit_cost wasn't stored
              final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
              if (productRow.isEmpty) continue;
              final costPrice = MoneyHelper.readMoney(productRow.first['cost_price']);
              totalCogs += costPrice * baseQuantity;
            }
          }

          if (totalCogs > 0) {
            if (!isReturn) {
              // Original: Debit COGS, Credit Inventory → Reverse: Debit Inventory, Credit COGS
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(totalCogs),
                'credit': 0,
                'description': 'إلغاء تكلفة بضاعة مباعة - $id',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(totalCogs),
                'description': 'إلغاء تخفيض مخزون - $id',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
            } else {
              // Original return: Debit Inventory, Credit COGS → Reverse: Debit COGS, Credit Inventory
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(totalCogs),
                'credit': 0,
                'description': 'إلغاء إعادة مخزون مرتجع - $id',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(totalCogs),
                'description': 'إلغاء عكس تكلفة بضاعة مرتجعة - $id',
                'date': now,
                'created_at': now,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
            }
          }
        }
      }

      // 3. Transport charges reversal
      // NOTE: Transport charges are already included in `total`, so the main reversal entries above
      // already handle transport correctly. No separate transport reversal is needed.

      // 4. Reverse customer/supplier balance
      // Must mirror the save logic: full cash = no balance change, partial cash = only remaining, credit = total
      if (invoice['customer_id'] != null) {
        final wasDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        double customerReversalAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: original save set customerAmount = 0, so reversal is also 0
          customerReversalAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: original save set customerAmount = remainingAmount
          customerReversalAmount = remainingAmount;
        } else {
          // Credit mechanism: original save set customerAmount = total (already includes transport)
          customerReversalAmount = total;
        }
        if (wasDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerReversalAmount), now, invoice['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(customerReversalAmount), now, invoice['customer_id']]);
        }
      }

      if (invoice['supplier_id'] != null) {
        final wasCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        double supplierReversalAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: original save set supplierAmount = 0, so reversal is also 0
          supplierReversalAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: original save set supplierAmount = remainingAmount
          supplierReversalAmount = remainingAmount;
        } else {
          // Credit mechanism: original save set supplierAmount = total (already includes transport)
          supplierReversalAmount = total;
        }
        if (wasCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierReversalAmount), now, invoice['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(supplierReversalAmount), now, invoice['supplier_id']]);
        }
      }

      // 5. Reverse cash box balance
      // Must mirror the save logic: full cash = reverse total, partial cash = reverse paidAmount only
      if (cashBoxId != null) {
        final cashReversalAmount = isPartialCash ? paidAmount : total;
        final wasCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
        if (wasCashIn) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashReversalAmount), now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(cashReversalAmount), now, cashBoxId]);
        }
        // No separate transport reversal needed - transport is already included in total/paidAmount
      }

      // 6. Restore product stock
      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        if (productId == null) continue;
        // Check allow_negative for this product
        final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Was decremented, now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          } else {
            // Was incremented (return), now decrement
            if (allowNeg) {
              await txn.rawUpdate('UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
            } else {
              await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
            }
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Was incremented, now decrement
            if (allowNeg) {
              await txn.rawUpdate('UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
            } else {
              await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
            }
          } else {
            // Was decremented (return), now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          }
        }
      }
    });

    // Log audit event for invoice cancellation
    await _dbHelper.logAuditEvent(
      action: 'cancel',
      tableName: 'invoices',
      recordId: int.tryParse(id),
      recordType: invoice['type'] as String?,
      oldValues: jsonEncode({'status': invoice['status']}),
      newValues: jsonEncode({'status': 'cancelled'}),
      userName: null,
    );
    } catch (e) {
      // If the error is already a closed-fiscal-year message, pass it through
      final msg = e.toString();
      if (msg.contains('سنة مالية مغلقة') || msg.contains('فترة مغلقة')) {
        rethrow;
      }
      // Log the error for audit trail
      await _dbHelper.logAuditEvent(
        action: 'error',
        tableName: 'invoices',
        recordId: int.tryParse(id),
        oldValues: 'خطأ أثناء إلغاء الفاتورة: $e',
      );
      throw Exception('حدث خطأ أثناء إلغاء الفاتورة: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Invoice query & reporting methods
  // ══════════════════════════════════════════════════════════════

  Future<double> getTotalSalesForDate(DateTime date) async {
    final db = await _db;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) = ?", [dateStr]);
    return MoneyHelper.readMoney(result.first['total']);
  }

  Future<double> getTotalPurchasesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type IN ('purchase', 'purchase_return') AND is_return = 0 AND date(created_at) >= ?", [monthStart]);
    return MoneyHelper.readMoney(result.first['total']);
  }

  Future<double> getTotalSalesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?", [monthStart]);
    return MoneyHelper.readMoney(result.first['total']);
  }

  /// Calculate Cost of Goods Sold (COGS) for the current month.
  /// COGS = SUM(base_quantity * unit_cost) for sale/pos invoice items this month.
  /// FIX: CAST to INTEGER so readMoney divides by 100 correctly.
  Future<double> getCOGSThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    try {
      final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM("
        "  CASE WHEN ii.base_quantity > 0 THEN ii.base_quantity ELSE ii.quantity END "
        "  * CASE WHEN ii.unit_cost > 0 THEN ii.unit_cost ELSE p.cost_price END"
        "), 0) AS INTEGER) AS total_cogs "
        "FROM invoice_items ii "
        "INNER JOIN invoices i ON ii.invoice_id = i.id "
        "LEFT JOIN products p ON ii.product_id = p.id "
        "WHERE i.type IN ('sale','pos') AND i.is_return = 0 "
        "AND date(i.created_at) >= ?",
        [monthStart],
      );
      return MoneyHelper.readMoney(result.first['total_cogs']);
    } catch (e) {
      return 0.0;
    }
  }

  Future<int> getInvoiceCountForDate(DateTime date) async {
    final db = await _db;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COUNT(*) AS cnt FROM invoices WHERE date(created_at) = ?", [dateStr]);
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> getCashBalance() async {
    return _dbHelper.getTotalCashBalance();
  }

  Future<List<Map<String, dynamic>>> getRecentInvoices({int limit = 10}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT i.id, i.type, i.total, i.paid_amount, i.remaining, i.is_return,
             i.status, i.created_at, i.payment_mechanism,
             COALESCE(c.name, s.name, 'بدون عميل') AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getDailySalesTotals({int days = 7}) async {
    final db = await _db;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr]);
  }

  Future<int> getNextInvoiceSequence(String datePrefix, String invoiceType) async {
    final db = await _db;
    // البحث عن أكبر رقم تسلسلي موجود لهذا اليوم وهذا النوع
    final result = await db.rawQuery(
      "SELECT id FROM invoices WHERE id LIKE ? AND type = ? ORDER BY id DESC LIMIT 1",
      ['$datePrefix%', invoiceType],
    );
    if (result.isEmpty) return 1;

    final lastId = result.first['id'] as String;
    // استخراج الرقم التسلسلي من المعرف: POS-YYYYMMDD-NNNN → NNNN
    final parts = lastId.split('-');
    if (parts.length >= 3) {
      final lastSeq = int.tryParse(parts.last) ?? 0;
      return lastSeq + 1;
    }
    return 1;
  }

  Future<int> getTodayPosInvoiceCount(String datePrefix) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE id LIKE ?",
      ['POS-$datePrefix%'],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Check return quantity limits against the original invoice.
  /// Returns a map of product_id -> error message for items that exceed original quantities.
  Future<Map<String, String>> checkReturnLimits(String originalInvoiceId, List<Map<String, dynamic>> returnItems) async {
    final db = await _db;
    final errors = <String, String>{};
    
    // Get original invoice items
    final originalItems = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [originalInvoiceId],
    );
    
    // Get already returned quantities
    final returnInvoices = await db.query(
      'invoices',
      where: 'original_invoice_id = ? AND is_return = 1 AND status != ?',
      whereArgs: [originalInvoiceId, 'cancelled'],
    );
    
    final returnedQuantities = <int, double>{};
    for (final returnInvoice in returnInvoices) {
      final returnItems2 = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [returnInvoice['id']],
      );
      for (final item in returnItems2) {
        final productId = (item['product_id'] as num?)?.toInt() ?? 0;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        returnedQuantities[productId] = (returnedQuantities[productId] ?? 0.0) + qty;
      }
    }
    
    // Check each return item against original - returned
    for (final item in returnItems) {
      final productId = (item['product_id'] as num?)?.toInt() ?? 0;
      final returnQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      
      // Find original quantity for this product
      double originalQty = 0.0;
      for (final origItem in originalItems) {
        final origProductId = (origItem['product_id'] as num?)?.toInt() ?? 0;
        if (origProductId == productId) {
          originalQty = (origItem['quantity'] as num?)?.toDouble() ?? 0.0;
          break;
        }
      }
      
      final alreadyReturned = returnedQuantities[productId] ?? 0.0;
      if (returnQty > originalQty - alreadyReturned) {
        errors[productId.toString()] = 'الكمية المرتجعة ($returnQty) تتجاوز الكمية المتبقية (${originalQty - alreadyReturned})';
      }
    }
    
    return errors;
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Invoice>> getAllInvoiceObjects({String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final maps = await getAllInvoices(orderBy: orderBy, limit: limit, offset: offset);
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getInvoiceObjectsByType(String type) async {
    final maps = await getInvoicesByType(type);
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Invoice?> getInvoiceObjectById(String invoiceId) async {
    final map = await getInvoiceById(invoiceId);
    return map != null ? Invoice.fromMap(map) : null;
  }
}
