import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/entity_balance_helper.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/models/invoice_model.dart';
import 'package:firstpro/data/models/inventory_cost_layer_model.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

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
    final invoiceDate =
        invoiceMap['created_at'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(invoiceDate);
    final db = await _db;
    await db.transaction((txn) async {
      final dbInvoiceMap =
          MoneyHelper.toCentsMap(invoiceMap, MoneyHelper.invoiceMoneyFields);
      await txn.insert('invoices', dbInvoiceMap);
      for (final item in items) {
        final dbItem =
            MoneyHelper.toCentsMap(item, MoneyHelper.invoiceItemMoneyFields);
        await txn.insert('invoice_items', dbItem);
      }
    });
  }

  /// Save invoice and post journal entries to the chart of accounts.
  /// [transportChargesParam] - optional transport charges that generate additional journal entries.
  /// [deferPosting] - if true, skip journal entries (for POS deferred posting until shift close).
  Future<void> saveInvoiceWithJournalEntries(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items, {
    required String invoiceType,
    required String paymentMechanism,
    required bool isReturn,
    int? cashBoxId,
    double transportChargesParam = 0.0,
    bool deferPosting = false,
    double? paidAmount,
  }) async {
    try {
      final db = await _db;
      final total = MoneyHelper.readMoney(invoiceMap['total']);
      final invoiceCurrency = (invoiceMap['currency'] as String?) ?? 'YER';
      final double exchangeRate =
          (invoiceMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final double effectiveExchangeRate = exchangeRate > 0 ? exchangeRate : 1.0;
      final now = DateTime.now().toIso8601String();

      // ── التحقق من قفل الفترة المحاسبية ──
      final invoiceDate = invoiceMap['date'] as String? ??
          invoiceMap['created_at'] as String? ??
          now;
      await _dbHelper.journal.checkFiscalPeriodOpen(invoiceDate);

      // Check if the invoice date falls in a closed fiscal year
      final isClosed = await _dbHelper.accounts
          .isDateInClosedPeriod(DateTime.parse(invoiceDate));
      if (isClosed) {
        throw Exception('لا يمكن إضافة فاتورة في سنة مالية مغلقة');
      }

      await db.transaction((txn) async {
        // Convert money fields to cents before inserting (UI sends raw doubles)
        final dbInvoiceMap =
            MoneyHelper.toCentsMap(invoiceMap, MoneyHelper.invoiceMoneyFields);
        await txn.insert('invoices', dbInvoiceMap);

        // Insert invoice items (convert money fields to cents)
        // P-06: Also store unit_cost (average cost at time of sale) for accurate deferred COGS

        // ── Pre-compute discount & transport for stock distribution and journal entries ──
        final discountAmount =
            MoneyHelper.readMoney(invoiceMap['discount_amount']);
        final transportCharges =
            MoneyHelper.readMoney(invoiceMap['transport_charges']) > 0
                ? MoneyHelper.readMoney(invoiceMap['transport_charges'])
                : transportChargesParam;

        for (final item in items) {
          // Enrich item with unit_cost from product's average_cost if not already set
          final productId = (item['product_id'] as num?)?.toInt();
          if (productId != null && !item.containsKey('unit_cost')) {
            final productRow = await txn.query('products',
                where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isNotEmpty) {
              final avgCost =
                  MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = avgCost > 0
                  ? avgCost
                  : MoneyHelper.readMoney(productRow.first['cost_price']);
              item['unit_cost'] = effectiveCost;
            }
          }
          final dbItem =
              MoneyHelper.toCentsMap(item, MoneyHelper.invoiceItemMoneyFields);
          await txn.insert('invoice_items', dbItem);
        }

        // ── Stock management ──
        // Sale/POS: decrement stock; Purchase: increment stock; Returns do the opposite
        // Also logs stock movements and updates weighted average cost on purchases

        // ── M-05: حساب إجمالي الكميات الأساسية لتوزيع مصاريف النقل ──
        double totalBaseQuantityForTransport = 0.0;
        if (transportCharges > 0) {
          for (final item in items) {
            final bq = (item['base_quantity'] as num?)?.toDouble() ??
                (item['quantity'] as num?)?.toDouble() ??
                1.0;
            totalBaseQuantityForTransport += bq;
          }
        }

        for (final item in items) {
          final productId = (item['product_id'] as num?)?.toInt();
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          double itemTransportShareBase = 0.0;
          // Use base_quantity for stock deduction (always in base unit)
          // Falls back to quantity for backward compat with old invoice items
          final baseQuantity =
              (item['base_quantity'] as num?)?.toDouble() ?? quantity;
          final unitPrice = MoneyHelper.readMoney(item['unit_price']);
          final invoiceIdStr = invoiceMap['id'] as String? ?? '';
          if (productId == null) continue;

          // Get product's average cost for stock movement logging
          final prodRow = await txn.query('products',
              where: 'id = ?', whereArgs: [productId], limit: 1);
          final averageCost = prodRow.isNotEmpty
              ? MoneyHelper.readMoney(prodRow.first['average_cost'])
              : 0.0;
          final allowNeg = prodRow.isNotEmpty
              ? (prodRow.first['allow_negative'] as int?) == 1
              : false;

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
              final preUpdateProductRow = await txn.query('products',
                  where: 'id = ?', whereArgs: [productId], limit: 1);
              final oldStock = preUpdateProductRow.isNotEmpty
                  ? (preUpdateProductRow.first['current_stock'] as num?)
                          ?.toDouble() ??
                      0.0
                  : 0.0;
              final currentAvgCost = preUpdateProductRow.isNotEmpty
                  ? MoneyHelper.readMoney(
                      preUpdateProductRow.first['average_cost'])
                  : 0.0;

              await txn.rawUpdate(
                'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
              // ── M-05: تحديث متوسط التكلفة المرجح مع مصاريف الاستلام ──
              // حسب IAS 2: تكلفة المخزون تشمل كل تكاليف الشراء بما فيها النقل والتأمين
              // المبلغ الإجمالي لكل وحدة = سعر الشراء + الحصة النسبية من مصاريف النقل
              final productRow = await txn.query('products',
                  where: 'id = ?', whereArgs: [productId], limit: 1);

              if (transportCharges > 0 && totalBaseQuantityForTransport > 0) {
                // transportCharges here is in invoice currency
                final double totalTransportBase =
                    transportCharges * effectiveExchangeRate;
                itemTransportShareBase =
                    (baseQuantity / totalBaseQuantityForTransport) *
                        totalTransportBase;
              }

              if (productRow.isNotEmpty) {
                final currentStock =
                    (productRow.first['current_stock'] as num?)?.toDouble() ??
                        0.0;
                // A-07: oldStock is now read BEFORE the stock update above, no need to recompute
                // M-05: توزيع مصاريف النقل على الكميات المشتراة (تناسبياً)
                // حسب IAS 2: تكلفة المخزون تشمل كل تكاليف الشراء بما فيها النقل والتأمين
                //
                // A-09: المخزون وتكلفة الوحدة يجب أن تكون دائماً بالعملة الأساس (YER)
                // يتم تحويل سعر الوحدة ومصاريف النقل إلى العملة الأساس قبل تحديث المتوسط
                final double baseUnitPrice = unitPrice * effectiveExchangeRate;

                final totalPurchaseValueBase =
                    (quantity * baseUnitPrice) + itemTransportShareBase;
                final newTotalValue =
                    (oldStock * currentAvgCost) + totalPurchaseValueBase;
                final newTotalStock =
                    currentStock; // already includes new qty (in base units)
                final newAvgCost = newTotalStock > 0
                    ? newTotalValue / newTotalStock
                    : (baseQuantity > 0
                        ? totalPurchaseValueBase / baseQuantity
                        : baseUnitPrice);
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
                // A-09: unit_cost is stored in base currency
                'unit_cost': MoneyHelper.toCents(unitPrice *
                    (effectiveExchangeRate)),
                'created_at': now,
              });

              // ── FIFO/LIFO: Create cost layer for non-weighted-average products ──
              // Cost layers enable accurate COGS calculation per FIFO/LIFO method.
              // For weighted average, the average_cost field is used instead.
              final costingMethodStr = prodRow.isNotEmpty
                  ? (prodRow.first['costing_method'] as String? ??
                      'weighted_average')
                  : 'weighted_average';
              final costingMethod =
                  CostingMethodExt.fromValue(costingMethodStr);
              if (costingMethod != CostingMethod.weightedAverage) {
                // unit cost per base unit = total purchase value (Base) / base quantity
                final double effectiveRate =
                    effectiveExchangeRate;
                final unitCostPerBase = baseQuantity > 0
                    ? ((quantity * unitPrice * effectiveRate) +
                            (itemTransportShareBase)) /
                        baseQuantity
                    : (unitPrice * effectiveRate);
                final layer = InventoryCostLayer(
                  productId: productId,
                  warehouseId: invoiceMap['warehouse_id'] as int?,
                  quantityOriginal: baseQuantity,
                  quantityRemaining: baseQuantity,
                  unitCost: unitCostPerBase,
                  acquisitionDate: DateTime.now(),
                  referenceType: 'purchase',
                  referenceId: invoiceIdStr,
                );
                await txn.insert('inventory_cost_layers', layer.toMap());
              }
            } else {
              // Purchase return: stock leaves warehouse at COST (not selling price)
              // C-03: Use average_cost for the return, not unitPrice
              // C-04: Update average cost after return
              final prodRow = await txn.query('products',
                  where: 'id = ?', whereArgs: [productId], limit: 1);
              final allowNeg = prodRow.isNotEmpty
                  ? (prodRow.first['allow_negative'] as int?) == 1
                  : false;
              final returnCostPrice = prodRow.isNotEmpty
                  ? MoneyHelper.readMoney(prodRow.first['average_cost'])
                  : unitPrice;
              final effectiveReturnCost = returnCostPrice > 0
                  ? returnCostPrice
                  : MoneyHelper.readMoney(prodRow.first['cost_price']);

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

              // C-04: After returning goods, recalculate average cost
              // When goods leave at average cost, remaining stock's avg cost doesn't change
              // (weighted average method). For FIFO/LIFO, reverse cost layers below.

              await txn.insert('stock_movements', {
                'product_id': productId,
                'movement_type': 'return',
                'quantity': -baseQuantity,
                'reference_type': 'purchase_return',
                'reference_id': invoiceIdStr,
                'unit_cost': MoneyHelper.toCents(
                    effectiveReturnCost), // C-03: Use cost, not selling price
                'created_at': now,
              });

              // C-04: For FIFO/LIFO products, reverse cost layers on purchase return
              final costingMethodStr = prodRow.isNotEmpty
                  ? (prodRow.first['costing_method'] as String? ??
                      'weighted_average')
                  : 'weighted_average';
              final costingMethod =
                  CostingMethodExt.fromValue(costingMethodStr);
              if (costingMethod != CostingMethod.weightedAverage) {
                // Reverse the most recent cost layers for the returned quantity
                await _dbHelper.costingEngine
                    .reverseCOGSAllocationsInTransaction(
                  txn,
                  invoiceId: invoiceIdStr,
                );
              }
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
        final effectivePaid =
            paidAmount ?? (paymentMechanism == 'credit' ? 0.0 : total);
        final isPartialCash = paymentMechanism == 'cash' &&
            effectivePaid < total - 0.005 &&
            effectivePaid > 0.005;
        final remainingAmount = total - effectivePaid;

        // A-07 & A-9 Fix: الفواتير بالعملة الأجنبية تُرحل بعملتها على حساباتها الخاصة
        // مع الاحتفاظ بالقيمة المحولة في amount_base للتقارير الموحدة
        final double journalTotal = total;
        final double journalEffectivePaid = effectivePaid;
        final double journalRemainingAmount = remainingAmount;

        // Determine codeOffset based on currency (YER=0, SAR=1, USD=2)
        // This ensures the entry goes to the correct currency-specific account.
        final int codeOffset = (invoiceCurrency == 'SAR'
            ? 1
            : (invoiceCurrency == 'USD' ? 2 : 0));
        final String journalCurrency = invoiceCurrency;

        // ── Discount, Transport & Tax amounts for journal ──
        final double journalDiscount = discountAmount;
        final double journalTransport = transportCharges;
        final double taxAmount =
            MoneyHelper.readMoney(invoiceMap['tax_amount']);
        final double journalTax = taxAmount;
        // IAS 2: Transport into base currency
        final double yerTransport = journalTransport * effectiveExchangeRate;

        // ── Net Recording Approach (C-01/C-02/M-02 fix) ──
        final double netRevenueAmount =
            journalTotal + journalDiscount - journalTax;
        final double netPurchaseCost =
            journalTotal + journalDiscount - journalTax;

        // Batch-fetch all required accounts in a single query (H-10: N+1 optimization)
        final accountCodes = [
          (4100 + codeOffset).toString(), // Sales
          (3100 + codeOffset).toString(), // Purchases
          (1200 + codeOffset).toString(), // Customers
          (2100 + codeOffset).toString(), // Suppliers
          (1100 + codeOffset).toString(), // Cash & Banks
          (2300 + codeOffset)
              .toString(), // VAT Payable (Output VAT - Liability)
          (1400 + codeOffset).toString(), // VAT Receivable (Input VAT - Asset)
          (5400 + codeOffset).toString(), // Discount Allowed
          (4600 + codeOffset).toString(), // Discount Earned
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
        final salesAccount = accountByCode[accountCodes[0]] != null
            ? [accountByCode[accountCodes[0]]!]
            : <Map<String, dynamic>>[];
        final purchasesAccount = accountByCode[accountCodes[1]] != null
            ? [accountByCode[accountCodes[1]]!]
            : <Map<String, dynamic>>[];
        final customersAccount = accountByCode[accountCodes[2]] != null
            ? [accountByCode[accountCodes[2]]!]
            : <Map<String, dynamic>>[];
        final suppliersAccount = accountByCode[accountCodes[3]] != null
            ? [accountByCode[accountCodes[3]]!]
            : <Map<String, dynamic>>[];
        final cashBanksAccount = accountByCode[accountCodes[4]] != null
            ? [accountByCode[accountCodes[4]]!]
            : <Map<String, dynamic>>[];

        final salesAccountId =
            salesAccount.isNotEmpty ? salesAccount.first['id'] as int : null;
        final purchasesAccountId = purchasesAccount.isNotEmpty
            ? purchasesAccount.first['id'] as int
            : null;
        final customersAccountId = customersAccount.isNotEmpty
            ? customersAccount.first['id'] as int
            : null;
        final suppliersAccountId = suppliersAccount.isNotEmpty
            ? suppliersAccount.first['id'] as int
            : null;
        final cashBanksAccountId = cashBanksAccount.isNotEmpty
            ? cashBanksAccount.first['id'] as int
            : null;

        // ── C-05: Resolve/create VAT and Discount accounts ──
        // VAT Payable (Output VAT) - account 2300+offset (Liability)
        final vatPayableAccount = accountByCode[(2300 + codeOffset).toString()];
        int? vatPayableAccountId =
            vatPayableAccount != null ? vatPayableAccount['id'] as int : null;
        if (vatPayableAccountId == null) {
          final parentRows = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(2000 + codeOffset).toString(), journalCurrency],
              limit: 1);
          final vatParentId =
              parentRows.isNotEmpty ? parentRows.first['id'] as int : null;
          vatPayableAccountId = await txn.insert('accounts', {
            'name_ar': 'ضريبة القيمة المضافة المستحقة ($journalCurrency)',
            'name_en': 'VAT Payable ($journalCurrency)',
            'account_code': (2300 + codeOffset).toString(),
            'account_type': 'LIABILITY',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'credit',
            'parent_id': vatParentId,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        // VAT Receivable (Input VAT) - account 1400+offset (Asset) — C-05
        final vatReceivableAccount =
            accountByCode[(1400 + codeOffset).toString()];
        int? vatReceivableAccountId = vatReceivableAccount != null
            ? vatReceivableAccount['id'] as int
            : null;
        if (vatReceivableAccountId == null) {
          final assetParentRows = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(1000 + codeOffset).toString(), journalCurrency],
              limit: 1);
          final vatAssetParentId = assetParentRows.isNotEmpty
              ? assetParentRows.first['id'] as int
              : null;
          vatReceivableAccountId = await txn.insert('accounts', {
            'name_ar': 'ضريبة القيمة المضافة القابلة للخصم ($journalCurrency)',
            'name_en': 'VAT Receivable ($journalCurrency)',
            'account_code': (1400 + codeOffset).toString(),
            'account_type': 'ASSET',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'debit',
            'parent_id': vatAssetParentId,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        // Discount Allowed - account 5400+offset (Expense)
        final discountAllowedAccount =
            accountByCode[(5400 + codeOffset).toString()];
        int? discountAllowedAccountId = discountAllowedAccount != null
            ? discountAllowedAccount['id'] as int
            : null;
        if (discountAllowedAccountId == null) {
          final expParentRows = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(5000 + codeOffset).toString(), journalCurrency],
              limit: 1);
          final expParentId = expParentRows.isNotEmpty
              ? expParentRows.first['id'] as int
              : null;
          discountAllowedAccountId = await txn.insert('accounts', {
            'name_ar': 'خصم مسموح به ($journalCurrency)',
            'name_en': 'Discount Allowed ($journalCurrency)',
            'account_code': (5400 + codeOffset).toString(),
            'account_type': 'EXPENSE',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'debit',
            'parent_id': expParentId,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        // Discount Earned - account 4600+offset (Revenue / Contra-expense)
        final discountEarnedAccount =
            accountByCode[(4600 + codeOffset).toString()];
        int? discountEarnedAccountId = discountEarnedAccount != null
            ? discountEarnedAccount['id'] as int
            : null;
        if (discountEarnedAccountId == null) {
          final revParentRows = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(4000 + codeOffset).toString(), journalCurrency],
              limit: 1);
          final revParentId = revParentRows.isNotEmpty
              ? revParentRows.first['id'] as int
              : null;
          discountEarnedAccountId = await txn.insert('accounts', {
            'name_ar': 'خصم مشتريات مكتسب ($journalCurrency)',
            'name_en': 'Purchase Discount Earned ($journalCurrency)',
            'account_code': (4600 + codeOffset).toString(),
            'account_type': 'REVENUE',
            'balance': 0,
            'currency': journalCurrency,
            'balance_type': 'credit',
            'parent_id': revParentId,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        if (invoiceType == 'sale' ||
            invoiceType == 'sale_return' ||
            invoiceType == 'pos') {
          if (isReturn) {
            // ── Sale return: Exact reverse of the original sale entry ──
            // Debit: Sales = netRevenueAmount (reverse revenue)
            // Debit: VAT Payable = yerTax (reverse VAT liability, if any)
            // Credit: Cash/Customer = journalTotal (amount refunded)
            // Credit: Discount Allowed = yerDiscount (reverse discount expense, if any)
            // Balanced: netRevenueAmount + journalTax = journalTotal + journalDiscount
            if (salesAccountId != null && netRevenueAmount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(netRevenueAmount),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(netRevenueAmount * effectiveExchangeRate),
                'description': 'عكس إيراد مبيعات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, netRevenueAmount, 0.0, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatPayableAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalTax),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description': 'عكس ضريبة مبيعات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatPayableAccountId, journalTax, 0.0, now);
            }
            final creditAccountId = paymentMechanism == 'credit'
                ? customersAccountId
                : cashBanksAccountId;
            if (creditAccountId != null && journalTotal.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': creditAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalTotal),
                'amount_base':
                    MoneyHelper.toCents(journalTotal * effectiveExchangeRate),
                'description': 'فاتورة مبيعات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, creditAccountId, 0.0, journalTotal, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountAllowedAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalDiscount),
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description': 'عكس خصم مسموح به - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountAllowedAccountId, 0.0, journalDiscount, now);
            }
          } else if (isPartialCash) {
            // ── Partial cash sale: Net recording ──
            // Debit: Cash = journalEffectivePaid
            // Debit: Customer = journalRemainingAmount
            // Debit: Discount Allowed = journalDiscount (if any, separate disclosure)
            // Credit: Sales = netRevenueAmount (net revenue including transport, before tax)
            // Credit: VAT Payable = journalTax (if any)
            // Balanced: journalEffectivePaid + journalRemainingAmount + journalDiscount = netRevenueAmount + journalTax
            if (cashBanksAccountId != null &&
                journalEffectivePaid.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': cashBanksAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalEffectivePaid),
                'credit': 0,
                'amount_base': MoneyHelper.toCents(
                    journalEffectivePaid * effectiveExchangeRate),
                'description': 'فاتورة مبيعات (مدفوع) - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cashBanksAccountId, journalEffectivePaid, 0.0, now);
            }
            if (customersAccountId != null &&
                journalRemainingAmount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': customersAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalRemainingAmount),
                'credit': 0,
                'amount_base': MoneyHelper.toCents(
                    journalRemainingAmount * effectiveExchangeRate),
                'description': 'فاتورة مبيعات (آجل) - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, customersAccountId, journalRemainingAmount, 0.0, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountAllowedAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalDiscount),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description': 'خصم مسموح به - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountAllowedAccountId, journalDiscount, 0.0, now);
            }
            if (salesAccountId != null && netRevenueAmount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(netRevenueAmount),
                'amount_base':
                    MoneyHelper.toCents(netRevenueAmount * effectiveExchangeRate),
                'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, 0.0, netRevenueAmount, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatPayableAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalTax),
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description': 'ضريبة قيمة مضافة مستحقة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatPayableAccountId, 0.0, journalTax, now);
            }
          } else {
            // ── Normal sale: Net recording (C-01/C-02/M-02) ──
            // Debit: Cash/Customer = journalTotal (actual amount paid/owed)
            // Debit: Discount Allowed = yerDiscount (if any, separate disclosure)
            // Credit: Sales = netRevenueAmount (net revenue including transport, before tax)
            // Credit: VAT Payable = yerTax (if any)
            // Balanced: journalTotal + yerDiscount = netRevenueAmount + yerTax
            final debitAccountId = paymentMechanism == 'credit'
                ? customersAccountId
                : cashBanksAccountId;
            if (debitAccountId != null && journalTotal.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': debitAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalTotal),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalTotal * effectiveExchangeRate),
                'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, debitAccountId, journalTotal, 0.0, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountAllowedAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalDiscount),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description': 'خصم مسموح به - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountAllowedAccountId, journalDiscount, 0.0, now);
            }
            if (salesAccountId != null && netRevenueAmount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': salesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(netRevenueAmount),
                'amount_base':
                    MoneyHelper.toCents(netRevenueAmount * effectiveExchangeRate),
                'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, 0.0, netRevenueAmount, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatPayableAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalTax),
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description': 'ضريبة قيمة مضافة مستحقة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatPayableAccountId, 0.0, journalTax, now);
            }
          }
        } else if (invoiceType == 'purchase' ||
            invoiceType == 'purchase_return') {
          if (isReturn) {
            // ── Purchase return: Net recording (reverse of original purchase) ──
            // Debit: Cash/Supplier = journalTotal (amount refunded)
            // Debit: Discount Earned = journalDiscount (reverse discount revenue, if any)
            // Credit: Purchases = netPurchaseCost (reverse purchase at net)
            // Credit: VAT Receivable = journalTax (reverse VAT asset, if any)
            // Balanced: journalTotal + journalDiscount = netPurchaseCost + journalTax
            final debitAccountId = paymentMechanism == 'credit'
                ? suppliersAccountId
                : cashBanksAccountId;
            if (debitAccountId != null && journalTotal.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': debitAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalTotal),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalTotal * effectiveExchangeRate),
                'description': 'فاتورة مشتريات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, debitAccountId, journalTotal, 0.0, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountEarnedAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalDiscount),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description':
                    'عكس خصم مشتريات مكتسب - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountEarnedAccountId, journalDiscount, 0.0, now);
            }
            if (purchasesAccountId != null && netPurchaseCost.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(netPurchaseCost),
                'amount_base':
                    MoneyHelper.toCents(netPurchaseCost * effectiveExchangeRate),
                'description': 'عكس مشتريات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, 0.0, netPurchaseCost, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatReceivableAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalTax),
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description':
                    'عكس ضريبة مشتريات - مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatReceivableAccountId, 0.0, journalTax, now);
            }
          } else if (isPartialCash) {
            // ── Partial cash purchase: Net recording ──
            // Debit: Purchases = netPurchaseCost (net cost including transport, before tax)
            // Debit: VAT Receivable = journalTax (if any, Asset account 1400+offset)
            // Credit: Cash = journalEffectivePaid
            // Credit: Supplier = journalRemainingAmount
            // Credit: Discount Earned = journalDiscount (if any)
            // Balanced: netPurchaseCost + journalTax = journalEffectivePaid + journalRemainingAmount + journalDiscount
            if (purchasesAccountId != null && netPurchaseCost.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(netPurchaseCost),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(netPurchaseCost * effectiveExchangeRate),
                'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, netPurchaseCost, 0.0, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatReceivableAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalTax),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description': 'ضريبة قيمة مضافة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatReceivableAccountId, journalTax, 0.0, now);
            }
            if (cashBanksAccountId != null &&
                journalEffectivePaid.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': cashBanksAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalEffectivePaid),
                'amount_base': MoneyHelper.toCents(
                    journalEffectivePaid * effectiveExchangeRate),
                'description': 'فاتورة مشتريات (مدفوع) - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cashBanksAccountId, 0.0, journalEffectivePaid, now);
            }
            if (suppliersAccountId != null &&
                journalRemainingAmount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': suppliersAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalRemainingAmount),
                'amount_base': MoneyHelper.toCents(
                    journalRemainingAmount * effectiveExchangeRate),
                'description': 'فاتورة مشتريات (آجل) - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, suppliersAccountId, 0.0, journalRemainingAmount, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountEarnedAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalDiscount),
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description': 'خصم مشتريات مكتسب - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountEarnedAccountId, 0.0, journalDiscount, now);
            }
          } else {
            // ── Normal purchase: Net recording (C-01/C-02/M-02) ──
            // Debit: Purchases = netPurchaseCost (net cost including transport, before tax)
            // Debit: VAT Receivable = journalTax (if any, ASSET account 1400+offset — C-05)
            // Credit: Cash/Supplier = journalTotal
            // Credit: Discount Earned = journalDiscount (if any)
            // Balanced: netPurchaseCost + journalTax = journalTotal + journalDiscount
            if (purchasesAccountId != null && netPurchaseCost.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(netPurchaseCost),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(netPurchaseCost * effectiveExchangeRate),
                'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, netPurchaseCost, 0.0, now);
            }
            if (journalTax.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': vatReceivableAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(journalTax),
                'credit': 0,
                'amount_base':
                    MoneyHelper.toCents(journalTax * effectiveExchangeRate),
                'description': 'ضريبة قيمة مضافة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, vatReceivableAccountId, journalTax, 0.0, now);
            }
            final creditAccountId = paymentMechanism == 'credit'
                ? suppliersAccountId
                : cashBanksAccountId;
            if (creditAccountId != null && journalTotal.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': creditAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalTotal),
                'amount_base':
                    MoneyHelper.toCents(journalTotal * effectiveExchangeRate),
                'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, creditAccountId, 0.0, journalTotal, now);
            }
            if (journalDiscount.abs() >= 0.005) {
              await txn.insert('transactions', {
                'account_id': discountEarnedAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(journalDiscount),
                'amount_base':
                    MoneyHelper.toCents(journalDiscount * effectiveExchangeRate),
                'description': 'خصم مشتريات مكتسب - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': journalCurrency,
                'exchange_rate': effectiveExchangeRate,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, discountEarnedAccountId, 0.0, journalDiscount, now);
            }
          }
        }

        // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
        // P-01: Use product-specific account IDs when available, fall back to default accounts.
        // Group items by (cogs_account_id, inventory_account_id) to create aggregate entries per group.
        if ((invoiceType == 'sale' ||
            invoiceType == 'pos' ||
            invoiceType == 'sale_return')) {
          if (isReturn) {
            // M-08: Use reverseCOGSAllocations to restore original cost layers
            // instead of calculateCOGSInTransaction which consumes new layers
            await _dbHelper.costingEngine.reverseCOGSAllocationsInTransaction(
              txn,
              invoiceId: invoiceMap['id'] as String,
            );
          }

          // Resolve default COGS + Inventory account IDs
          final cogsCode = (3200 + codeOffset).toString();
          final inventoryCode = (1300 + codeOffset).toString();
          final cogsInventoryRows = await txn.query(
            'accounts',
            where: 'account_code IN (?, ?) AND currency = ?',
            whereArgs: [cogsCode, inventoryCode, journalCurrency],
          );
          final defaultCogsAccountId = cogsInventoryRows
              .where((r) => r['account_code'] == cogsCode)
              .firstOrNull?['id'] as int?;
          final defaultInventoryAccountId = cogsInventoryRows
              .where((r) => r['account_code'] == inventoryCode)
              .firstOrNull?['id'] as int?;

          // Group items by their effective (cogs_account, inventory_account) pair
          final cogsGroups = <String, double>{};
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final baseQuantity =
                (item['base_quantity'] as num?)?.toDouble() ?? quantity;
            if (productId == null) continue;

            final productRow = await txn.query('products',
                where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isEmpty) continue;

            // FIX: Use CostingEngineService to properly consume FIFO/LIFO
            // cost layers instead of always using weighted average cost.
            final costingMethodStr =
                productRow.first['costing_method'] as String? ??
                    'weighted_average';
            final costingMethod = CostingMethodExt.fromValue(costingMethodStr);

            double itemCogs;
            if (isReturn) {
              // M-08: For sale returns, use average_cost for COGS (layers already restored above)
              final averageCost =
                  MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = averageCost > 0
                  ? averageCost
                  : MoneyHelper.readMoney(productRow.first['cost_price']);
              itemCogs = effectiveCost * baseQuantity;
            } else if (costingMethod != CostingMethod.weightedAverage) {
              // FIFO/LIFO: consume cost layers via costing engine (only for non-return sales)
              itemCogs =
                  await _dbHelper.costingEngine.calculateCOGSInTransaction(
                txn,
                productId: productId,
                baseQuantity: baseQuantity,
                invoiceId: invoiceMap['id'] as String,
                codeOffset: codeOffset,
              );
            } else {
              // Weighted average: use average_cost / cost_price directly
              final averageCost =
                  MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = averageCost > 0
                  ? averageCost
                  : MoneyHelper.readMoney(productRow.first['cost_price']);
              itemCogs = effectiveCost * baseQuantity;
            }
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
              // A-09: COGS/Inventory entries are ALWAYS in base currency (YER)
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(totalCogs),
                'credit': 0,
                'amount_base': MoneyHelper.toCents(totalCogs),
                'description': 'تكلفة بضاعة مباعة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(totalCogs),
                'amount_base': MoneyHelper.toCents(totalCogs),
                'description': 'تخفيض مخزون - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cogsAccountId, totalCogs, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, inventoryAccountId, 0.0, totalCogs, now);
            } else {
              // Sale return: Debit Inventory, Credit COGS (reverse)
              // A-09: COGS/Inventory entries are ALWAYS in base currency (YER)
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(totalCogs),
                'credit': 0,
                'amount_base': MoneyHelper.toCents(totalCogs),
                'description': 'إعادة مخزون مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(totalCogs),
                'amount_base': MoneyHelper.toCents(totalCogs),
                'description': 'عكس تكلفة بضاعة مرتجعة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'reference_type': invoiceType,
                'reference_id': invoiceMap['id'] as String?,
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, inventoryAccountId, totalCogs, 0.0, now);
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cogsAccountId, 0.0, totalCogs, now);
            }
          }
        }

        // ── Purchase Inventory Transfer Entries ──
        // P-01: Use product-specific account IDs when available, fall back to default accounts.
        // Group items by (inventory_account_id, purchase_account_id) to create aggregate entries per group.
        // For purchase returns, also transfer from Inventory back to Purchases clearing account.
        if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
          // Resolve default Inventory + Purchases account IDs
          final inventoryCode = (1300 + codeOffset).toString();
          final purchasesCode = (3100 + codeOffset).toString();
          final invPurchRows = await txn.query(
            'accounts',
            where: 'account_code IN (?, ?) AND currency = ?',
            whereArgs: [inventoryCode, purchasesCode, journalCurrency],
          );
          final defaultInventoryAccountId = invPurchRows
              .where((r) => r['account_code'] == inventoryCode)
              .firstOrNull?['id'] as int?;
          final defaultPurchasesAccountId = invPurchRows
              .where((r) => r['account_code'] == purchasesCode)
              .firstOrNull?['id'] as int?;

          // Group items by their effective (inventory_account, purchase_account) pair
          // Use unitPrice (actual purchase price) for the inventory transfer entry
          // to ensure purchases account zeros out correctly.
          final purchGroups = <String, double>{};
          // For purchase returns, use average_cost instead of unitPrice
          final returnGroups = <String, double>{};
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final unitPrice = MoneyHelper.readMoney(item['unit_price']);
            if (productId == null) continue;
            final productRow = await txn.query('products',
                where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isEmpty) continue;

            if (!isReturn) {
              // Normal purchase: use quantity * unitPrice for transfer
              final itemCost = quantity * unitPrice;
              if (itemCost.abs() < 0.005) continue;

              final prodInvId =
                  productRow.first['inventory_account_id'] as int?;
              final prodPurchId =
                  productRow.first['purchase_account_id'] as int?;
              final effectiveInvId = prodInvId ?? defaultInventoryAccountId;
              final effectivePurchId = prodPurchId ?? defaultPurchasesAccountId;
              if (effectiveInvId == null || effectivePurchId == null) continue;
              final key = '${effectiveInvId}_$effectivePurchId';
              purchGroups[key] = (purchGroups[key] ?? 0.0) + itemCost;
            } else {
              // Purchase return: use average_cost for the return transfer (C-03)
              final avgCost =
                  MoneyHelper.readMoney(productRow.first['average_cost']);
              final effectiveCost = avgCost > 0
                  ? avgCost
                  : MoneyHelper.readMoney(productRow.first['cost_price']);
              final baseQuantity =
                  (item['base_quantity'] as num?)?.toDouble() ?? quantity;
              final itemCost = effectiveCost * baseQuantity;
              if (itemCost.abs() < 0.005) continue;

              final prodInvId =
                  productRow.first['inventory_account_id'] as int?;
              final prodPurchId =
                  productRow.first['purchase_account_id'] as int?;
              final effectiveInvId = prodInvId ?? defaultInventoryAccountId;
              final effectivePurchId = prodPurchId ?? defaultPurchasesAccountId;
              if (effectiveInvId == null || effectivePurchId == null) continue;
              final key = '${effectiveInvId}_$effectivePurchId';
              returnGroups[key] = (returnGroups[key] ?? 0.0) + itemCost;
            }
          }

          // Normal purchase inventory transfers
          for (final entry in purchGroups.entries) {
            final totalPurchaseCost = entry.value;
            if (totalPurchaseCost.abs() < 0.005) continue;
            final parts = entry.key.split('_');
            final inventoryAccountId = int.tryParse(parts[0]);
            final purchasesAccountId = int.tryParse(parts[1]);
            if (inventoryAccountId == null || purchasesAccountId == null) {
              continue;
            }

            // Purchase: Debit Inventory (goods come in), Credit Purchases (transfer from purchases account)
            await txn.insert('transactions', {
              'account_id': inventoryAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalPurchaseCost),
              'credit': 0,
              'description': 'إضافة مخزون مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalPurchaseCost),
              'description': 'تحويل من حساب المشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, inventoryAccountId, totalPurchaseCost, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, purchasesAccountId, 0.0, totalPurchaseCost, now);
          }

          // Purchase return inventory transfers (C-03)
          for (final entry in returnGroups.entries) {
            final totalReturnCost = entry.value;
            if (totalReturnCost.abs() < 0.005) continue;
            final parts = entry.key.split('_');
            final inventoryAccountId = int.tryParse(parts[0]);
            final purchasesAccountId = int.tryParse(parts[1]);
            if (inventoryAccountId == null || purchasesAccountId == null) {
              continue;
            }

            // Purchase return: Debit Purchases (reverse), Credit Inventory (reverse at cost)
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalReturnCost),
              'credit': 0,
              'description': 'تحويل مرتجع مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await txn.insert('transactions', {
              'account_id': inventoryAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalReturnCost),
              'description': 'تخفيض مخزون مرتجع مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, purchasesAccountId, totalReturnCost, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, inventoryAccountId, 0.0, totalReturnCost, now);
          }
        }

        // ── VAT entries are now part of the main entries (C-05 fix) ──
        // VAT is already included in the main sale/purchase entries above.
        // No separate VAT reversal section needed — the old gross-up pattern is removed.

        // ── Discount entries are now part of the main entry (C-01/C-02 fix) ──
        // Discounts are already included in the main sale/purchase entries above.
        // No separate discount reversal section needed — the old gross-up pattern is removed.

        // ── M-01/M-10: Transport entries ──
        // Sales transport: REMOVED. Transport is already included in netRevenueAmount.
        // The customer pays for transport as part of the total, so it's revenue.

        // Purchase transport: Move transport from Purchases clearing to Inventory (IAS 2)
        // This ensures: (1) Purchases account zeros out correctly, (2) Inventory valuation includes transport
        if (yerTransport.abs() >= 0.005 &&
            invoiceType == 'purchase' &&
            !isReturn) {
          // Debit: Inventory = yerTransport (capitalize transport into inventory per IAS 2)
          // Credit: Purchases = yerTransport (reduce purchases by transport, it's now in inventory)
          final inventoryCode = (1300 + codeOffset).toString();
          final purchasesCode = (3100 + codeOffset).toString();
          final transportInvRows = await txn.query(
            'accounts',
            where: 'account_code IN (?, ?) AND currency = ?',
            whereArgs: [inventoryCode, purchasesCode, journalCurrency],
          );
          final transportInvAccountId = transportInvRows
              .where((r) => r['account_code'] == inventoryCode)
              .firstOrNull?['id'] as int?;
          final transportPurchAccountId = transportInvRows
              .where((r) => r['account_code'] == purchasesCode)
              .firstOrNull?['id'] as int?;

          if (transportInvAccountId != null &&
              transportPurchAccountId != null) {
            await txn.insert('transactions', {
              'account_id': transportInvAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(yerTransport),
              'credit': 0,
              'description':
                  'رأس مالية مصاريف نقل في المخزون - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await txn.insert('transactions', {
              'account_id': transportPurchAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(yerTransport),
              'description':
                  'تحويل مصاريف نقل من المشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, transportInvAccountId, yerTransport, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, transportPurchAccountId, 0.0, yerTransport, now);
          }
        }

        // Purchase return transport: Reverse the transport transfer
        if (yerTransport.abs() >= 0.005 &&
            invoiceType == 'purchase' &&
            isReturn) {
          // Debit: Purchases = yerTransport
          // Credit: Inventory = yerTransport
          final inventoryCode = (1300 + codeOffset).toString();
          final purchasesCode = (3100 + codeOffset).toString();
          final transportInvRows = await txn.query(
            'accounts',
            where: 'account_code IN (?, ?) AND currency = ?',
            whereArgs: [inventoryCode, purchasesCode, journalCurrency],
          );
          final transportInvAccountId = transportInvRows
              .where((r) => r['account_code'] == inventoryCode)
              .firstOrNull?['id'] as int?;
          final transportPurchAccountId = transportInvRows
              .where((r) => r['account_code'] == purchasesCode)
              .firstOrNull?['id'] as int?;

          if (transportInvAccountId != null &&
              transportPurchAccountId != null) {
            await txn.insert('transactions', {
              'account_id': transportPurchAccountId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(yerTransport),
              'credit': 0,
              'description':
                  'عكس تحويل مصاريف نقل - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await txn.insert('transactions', {
              'account_id': transportInvAccountId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(yerTransport),
              'description':
                  'عكس رأس مالية نقل في المخزون - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
              'currency_code': journalCurrency,
              'exchange_rate': effectiveExchangeRate,
              'reference_type': invoiceType,
              'reference_id': invoiceMap['id'] as String?,
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, transportPurchAccountId, yerTransport, 0.0, now);
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, transportInvAccountId, 0.0, yerTransport, now);
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
        await txn.update('invoices', {'is_posted': 1},
            where: 'id = ?', whereArgs: [invoiceMap['id']]);

        // ── Update customer/supplier balance with balance_type-aware logic ──
        // For full cash payments: entity balance should NOT change (they already paid in full)
        // For partial cash: only the remaining unpaid amount affects entity balance
        // For credit: entity owes the full amount (total already includes transport)
        //
        // Accounting direction convention:
        //   Customer: Sale on credit → debit effect (عليه, they owe us more)
        //   Customer: Sale return → credit effect (له, we owe them more)
        //   Supplier: Purchase on credit → credit effect (له, we owe them more)
        //   Supplier: Purchase return → debit effect (عليه, they owe us more)
        if (invoiceMap['customer_id'] != null) {
          final customerId = invoiceMap['customer_id'] as int;
          final isSaleDebit = (invoiceType == 'sale' && !isReturn) ||
              (invoiceType == 'sale_return' && isReturn);
          double customerAmount;
          if (paymentMechanism == 'cash' && !isPartialCash) {
            customerAmount = 0;
          } else if (isPartialCash && !isReturn) {
            customerAmount = remainingAmount;
          } else {
            customerAmount = total;
          }
          if (customerAmount.abs() >= 0.005) {
            if (isSaleDebit) {
              // Sale: customer owes us more → debit effect
              await EntityBalanceHelper.customerSaleOnCredit(
                txn: txn,
                customerId: customerId,
                amount: customerAmount,
                now: now,
              );
            } else {
              // Return: we owe customer more → credit effect
              await EntityBalanceHelper.customerSaleReturn(
                txn: txn,
                customerId: customerId,
                amount: customerAmount,
                now: now,
              );
            }
          }
        }

        if (invoiceMap['supplier_id'] != null) {
          final supplierId = invoiceMap['supplier_id'] as int;
          final isPurchaseCredit = (invoiceType == 'purchase' && !isReturn) ||
              (invoiceType == 'purchase_return' && isReturn);
          double supplierAmount;
          if (paymentMechanism == 'cash' && !isPartialCash) {
            supplierAmount = 0;
          } else if (isPartialCash && !isReturn) {
            supplierAmount = remainingAmount;
          } else {
            supplierAmount = total;
          }
          if (supplierAmount.abs() >= 0.005) {
            if (isPurchaseCredit) {
              // Purchase: we owe supplier more → credit effect
              await EntityBalanceHelper.supplierPurchaseOnCredit(
                txn: txn,
                supplierId: supplierId,
                amount: supplierAmount,
                now: now,
              );
            } else {
              // Return: supplier owes us more → debit effect
              await EntityBalanceHelper.supplierPurchaseReturn(
                txn: txn,
                supplierId: supplierId,
                amount: supplierAmount,
                now: now,
              );
            }
          }
        }

        // Update cash box balance (total already includes transport charges)
        if (cashBoxId != null) {
          // For partial payments, only update cash box with the paid amount
          final cashAmount = isPartialCash ? effectivePaid : total;
          final isCashIn = (invoiceType == 'sale' && !isReturn) ||
              (invoiceType == 'purchase' && isReturn);
          // Check cash box balance_type to determine direction
          final cbRow = await txn.query('cash_boxes',
              where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
          final cbBalanceType = cbRow.isNotEmpty
              ? (cbRow.first['balance_type'] as String? ?? 'credit')
              : 'credit';
          if (cbBalanceType == 'credit') {
            // Credit-type (له): money in increases balance, money out decreases
            if (isCashIn) {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
            }
          } else {
            // Debit-type (عليه): money in decreases balance (less owed), money out increases balance (more owed)
            if (isCashIn) {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                  [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
            } else {
              await txn.rawUpdate(
                  'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                  [MoneyHelper.toCents(cashAmount), now, cashBoxId]);
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
      await _dbHelper.audit.logAuditEvent(
        action: 'error',
        tableName: 'invoices',
        recordId: int.tryParse(invoiceMap['id']?.toString() ?? ''),
        recordType: invoiceType,
        oldValues: 'خطأ أثناء حفظ الفاتورة: $e',
      );
      throw Exception('حدث خطأ أثناء حفظ الفاتورة: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllInvoices(
      {String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
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
    return await db.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  /// Get a single invoice by its ID.
  Future<Map<String, dynamic>?> getInvoiceById(String invoiceId) async {
    final db = await _db;
    final results = await db.query('invoices',
        where: 'id = ?', whereArgs: [invoiceId], limit: 1);
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
    return await db.update('invoices', {'status': 'cancelled'},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Delete an invoice and all its related records (CASCADE behavior).
  ///
  /// B-1.5 (A-3) full rewrite — the previous version had three critical
  /// accounting bugs:
  ///   1. Deleted stock_movements WITHOUT restoring product quantities →
  ///      permanent stock corruption.
  ///   2. Deleted journal transactions WITHOUT reversing account balances
  ///      (the "next reconciliation" never ran automatically) → inflated
  ///      account/customer/cash balances forever.
  ///   3. Matched journals with LIKE '%invoiceId%' → invoice "12" could
  ///      match "112"/"120" and delete OTHER invoices' journal entries.
  ///
  /// This version, inside ONE transaction:
  ///   - Restores stock quantities from the invoice's stock movements.
  ///   - Restores FIFO/LIFO cost layers (consumed allocations re-opened,
  ///     layers created by this purchase removed).
  ///   - Finds journal rows precisely via reference_id, or the exact
  ///     suffix pattern '% - invoiceId' (never a bare substring match),
  ///     reverses every row's effect on its account balance, then deletes.
  ///   - Reverses the entity (customer/supplier) open balance by the
  ///     invoice's `remaining` (payments already reduced it).
  ///   - Reverses the cash box by `paid_amount` on the invoice's cash box.
  ///
  /// Note: weighted-average cost is intentionally NOT recalculated
  /// backwards (period costing standard practice); FIFO/LIFO layers are
  /// restored exactly.
  Future<int> deleteInvoiceWithCascade(String invoiceId) async {
    final db = await _db;

    // Fiscal-period guard BEFORE opening the transaction (same pattern as
    // CashBoxService.deleteVoucher — checkFiscalPeriodOpen uses its own
    // db handle and must not run inside an open transaction).
    final preRows = await db.query('invoices',
        where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (preRows.isEmpty) return 0;
    final preDate = preRows.first['created_at'] as String? ??
        DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(preDate);

    final now = DateTime.now().toIso8601String();
    return await db.transaction((txn) async {
      final invRows = await txn.query('invoices',
          where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (invRows.isEmpty) return 0;
      final inv = invRows.first;
      final type = inv['type'] as String? ?? 'sale';
      final isReturn = (inv['is_return'] as int? ?? 0) == 1;

      // ── 1. Restore stock quantities, then delete the movements ──
      // The movement's `quantity` column stores the signed delta that was
      // applied to current_stock (sale: -qty, purchase: +qty, returns
      // opposite) — so reversal is simply `current_stock - quantity`.
      final movements = await txn.query('stock_movements',
          where: 'reference_id = ?', whereArgs: [invoiceId]);
      for (final m in movements) {
        final productId = (m['product_id'] as num?)?.toInt();
        final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
        if (productId != null && qty != 0) {
          await txn.rawUpdate(
            'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
            [qty, now, productId],
          );
        }
      }
      await txn.delete('stock_movements',
          where: 'reference_id = ?', whereArgs: [invoiceId]);

      // ── 2. FIFO/LIFO cost layers ──
      // Sales: re-open the layers this invoice consumed.
      await _dbHelper.costingEngine
          .reverseCOGSAllocationsInTransaction(txn, invoiceId: invoiceId);
      // Purchases: remove the layers this invoice created.
      await txn.delete('inventory_cost_layers',
          where: 'reference_id = ?', whereArgs: [invoiceId]);

      // ── 3. Locate journal rows precisely (NO bare substring LIKE) ──
      final matched = await txn.rawQuery(
        'SELECT * FROM transactions WHERE reference_id = ? OR description LIKE ?',
        [invoiceId, '% - $invoiceId'],
      );
      // Wipe whole journal entries so no orphan half-entries remain.
      final journalIds =
          matched.map((t) => t['journal_id']).where((j) => j != null).toSet();
      final rowsById = <Object?, Map<String, Object?>>{};
      for (final r in matched) {
        rowsById[r['id']] = r;
      }
      for (final j in journalIds) {
        final siblings = await txn
            .query('transactions', where: 'journal_id = ?', whereArgs: [j]);
        for (final r in siblings) {
          rowsById[r['id']] = r;
        }
      }

      // ── 4. Reverse each row's account-balance effect, then delete ──
      for (final r in rowsById.values) {
        final accountId = (r['account_id'] as num?)?.toInt();
        if (accountId != null) {
          final debit = MoneyHelper.readMoney(r['debit']);
          final credit = MoneyHelper.readMoney(r['credit']);
          // Opposite application: swap debit/credit.
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, accountId, credit, debit, now);
        }
        await txn.delete('transactions', where: 'id = ?', whereArgs: [r['id']]);
      }

      // ── 5. Reverse entity open balance by `remaining` ──
      // Payments recorded after the sale already reduced the entity
      // balance, so the invoice's outstanding effect today == remaining.
      final remaining = MoneyHelper.readMoney(inv['remaining']);
      final customerId = (inv['customer_id'] as num?)?.toInt();
      final supplierId = (inv['supplier_id'] as num?)?.toInt();
      if (remaining.abs() >= 0.005) {
        if (customerId != null && type == 'sale') {
          if (!isReturn) {
            // Credit sale added a debit on the customer → reverse = credit.
            await EntityBalanceHelper.customerSaleReturn(
                txn: txn, customerId: customerId, amount: remaining, now: now);
          } else {
            await EntityBalanceHelper.customerSaleOnCredit(
                txn: txn, customerId: customerId, amount: remaining, now: now);
          }
        }
        if (supplierId != null && type == 'purchase') {
          if (!isReturn) {
            // Credit purchase added a credit for the supplier → reverse = debit.
            await EntityBalanceHelper.supplierPurchaseReturn(
                txn: txn, supplierId: supplierId, amount: remaining, now: now);
          } else {
            await EntityBalanceHelper.supplierPurchaseOnCredit(
                txn: txn, supplierId: supplierId, amount: remaining, now: now);
          }
        }
      }

      // ── 6. Reverse the cash box by `paid_amount` ──
      // (Assumes payments flowed into the invoice's cash box — the
      // overwhelmingly common case; GL accounts are already exact from
      // step 4 regardless.)
      final paid = MoneyHelper.readMoney(inv['paid_amount']);
      final cashBoxId = (inv['cash_box_id'] as num?)?.toInt();
      if (cashBoxId != null && paid.abs() >= 0.005) {
        final isCashIn =
            (type == 'sale' && !isReturn) || (type == 'purchase' && isReturn);
        final cb = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cb.isNotEmpty) {
          final bt = cb.first['balance_type'] as String? ?? 'credit';
          // Original delta sign was +paid when (credit-nature == cashIn),
          // else -paid. Reversal applies the negation.
          final reversalSign = ((bt == 'credit') == isCashIn) ? -1 : 1;
          await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [reversalSign * MoneyHelper.toCents(paid), now, cashBoxId],
          );
        }
      }

      // ── 7. Delete items and the invoice itself ──
      await txn.delete('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      return await txn
          .delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
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
    final invoiceRows = await db.query('invoices',
        where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    final currentRemaining = MoneyHelper.readMoney(invoice['remaining']);
    final currentPaid = MoneyHelper.readMoney(invoice['paid_amount']);
    final total = MoneyHelper.readMoney(invoice['total']);
    final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
    final exchangeRate = (invoice['exchange_rate'] as num?)?.toDouble() ?? 1.0;
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
      final codeOffset = await locator<BaseCurrencyService>().getOffsetForCurrency(invoiceCurrency);
      final double effectiveExchangeRate =
          exchangeRate > 0 ? exchangeRate : 1.0;

      final cashBanksAccount = await txn.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency],
          limit: 1);
      final customersAccount = await txn.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency],
          limit: 1);
      final suppliersAccount = await txn.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency],
          limit: 1);

      final cashBanksAccountId = cashBanksAccount.isNotEmpty
          ? cashBanksAccount.first['id'] as int
          : null;
      final customersAccountId = customersAccount.isNotEmpty
          ? customersAccount.first['id'] as int
          : null;
      final suppliersAccountId = suppliersAccount.isNotEmpty
          ? suppliersAccount.first['id'] as int
          : null;

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
            'amount_base':
                MoneyHelper.toCents(paymentAmount * effectiveExchangeRate),
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
            'currency_code': invoiceCurrency,
            'exchange_rate': effectiveExchangeRate,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, cashBanksAccountId, paymentAmount, 0.0, now);
        }
        if (customersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': customersAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(paymentAmount),
            'amount_base':
                MoneyHelper.toCents(paymentAmount * effectiveExchangeRate),
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
            'currency_code': invoiceCurrency,
            'exchange_rate': effectiveExchangeRate,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, customersAccountId, 0.0, paymentAmount, now);
        }
      } else if (invoiceType == 'purchase') {
        // Purchase: we are paying supplier → Debit supplier, Credit cash
        if (suppliersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': suppliersAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(paymentAmount),
            'credit': 0,
            'amount_base':
                MoneyHelper.toCents(paymentAmount * effectiveExchangeRate),
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
            'currency_code': invoiceCurrency,
            'exchange_rate': effectiveExchangeRate,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, suppliersAccountId, paymentAmount, 0.0, now);
        }
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(paymentAmount),
            'amount_base':
                MoneyHelper.toCents(paymentAmount * effectiveExchangeRate),
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
            'currency_code': invoiceCurrency,
            'exchange_rate': effectiveExchangeRate,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, cashBanksAccountId, 0.0, paymentAmount, now);
        }
      } else if (invoiceType == 'purchase_return') {
        // Purchase return: supplier is paying us (refund for returned goods)
        // Debit cash (money comes in), Credit supplier (liability increases back)
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(paymentAmount),
            'credit': 0,
            'description': 'استرداد دفعة مرتجع مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, cashBanksAccountId, paymentAmount, 0.0, now);
        }
        if (suppliersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': suppliersAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(paymentAmount),
            'description': 'استرداد دفعة مرتجع مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, suppliersAccountId, 0.0, paymentAmount, now);
        }
      }

      // 6. Update customer balance (customer owes less after payment → credit effect)
      if (customerId != null) {
        await EntityBalanceHelper.customerReceipt(
          txn: txn,
          customerId: customerId,
          amount: paymentAmount,
          now: now,
        );
      }

      // 7. Update supplier balance
      // Purchase invoice: we pay the supplier → debit effect (reduces what we owe)
      // Purchase return: supplier pays us → credit effect (increases what we owe / reduces debit balance)
      if (supplierId != null) {
        if (invoiceType == 'purchase_return') {
          await EntityBalanceHelper.supplierReceipt(
            txn: txn,
            supplierId: supplierId,
            amount: paymentAmount,
            now: now,
          );
        } else {
          await EntityBalanceHelper.supplierPayment(
            txn: txn,
            supplierId: supplierId,
            amount: paymentAmount,
            now: now,
          );
        }
      }

      // 8. Update cash box balance
      // Sale: customer pays us → cash IN
      // Sale return: we refund the customer → cash OUT
      // Purchase: we pay the supplier → cash OUT
      // Purchase return: supplier refunds us → cash IN
      final isCashIn =
          invoiceType == 'sale' || invoiceType == 'purchase_return';
      if (isCashIn) {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(paymentAmount), now, cashBoxId]);
      } else {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(paymentAmount), now, cashBoxId]);
      }
    });
  }

  /// Cancel an invoice: soft-delete + reversal journal entries + balance reversals + stock restore.
  Future<void> cancelInvoice(String id) async {
    try {
      final db = await _db;
      final now = DateTime.now().toIso8601String();

      // Fetch invoice
      final invoiceRows = await db.query('invoices',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (invoiceRows.isEmpty) return;
      final invoice = invoiceRows.first;

      // Already cancelled — nothing to do
      if ((invoice['status'] as String?) == 'cancelled') return;

      // Check if the invoice date falls in a closed fiscal year
      final invoiceDate =
          invoice['date'] as String? ?? invoice['created_at'] as String;
      final isClosed = await _dbHelper.accounts
          .isDateInClosedPeriod(DateTime.parse(invoiceDate));
      if (isClosed) {
        throw Exception('لا يمكن إلغاء فاتورة في سنة مالية مغلقة');
      }

      final total = MoneyHelper.readMoney(invoice['total']);
      final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
      final invoiceType = (invoice['type'] as String?) ?? 'sale';
      final isReturn = (invoice['is_return'] as int?) == 1;
      final paymentMechanism =
          (invoice['payment_mechanism'] as String?) ?? 'cash';
      final cashBoxId = invoice['cash_box_id'] as int?;
      // ignore: unused_local_variable
      final transportCharges =
          MoneyHelper.readMoney(invoice['transport_charges']);

      // Fetch items for stock reversal
      final items = await db
          .query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);

      await db.transaction((txn) async {
        // 1. Set status to cancelled
        await txn.update('invoices', {'status': 'cancelled'},
            where: 'id = ?', whereArgs: [id]);

        // 2. Create reversal journal entries
        final journalId = generateUniqueJournalId();
        final codeOffset =
            invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

        final salesAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(4100 + codeOffset).toString(), invoiceCurrency],
            limit: 1);
        final purchasesAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency],
            limit: 1);
        final customersAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency],
            limit: 1);
        final suppliersAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency],
            limit: 1);
        final cashBanksAccount = await txn.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency],
            limit: 1);

        final salesAccountId =
            salesAccount.isNotEmpty ? salesAccount.first['id'] as int : null;
        final purchasesAccountId = purchasesAccount.isNotEmpty
            ? purchasesAccount.first['id'] as int
            : null;
        final customersAccountId = customersAccount.isNotEmpty
            ? customersAccount.first['id'] as int
            : null;
        final suppliersAccountId = suppliersAccount.isNotEmpty
            ? suppliersAccount.first['id'] as int
            : null;
        final cashBanksAccountId = cashBanksAccount.isNotEmpty
            ? cashBanksAccount.first['id'] as int
            : null;

        // Determine original debit/credit accounts and handle partial payments
        // Check for partial payment (same logic as saveInvoiceWithJournalEntries)
        final paidAmount = MoneyHelper.readMoney(invoice['paid_amount']);
        final remainingAmount = MoneyHelper.readMoney(invoice['remaining']);
        final isPartialCash = paymentMechanism == 'cash' &&
            paidAmount > 0.005 &&
            remainingAmount > 0.005;

        if (invoiceType == 'sale' ||
            invoiceType == 'sale_return' ||
            invoiceType == 'pos') {
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cashBanksAccountId, 0.0, paidAmount, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, customersAccountId, 0.0, remainingAmount, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, total, 0.0, now);
            }
          } else if (isReturn) {
            // Reverse sale return: Debit Customer/Cash (original credit), Credit Sales (original debit)
            final originalCreditAccountId = paymentMechanism == 'credit'
                ? customersAccountId
                : cashBanksAccountId;
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, originalCreditAccountId, total, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, 0.0, total, now);
            }
          } else {
            // Normal reversal (full cash or full credit): swap debit/credit
            final originalDebitAccountId = paymentMechanism == 'credit'
                ? customersAccountId
                : cashBanksAccountId;
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, salesAccountId, total, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, originalDebitAccountId, 0.0, total, now);
            }
          }
        } else if (invoiceType == 'purchase' ||
            invoiceType == 'purchase_return') {
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, cashBanksAccountId, paidAmount, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, suppliersAccountId, remainingAmount, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, 0.0, total, now);
            }
          } else if (isReturn) {
            // Reverse purchase return: Debit Purchases (original credit), Credit Cash/Supplier (original debit)
            final originalDebitAccountId = paymentMechanism == 'credit'
                ? suppliersAccountId
                : cashBanksAccountId;
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, total, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, originalDebitAccountId, 0.0, total, now);
            }
          } else {
            // Normal reversal (full cash or full credit): swap debit/credit
            final originalCreditAccountId = paymentMechanism == 'credit'
                ? suppliersAccountId
                : cashBanksAccountId;
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, originalCreditAccountId, total, 0.0, now);
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
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, purchasesAccountId, 0.0, total, now);
            }
          }
        }

        // 2b. Reverse COGS journal entries (for sale invoices)
        if ((invoiceType == 'sale' ||
            invoiceType == 'pos' ||
            invoiceType == 'sale_return')) {
          final cogsAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency],
              limit: 1);
          final inventoryAccount = await txn.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency],
              limit: 1);
          final cogsAccountId =
              cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
          final inventoryAccountId = inventoryAccount.isNotEmpty
              ? inventoryAccount.first['id'] as int
              : null;

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
              final baseQuantity =
                  (item['base_quantity'] as num?)?.toDouble() ?? quantity;

              if (storedUnitCost > 0) {
                totalCogs += storedUnitCost * baseQuantity;
              } else {
                // Fallback to current cost_price if unit_cost wasn't stored
                final productRow = await txn.query('products',
                    where: 'id = ?', whereArgs: [productId], limit: 1);
                if (productRow.isEmpty) continue;
                final costPrice =
                    MoneyHelper.readMoney(productRow.first['cost_price']);
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
                await _dbHelper.journal.updateAccountBalanceWithJournal(
                    txn, inventoryAccountId, totalCogs, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(
                    txn, cogsAccountId, 0.0, totalCogs, now);
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
                await _dbHelper.journal.updateAccountBalanceWithJournal(
                    txn, cogsAccountId, totalCogs, 0.0, now);
                await _dbHelper.journal.updateAccountBalanceWithJournal(
                    txn, inventoryAccountId, 0.0, totalCogs, now);
              }
            }
          }
        }

        // 3. Transport charges reversal
        // NOTE: Transport charges are already included in `total`, so the main reversal entries above
        // already handle transport correctly. No separate transport reversal is needed.

        // 4. Reverse customer/supplier balance with balance_type-aware logic
        // Must mirror the save logic: full cash = no balance change, partial cash = only remaining, credit = total
        // REVERSAL means the OPPOSITE direction: if original was debit effect, reversal is credit effect
        if (invoice['customer_id'] != null) {
          final customerId = invoice['customer_id'] as int;
          final wasDebit = (invoiceType == 'sale' && !isReturn) ||
              (invoiceType == 'sale_return' && isReturn);
          double customerReversalAmount;
          if (paymentMechanism == 'cash' && !isPartialCash) {
            customerReversalAmount = 0;
          } else if (isPartialCash && !isReturn) {
            customerReversalAmount = remainingAmount;
          } else {
            customerReversalAmount = total;
          }
          if (customerReversalAmount.abs() >= 0.005) {
            if (wasDebit) {
              // Original was debit (sale) → reversal is credit (return)
              await EntityBalanceHelper.customerSaleReturn(
                txn: txn,
                customerId: customerId,
                amount: customerReversalAmount,
                now: now,
              );
            } else {
              // Original was credit (return) → reversal is debit (sale)
              await EntityBalanceHelper.customerSaleOnCredit(
                txn: txn,
                customerId: customerId,
                amount: customerReversalAmount,
                now: now,
              );
            }
          }
        }

        if (invoice['supplier_id'] != null) {
          final supplierId = invoice['supplier_id'] as int;
          final wasCreditToSupplier =
              (invoiceType == 'purchase' && !isReturn) ||
                  (invoiceType == 'purchase_return' && isReturn);
          double supplierReversalAmount;
          if (paymentMechanism == 'cash' && !isPartialCash) {
            supplierReversalAmount = 0;
          } else if (isPartialCash && !isReturn) {
            supplierReversalAmount = remainingAmount;
          } else {
            supplierReversalAmount = total;
          }
          if (supplierReversalAmount.abs() >= 0.005) {
            if (wasCreditToSupplier) {
              // Original was credit (purchase) → reversal is debit (return)
              await EntityBalanceHelper.supplierPurchaseReturn(
                txn: txn,
                supplierId: supplierId,
                amount: supplierReversalAmount,
                now: now,
              );
            } else {
              // Original was debit (return) → reversal is credit (purchase)
              await EntityBalanceHelper.supplierPurchaseOnCredit(
                txn: txn,
                supplierId: supplierId,
                amount: supplierReversalAmount,
                now: now,
              );
            }
          }
        }

        // 5. Reverse cash box balance
        // Must mirror the save logic: full cash = reverse total, partial cash = reverse paidAmount only
        if (cashBoxId != null) {
          final cashReversalAmount = isPartialCash ? paidAmount : total;
          final wasCashIn = (invoiceType == 'sale' && !isReturn) ||
              (invoiceType == 'purchase' && isReturn) ||
              (invoiceType == 'pos' && !isReturn);
          if (wasCashIn) {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
                [MoneyHelper.toCents(cashReversalAmount), now, cashBoxId]);
          } else {
            await txn.rawUpdate(
                'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
                [MoneyHelper.toCents(cashReversalAmount), now, cashBoxId]);
          }
          // No separate transport reversal needed - transport is already included in total/paidAmount
        }

        // 6. Restore product stock
        for (final item in items) {
          final productId = (item['product_id'] as num?)?.toInt();
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          if (productId == null) continue;
          // Check allow_negative for this product
          final prodRow = await txn.query('products',
              where: 'id = ?', whereArgs: [productId], limit: 1);
          final allowNeg = prodRow.isNotEmpty
              ? (prodRow.first['allow_negative'] as int?) == 1
              : false;

          if (invoiceType == 'sale' || invoiceType == 'pos') {
            if (!isReturn) {
              // Was decremented, now restore
              await txn.rawUpdate(
                  'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
                  [quantity, now, productId]);
            } else {
              // Was incremented (return), now decrement
              if (allowNeg) {
                await txn.rawUpdate(
                    'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                    [quantity, now, productId]);
              } else {
                await txn.rawUpdate(
                    'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                    [quantity, now, productId]);
              }
            }
          } else if (invoiceType == 'purchase') {
            if (!isReturn) {
              // Was incremented, now decrement
              if (allowNeg) {
                await txn.rawUpdate(
                    'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                    [quantity, now, productId]);
              } else {
                await txn.rawUpdate(
                    'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                    [quantity, now, productId]);
              }
            } else {
              // Was decremented (return), now restore
              await txn.rawUpdate(
                  'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
                  [quantity, now, productId]);
            }
          }
        }
      });

      // Log audit event for invoice cancellation
      await _dbHelper.audit.logAuditEvent(
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
      await _dbHelper.audit.logAuditEvent(
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
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) = ?",
        [dateStr]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Get total purchases for a specific date range and currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getTotalPurchasesForDateRange(
      String currency, String startStr, String endStr) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices "
      "WHERE type = 'purchase' AND is_return = 0 AND currency = ? "
      "AND created_at >= ? AND created_at < ?",
      [currency, startStr, endStr],
    );
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Calculate Cost of Goods Sold (COGS) for a specific date range and currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getCOGSForDateRange(
      String currency, String startStr, String endStr) async {
    final db = await _db;
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
        "AND i.currency = ? AND i.created_at >= ? AND i.created_at < ?",
        [currency, startStr, endStr],
      );
      return MoneyHelper.readCalculatedMoney(result.first['total_cogs']);
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> getTotalPurchasesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('purchase', 'purchase_return') AND is_return = 0 AND date(created_at) >= ?",
        [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  Future<double> getTotalSalesThisMonth() async {
    final db = await _db;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?",
        [monthStart]);
    return MoneyHelper.readCalculatedMoney(result.first['total']);
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
      return MoneyHelper.readCalculatedMoney(result.first['total_cogs']);
    } catch (e) {
      return 0.0;
    }
  }

  Future<int> getInvoiceCountForDate(DateTime date) async {
    final db = await _db;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM invoices WHERE date(created_at) = ?",
        [dateStr]);
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> getCashBalance() async {
    return _dbHelper.cashBoxes.getTotalCashBalance();
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
    final startDateStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr]);
  }

  Future<int> getNextInvoiceSequence(
      String datePrefix, String invoiceType) async {
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
  Future<Map<String, String>> checkReturnLimits(
      String originalInvoiceId, List<Map<String, dynamic>> returnItems) async {
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
        returnedQuantities[productId] =
            (returnedQuantities[productId] ?? 0.0) + qty;
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
        errors[productId.toString()] =
            'الكمية المرتجعة ($returnQty) تتجاوز الكمية المتبقية (${originalQty - alreadyReturned})';
      }
    }

    return errors;
  }

  // ══════════════════════════════════════════════════════════════
  //  Typed getters (C-09: domain model alternatives to raw maps)
  // ══════════════════════════════════════════════════════════════

  Future<List<Invoice>> getAllInvoiceObjects(
      {String orderBy = 'created_at DESC', int? limit, int offset = 0}) async {
    final maps =
        await getAllInvoices(orderBy: orderBy, limit: limit, offset: offset);
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
