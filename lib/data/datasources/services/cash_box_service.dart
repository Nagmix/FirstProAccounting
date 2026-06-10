import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/entity_balance_helper.dart';
import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class CashBoxService {
  final DatabaseHelper _dbHelper;
  CashBoxService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Cash Boxes & Banks CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCashBox(Map<String, dynamic> cashBoxMap) async {
    final db = await _db;
    return await db.insert('cash_boxes',
        MoneyHelper.toCentsMap(cashBoxMap, MoneyHelper.cashBoxMoneyFields));
  }

  Future<List<Map<String, dynamic>>> getAllCashBoxes() async {
    final db = await _db;
    return await db.query('cash_boxes',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'type ASC, name ASC');
  }

  Future<List<Map<String, dynamic>>> getCashBoxesByType(String type) async {
    final db = await _db;
    return await db.query('cash_boxes',
        where: 'type = ? AND is_active = ?',
        whereArgs: [type, 1],
        orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getCashBoxById(int id) async {
    final db = await _db;
    final results = await db.query('cash_boxes',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCashBox(int id, Map<String, dynamic> cashBoxMap) async {
    final db = await _db;
    return await db.update('cash_boxes',
        MoneyHelper.toCentsMap(cashBoxMap, MoneyHelper.cashBoxMoneyFields),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCashBox(int id) async {
    final db = await _db;

    // **Fix (7.5):** Referential integrity check before deletion.
    // Instead of a hard delete, we perform a soft delete (is_active = 0)
    // after checking that no dependent records exist. This preserves
    // audit trail and prevents orphaned references.

    // Check for dependent records across all related tables.
    final dependentChecks = <String, int>{};

    // 1. Invoices linked to this cash box
    final invoiceCount = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM invoices WHERE cash_box_id = ?', [id]);
    dependentChecks['invoices'] =
        (invoiceCount.first['cnt'] as num?)?.toInt() ?? 0;

    // 2. Vouchers linked to this cash box
    try {
      final voucherCount = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM vouchers WHERE cash_box_id = ?', [id]);
      dependentChecks['vouchers'] =
          (voucherCount.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      dependentChecks['vouchers'] = 0;
    }

    // 3. Expenses linked to this cash box
    final expenseCount = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM expenses WHERE cash_box_id = ?', [id]);
    dependentChecks['expenses'] =
        (expenseCount.first['cnt'] as num?)?.toInt() ?? 0;

    // 4. Cash transfers from/to this cash box
    try {
      final transferCount = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM cash_transfers WHERE from_cash_box_id = ? OR to_cash_box_id = ?',
          [id, id]);
      dependentChecks['cash_transfers'] =
          (transferCount.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      dependentChecks['cash_transfers'] = 0;
    }

    // 5. Currency exchanges from/to this cash box
    try {
      final exchangeCount = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM currency_exchanges WHERE from_cash_box_id = ? OR to_cash_box_id = ?',
          [id, id]);
      dependentChecks['currency_exchanges'] =
          (exchangeCount.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      dependentChecks['currency_exchanges'] = 0;
    }

    // 6. Shifts linked to this cash box
    final shiftCount = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM shifts WHERE cash_box_id = ?', [id]);
    dependentChecks['shifts'] = (shiftCount.first['cnt'] as num?)?.toInt() ?? 0;

    // 7. Bank reconciliations linked to this cash box
    try {
      final reconCount = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM bank_reconciliations WHERE cash_box_id = ?',
          [id]);
      dependentChecks['bank_reconciliations'] =
          (reconCount.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      dependentChecks['bank_reconciliations'] = 0;
    }

    // Build a list of dependent tables with records
    final hasDependents = dependentChecks.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key} (${e.value})')
        .toList();

    if (hasDependents.isNotEmpty) {
      throw Exception(
        'لا يمكن حذف الصندوق لوجود سجلات مرتبطة: ${hasDependents.join('، ')}. '
        'يمكنك تعطيل الصندوق بدلاً من حذفه.',
      );
    }

    // No dependents — safe to soft delete
    final now = DateTime.now().toIso8601String();
    return await db.update(
      'cash_boxes',
      {
        'is_active': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> getTotalCashBalance() async {
    final db = await _db;
    final result = await db.rawQuery(
        "SELECT CAST(COALESCE(SUM(CASE WHEN balance_type = 'credit' THEN balance ELSE -balance END), 0) AS INTEGER) AS total FROM cash_boxes WHERE is_active = 1");
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// Get total cash balance for a specific currency.
  /// Used by DashboardViewModel instead of raw SQL.
  Future<double> getCashBalanceForCurrency(String currency) async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT CAST(COALESCE(SUM(CASE "
      "WHEN balance_type = 'credit' THEN balance ELSE -balance END), 0) AS INTEGER) AS total "
      "FROM cash_boxes WHERE currency = ? AND is_active = 1",
      [currency],
    );
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// جلب الصناديق حسب العملة
  /// Get cash boxes filtered by currency (via linked account currency).
  Future<List<Map<String, dynamic>>> getCashBoxesByCurrency(
      String currency) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT cb.* FROM cash_boxes cb
      LEFT JOIN accounts a ON cb.linked_account_id = a.id
      WHERE cb.is_active = 1 AND (
        (a.currency = ?) OR (cb.linked_account_id IS NULL)
      )
      ORDER BY cb.type ASC, cb.name ASC
    ''', [currency]);
  }

  /// Calculate the balance of a specific cash box for a given currency
  /// by summing all financial movements (vouchers, transfers, exchanges,
  /// invoices) in that currency.
  ///
  /// Cash boxes are currency-agnostic, so a single cash box can have
  /// balances in multiple currencies. This method computes the balance
  /// for one specific currency.
  Future<double> getCashBoxBalanceForCurrency(
      int cashBoxId, String currency) async {
    final db = await _db;
    double balance = 0.0;

    // 1. Receipt vouchers (cash in) for this cash box in this currency
    final receipts = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS total FROM vouchers
      WHERE cash_box_id = ? AND voucher_type = 'receipt' AND currency = ?
    ''', [cashBoxId, currency]);
    balance += MoneyHelper.readCalculatedMoney(receipts.first['total']);

    // 2. Payment vouchers (cash out) for this cash box in this currency
    final payments = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS total FROM vouchers
      WHERE cash_box_id = ? AND voucher_type = 'payment' AND currency = ?
    ''', [cashBoxId, currency]);
    balance -= MoneyHelper.readCalculatedMoney(payments.first['total']);

    // 3. Incoming transfers for this cash box in this currency
    final inTransfers = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total FROM cash_transfers
      WHERE to_cash_box_id = ? AND currency = ?
    ''', [cashBoxId, currency]);
    balance += MoneyHelper.readCalculatedMoney(inTransfers.first['total']);

    // 4. Outgoing transfers from this cash box in this currency
    final outTransfers = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total FROM cash_transfers
      WHERE from_cash_box_id = ? AND currency = ?
    ''', [cashBoxId, currency]);
    balance -= MoneyHelper.readCalculatedMoney(outTransfers.first['total']);

    // 5. Currency exchanges - incoming (to_amount in to_currency)
    final inExchanges = await db.rawQuery('''
      SELECT COALESCE(SUM(to_amount), 0) AS total FROM currency_exchanges
      WHERE to_cash_box_id = ? AND to_currency = ?
    ''', [cashBoxId, currency]);
    balance += MoneyHelper.readCalculatedMoney(inExchanges.first['total']);

    // 6. Currency exchanges - outgoing (from_amount in from_currency)
    final outExchanges = await db.rawQuery('''
      SELECT COALESCE(SUM(from_amount), 0) AS total FROM currency_exchanges
      WHERE from_cash_box_id = ? AND from_currency = ?
    ''', [cashBoxId, currency]);
    balance -= MoneyHelper.readCalculatedMoney(outExchanges.first['total']);

    // 7. Sales invoices (cash in) - paid_amount for this cash box in this currency
    final salesPaid = await db.rawQuery('''
      SELECT COALESCE(SUM(paid_amount), 0) AS total FROM invoices
      WHERE cash_box_id = ? AND type = 'sale' AND currency = ? AND (is_return = 0 OR is_return IS NULL)
    ''', [cashBoxId, currency]);
    balance += MoneyHelper.readCalculatedMoney(salesPaid.first['total']);

    // 8. Purchase invoices (cash out) - paid_amount for this cash box in this currency
    final purchasePaid = await db.rawQuery('''
      SELECT COALESCE(SUM(paid_amount), 0) AS total FROM invoices
      WHERE cash_box_id = ? AND type = 'purchase' AND currency = ? AND (is_return = 0 OR is_return IS NULL)
    ''', [cashBoxId, currency]);
    balance -= MoneyHelper.readCalculatedMoney(purchasePaid.first['total']);

    // 9. Sales return (cash out)
    final salesReturnPaid = await db.rawQuery('''
      SELECT COALESCE(SUM(paid_amount), 0) AS total FROM invoices
      WHERE cash_box_id = ? AND type = 'sale' AND currency = ? AND is_return = 1
    ''', [cashBoxId, currency]);
    balance -= MoneyHelper.readCalculatedMoney(salesReturnPaid.first['total']);

    // 10. Purchase return (cash in)
    final purchaseReturnPaid = await db.rawQuery('''
      SELECT COALESCE(SUM(paid_amount), 0) AS total FROM invoices
      WHERE cash_box_id = ? AND type = 'purchase' AND currency = ? AND is_return = 1
    ''', [cashBoxId, currency]);
    balance +=
        MoneyHelper.readCalculatedMoney(purchaseReturnPaid.first['total']);

    // 11. Opening balance transactions for this cash box in this currency.
    //     First try to find by reference_id (new data), then fall back to
    //     searching by account code + reference_type (legacy data).
    double obBalance = 0.0;

    // 11a. Try reference_id first (for data created after the fix)
    {
      final obByRef = await db.rawQuery('''
        SELECT
          COALESCE(SUM(t.debit), 0) AS total_debit,
          COALESCE(SUM(t.credit), 0) AS total_credit
        FROM transactions t
        INNER JOIN accounts a ON t.account_id = a.id
        WHERE t.reference_type = 'opening_balance'
          AND t.reference_id = ?
          AND a.account_code LIKE '11%'
          AND a.currency = ?
      ''', ['cash_box_$cashBoxId', currency]);
      obBalance +=
          MoneyHelper.readCalculatedMoney(obByRef.first['total_debit']) -
              MoneyHelper.readCalculatedMoney(obByRef.first['total_credit']);
    }

    // 11b. Fallback: if no reference_id match, skip legacy fallback for per-cash-box
    //     balance computation. The old approach searched ALL opening_balance
    //     transactions on the 1100 account without filtering by cash_box_id,
    //     which incorrectly attributed other cash boxes' opening balances
    //     to this cash box. Only reference_id-based matching is reliable.

    balance += obBalance;

    return balance;
  }

  /// Get all financial movements for a specific cash box, optionally
  /// filtered by currency. Returns a list of movement maps suitable
  /// for display in a detail/ledger screen.
  /// Each data source is wrapped in try-catch so that a failure in one
  /// source (e.g. missing table/column) does not prevent the others from loading.
  Future<List<Map<String, dynamic>>> getCashBoxMovements(
    int cashBoxId, {
    String? currency,
  }) async {
    final db = await _db;
    final movements = <Map<String, dynamic>>[];

    // 1. Vouchers linked to this cash box
    try {
      final voucherFilter = currency != null ? 'AND v.currency = ?' : '';
      final voucherArgs =
          currency != null ? [cashBoxId, currency] : [cashBoxId];
      final vouchers = await db.rawQuery('''
        SELECT v.* FROM vouchers v
        WHERE v.cash_box_id = ? $voucherFilter
        ORDER BY v.date ASC, v.id ASC
      ''', voucherArgs);

      for (final v in vouchers) {
        final voucherType = v['voucher_type'] as String? ?? '';
        final totalAmount = MoneyHelper.readMoney(v['total_amount']);
        final curr = v['currency'] as String? ?? 'YER';
        final dateStr = v['date'] as String? ??
            v['created_at'] as String? ??
            DateTime.now().toIso8601String();

        String typeAr;
        IconData icon;
        Color color;
        double debit = 0.0;
        double credit = 0.0;
        String filterKey;

        switch (voucherType) {
          case 'receipt':
            typeAr = 'سند قبض';
            icon = Icons.assignment_turned_in;
            color = AppColors.success;
            credit = totalAmount;
            filterKey = 'receipt_voucher';
            break;
          case 'payment':
            typeAr = 'سند صرف';
            icon = Icons.assignment_return;
            color = AppColors.error;
            debit = totalAmount;
            filterKey = 'payment_voucher';
            break;
          case 'settlement':
            typeAr = 'قيد تسوية';
            icon = Icons.balance;
            color = AppColors.info;
            credit = totalAmount;
            filterKey = 'settlement';
            break;
          case 'compound':
            typeAr = 'قيد متعدد';
            icon = Icons.dynamic_feed;
            color = AppColors.accentBlue;
            debit = totalAmount;
            filterKey = 'compound_entry';
            break;
          default:
            typeAr = 'سند';
            icon = Icons.description;
            color = AppColors.textSecondary;
            debit = totalAmount;
            filterKey = 'all';
        }

        final description = v['description'] as String? ??
            '$typeAr - ${v['voucher_number'] ?? ''}';
        movements.add({
          'id': 'v_${v['id']}',
          'date': dateStr,
          'type': voucherType,
          'type_ar': typeAr,
          'filter_key': filterKey,
          'icon': icon,
          'color': color,
          'description': description,
          'debit': debit,
          'credit': credit,
          'currency': curr,
          'source': 'voucher',
          'voucher_type': voucherType,
          'created_at': v['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('CashBoxService.getCashBoxMovements [vouchers]: $e');
    }

    // 2. Cash transfers involving this cash box
    try {
      final transferFilter = currency != null ? 'AND ct.currency = ?' : '';
      final transferArgs = currency != null
          ? [cashBoxId, currency, cashBoxId, currency]
          : [cashBoxId, cashBoxId];
      final transfers = await db.rawQuery('''
        SELECT ct.*, from_cb.name AS from_cash_box_name, to_cb.name AS to_cash_box_name
        FROM cash_transfers ct
        LEFT JOIN cash_boxes from_cb ON ct.from_cash_box_id = from_cb.id
        LEFT JOIN cash_boxes to_cb ON ct.to_cash_box_id = to_cb.id
        WHERE (ct.from_cash_box_id = ? OR ct.to_cash_box_id = ?) $transferFilter
        ORDER BY ct.created_at ASC, ct.id ASC
      ''', transferArgs);

      for (final t in transfers) {
        final amount = MoneyHelper.readMoney(t['amount']);
        final curr = t['currency'] as String? ?? 'YER';
        final dateStr = t['date'] as String? ??
            t['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final isOutgoing = t['from_cash_box_id'] == cashBoxId;
        final fromName = t['from_cash_box_name'] as String? ?? '';
        final toName = t['to_cash_box_name'] as String? ?? '';

        movements.add({
          'id': 't_${t['id']}',
          'date': dateStr,
          'type': isOutgoing ? 'outgoing_transfer' : 'incoming_transfer',
          'type_ar': isOutgoing ? 'تحويل صادر' : 'تحويل وارد',
          'filter_key': isOutgoing ? 'outgoing_transfer' : 'incoming_transfer',
          'icon': isOutgoing ? Icons.outbox : Icons.inbox,
          'color': isOutgoing ? AppColors.warning : AppColors.accentBlue,
          'description':
              isOutgoing ? 'تحويل إلى $toName' : 'تحويل من $fromName',
          'debit': isOutgoing ? amount : 0.0,
          'credit': isOutgoing ? 0.0 : amount,
          'currency': curr,
          'source': 'transfer',
          'voucher_type': null,
          'created_at': t['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('CashBoxService.getCashBoxMovements [transfers]: $e');
    }

    // 3. Currency exchanges involving this cash box
    try {
      final exchangeFilter = currency != null
          ? 'AND (ce.from_currency = ? OR ce.to_currency = ?)'
          : '';
      final exchangeArgs = currency != null
          ? [cashBoxId, cashBoxId, currency, currency]
          : [cashBoxId, cashBoxId];
      final exchanges = await db.rawQuery('''
        SELECT ce.*, from_cb.name AS from_cash_box_name, to_cb.name AS to_cash_box_name
        FROM currency_exchanges ce
        LEFT JOIN cash_boxes from_cb ON ce.from_cash_box_id = from_cb.id
        LEFT JOIN cash_boxes to_cb ON ce.to_cash_box_id = to_cb.id
        WHERE (ce.from_cash_box_id = ? OR ce.to_cash_box_id = ?) $exchangeFilter
        ORDER BY ce.created_at ASC, ce.id ASC
      ''', exchangeArgs);

      for (final e in exchanges) {
        final fromAmount = MoneyHelper.readMoney(e['from_amount']);
        final toAmount = MoneyHelper.readMoney(e['to_amount']);
        final fromCurrency = e['from_currency'] as String? ?? 'YER';
        final toCurrency = e['to_currency'] as String? ?? 'YER';
        final dateStr = e['date'] as String? ??
            e['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final isSource = e['from_cash_box_id'] == cashBoxId;

        if (currency != null) {
          if (isSource && fromCurrency != currency) continue;
          if (!isSource && toCurrency != currency) continue;
        }

        final amount = isSource ? fromAmount : toAmount;
        final curr = isSource ? fromCurrency : toCurrency;
        movements.add({
          'id': 'e_${e['id']}',
          'date': dateStr,
          'type': isSource ? 'exchange_out' : 'exchange_in',
          'type_ar': isSource ? 'صرافة (صادر)' : 'صرافة (وارد)',
          'filter_key': 'exchange',
          'icon': Icons.currency_exchange,
          'color': AppColors.secondary,
          'description': 'صرافة: $fromCurrency → $toCurrency',
          'debit': isSource ? amount : 0.0,
          'credit': isSource ? 0.0 : amount,
          'currency': curr,
          'source': 'exchange',
          'voucher_type': null,
          'created_at': e['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('CashBoxService.getCashBoxMovements [exchanges]: $e');
    }

    // 4. Invoices linked to this cash box
    try {
      final invoiceFilter = currency != null ? 'AND i.currency = ?' : '';
      final invoiceArgs =
          currency != null ? [cashBoxId, currency] : [cashBoxId];
      final invoices = await db.rawQuery('''
        SELECT i.* FROM invoices i
        WHERE i.cash_box_id = ? $invoiceFilter
        ORDER BY i.created_at ASC, i.id ASC
      ''', invoiceArgs);

      for (final inv in invoices) {
        // FIX Bug 1: Use robust type detection that handles both stored types
        // (e.g. 'pos', 'sale', 'purchase') AND effective types
        // (e.g. 'sale_return', 'purchase_return').
        // Also handle is_return as num (not just int) to avoid type-cast failures.
        final rawType = inv['type'] as String? ?? 'sale';
        final rawIsReturn = inv['is_return'];
        final isReturn = (rawIsReturn is num
                ? rawIsReturn.toInt()
                : (rawIsReturn as int? ?? 0)) ==
            1;

        // Normalize: determine the base type and whether this is a return
        // 'sale_return' / 'purchase_return' are effective types that may be
        // stored directly in the type column by some code paths.
        String baseType;
        bool effectiveIsReturn;
        if (rawType == 'sale_return') {
          baseType = 'sale';
          effectiveIsReturn = true;
        } else if (rawType == 'purchase_return') {
          baseType = 'purchase';
          effectiveIsReturn = true;
        } else {
          baseType = rawType;
          effectiveIsReturn = isReturn;
        }

        final paidAmount = MoneyHelper.readMoney(inv['paid_amount']);
        final curr = inv['currency'] as String? ?? 'YER';
        final dateStr =
            inv['created_at'] as String? ?? DateTime.now().toIso8601String();

        String typeAr;
        String filterKey;
        double debit = 0.0;
        double credit = 0.0;
        final isSaleOrPos = baseType == 'sale' || baseType == 'pos';
        if (isSaleOrPos && !effectiveIsReturn) {
          typeAr = baseType == 'pos' ? 'فاتورة نقطة بيع' : 'فاتورة مبيعات';
          filterKey = 'sales';
          credit = paidAmount;
        } else if (isSaleOrPos && effectiveIsReturn) {
          typeAr = baseType == 'pos' ? 'مرتجع نقطة بيع' : 'مرتجع مبيعات';
          filterKey = 'returns';
          debit = paidAmount;
        } else if (baseType == 'purchase' && !effectiveIsReturn) {
          typeAr = 'فاتورة مشتريات';
          filterKey = 'purchases';
          debit = paidAmount;
        } else if (baseType == 'purchase' && effectiveIsReturn) {
          typeAr = 'مرتجع مشتريات';
          filterKey = 'returns';
          credit = paidAmount;
        } else {
          typeAr = 'فاتورة';
          filterKey = 'sales';
          credit = paidAmount;
        }

        movements.add({
          'id': 'i_${inv['id']}',
          'date': dateStr,
          'type': rawType,
          'type_ar': typeAr,
          'filter_key': filterKey,
          'icon': isSaleOrPos ? Icons.receipt_long : Icons.shopping_cart,
          'color': isSaleOrPos ? AppColors.primary : AppColors.secondary,
          'description':
              '$typeAr - ${inv['invoice_number'] ?? inv['id'] ?? ''}',
          'debit': debit,
          'credit': credit,
          'currency': curr,
          'source': 'invoice',
          'voucher_type': null,
          'created_at': inv['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('CashBoxService.getCashBoxMovements [invoices]: $e');
    }

    // 5. Opening balance transactions for this cash box
    try {
      final obMovements = await db.rawQuery('''
        SELECT t.*, a.currency AS account_currency
        FROM transactions t
        INNER JOIN accounts a ON t.account_id = a.id
        WHERE t.reference_type = 'opening_balance'
          AND t.reference_id = ?
          AND a.account_code LIKE '11%'
      ''', ['cash_box_$cashBoxId']);

      for (final ob in obMovements) {
        final obCurrency = ob['account_currency'] as String? ?? 'YER';
        if (currency != null && obCurrency != currency) continue;

        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ??
            ob['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';

        movements.add({
          'id': 'ob_${ob['id']}',
          'date': dateStr,
          'type': 'opening_balance',
          'type_ar': 'رصيد افتتاحي',
          'filter_key': 'opening_balance',
          'icon': Icons.account_balance_wallet,
          'color': AppColors.accentBlue,
          'description': description,
          'debit': credit > 0 ? credit : 0.0,
          'credit': debit > 0 ? debit : 0.0,
          'currency': obCurrency,
          'source': 'opening_balance',
          'voucher_type': null,
          'created_at': ob['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('CashBoxService.getCashBoxMovements [opening_balance]: $e');
    }

    // Sort by date+time ascending (oldest first).
    movements.sort((a, b) {
      final dateA = a['date'] as String;
      final dateB = b['date'] as String;
      final cmp = dateA.compareTo(dateB);
      if (cmp != 0) return cmp;
      return ((a['created_at'] as String?) ?? '')
          .compareTo((b['created_at'] as String?) ?? '');
    });

    return movements;
  }

  // ══════════════════════════════════════════════════════════════
  //  Optimized balance queries (7.4)
  // ══════════════════════════════════════════════════════════════

  /// **Fix (7.4):** Compute a single cash box's effective balance from ALL
  /// transaction sources in one unified query, instead of the previous approach
  /// which would require 11+ separate SQL queries (one per source table).
  ///
  /// Sources included in the single UNION ALL query:
  ///   1. Opening balance from cash_boxes.balance
  ///   2. Sale/PoS invoice payments received
  ///   3. Purchase invoice payments made
  ///   4. Receipt voucher amounts
  ///   5. Payment voucher amounts
  ///   6. Cash transfers IN (to this box)
  ///   7. Cash transfers OUT (from this box)
  ///   8. Currency exchange IN (to this box)
  ///   9. Currency exchange OUT (from this box)
  ///   10. Expenses paid from this box
  ///   11. Opening balance journal entries via linked account
  ///
  /// Returns a map with:
  ///   - 'effective_balance': double — the net balance considering all sources
  ///   - 'total_inflows': double — sum of all inflows
  ///   - 'total_outflows': double — sum of all outflows
  ///
  /// **Note:** Renamed from getCashBoxBalanceForCurrency to avoid duplicate
  /// definition with the older per-currency overload above.
  Future<Map<String, double>> getCashBoxBalanceSummary(int cashBoxId) async {
    final db = await _db;

    // Single UNION ALL query that computes inflows and outflows from all sources
    final result = await db.rawQuery('''
      SELECT
        CAST(COALESCE(SUM(CASE WHEN flow = 'in' THEN amount ELSE 0 END), 0) AS INTEGER) AS total_inflows,
        CAST(COALESCE(SUM(CASE WHEN flow = 'out' THEN amount ELSE 0 END), 0) AS INTEGER) AS total_outflows
      FROM (
        -- 1. Opening balance from cash_boxes table
        SELECT CASE
          WHEN balance_type = 'credit' THEN 'in'
          ELSE 'out'
        END AS flow,
        ABS(balance) AS amount
        FROM cash_boxes WHERE id = ? AND is_active = 1

        UNION ALL

        -- 2. Sale/PoS invoice payments received into this box
        SELECT 'in' AS flow, COALESCE(paid_amount, 0) AS amount
        FROM invoices
        WHERE cash_box_id = ? AND type IN ('sale', 'pos') AND is_return = 0 AND paid_amount > 0

        UNION ALL

        -- 3. Purchase returns payments received into this box
        SELECT 'in' AS flow, COALESCE(paid_amount, 0) AS amount
        FROM invoices
        WHERE cash_box_id = ? AND type = 'purchase' AND is_return = 1 AND paid_amount > 0

        UNION ALL

        -- 4. Purchase payments made from this box
        SELECT 'out' AS flow, COALESCE(paid_amount, 0) AS amount
        FROM invoices
        WHERE cash_box_id = ? AND type = 'purchase' AND is_return = 0 AND paid_amount > 0

        UNION ALL

        -- 5. Sale returns (refunds) paid from this box
        SELECT 'out' AS flow, COALESCE(paid_amount, 0) AS amount
        FROM invoices
        WHERE cash_box_id = ? AND type IN ('sale', 'pos') AND is_return = 1 AND paid_amount > 0

        UNION ALL

        -- 6. Receipt voucher amounts (money in)
        SELECT 'in' AS flow, COALESCE(total_amount, 0) AS amount
        FROM vouchers
        WHERE cash_box_id = ? AND voucher_type = 'receipt'

        UNION ALL

        -- 7. Payment voucher amounts (money out)
        SELECT 'out' AS flow, COALESCE(total_amount, 0) AS amount
        FROM vouchers
        WHERE cash_box_id = ? AND voucher_type = 'payment'

        UNION ALL

        -- 8. Cash transfers IN (to this box)
        SELECT 'in' AS flow, COALESCE(amount, 0) AS amount
        FROM cash_transfers
        WHERE to_cash_box_id = ?

        UNION ALL

        -- 9. Cash transfers OUT (from this box)
        SELECT 'out' AS flow, COALESCE(amount, 0) AS amount
        FROM cash_transfers
        WHERE from_cash_box_id = ?

        UNION ALL

        -- 10. Currency exchange IN (to this box)
        SELECT 'in' AS flow, COALESCE(to_amount, 0) AS amount
        FROM currency_exchanges
        WHERE to_cash_box_id = ?

        UNION ALL

        -- 11. Currency exchange OUT (from this box)
        SELECT 'out' AS flow, COALESCE(from_amount, 0) AS amount
        FROM currency_exchanges
        WHERE from_cash_box_id = ?

        UNION ALL

        -- 12. Expenses paid from this box
        SELECT 'out' AS flow, COALESCE(amount, 0) AS amount
        FROM expenses
        WHERE cash_box_id = ?
      )
    ''', [
      cashBoxId, // 1
      cashBoxId, // 2
      cashBoxId, // 3
      cashBoxId, // 4
      cashBoxId, // 5
      cashBoxId, // 6
      cashBoxId, // 7
      cashBoxId, // 8
      cashBoxId, // 9
      cashBoxId, // 10
      cashBoxId, // 11
      cashBoxId, // 12
    ]);

    final totalInflows =
        MoneyHelper.readCalculatedMoney(result.first['total_inflows']);
    final totalOutflows =
        MoneyHelper.readCalculatedMoney(result.first['total_outflows']);
    final effectiveBalance = totalInflows - totalOutflows;

    return {
      'effective_balance': effectiveBalance,
      'total_inflows': totalInflows,
      'total_outflows': totalOutflows,
    };
  }

  /// **Fix (7.4):** Get aggregated balance summary for ALL cash boxes in a
  /// single query, grouped by currency. This replaces calling
  /// [getCashBalanceForCurrency] multiple times (one per currency) or
  /// calling [getTotalCashBalance] + per-currency queries separately.
  ///
  /// Returns a list of maps, each with:
  ///   - 'currency': String — the currency code
  ///   - 'total_balance': double — net balance in that currency
  ///   - 'cash_box_count': int — number of active cash boxes in that currency
  Future<List<Map<String, dynamic>>> getAllCashBoxBalancesByCurrency() async {
    final db = await _db;
    final results = await db.rawQuery('''
      SELECT
        currency,
        CAST(COALESCE(SUM(CASE
          WHEN balance_type = 'credit' THEN balance
          ELSE -balance
        END), 0) AS INTEGER) AS total_balance,
        COUNT(*) AS cash_box_count
      FROM cash_boxes
      WHERE is_active = 1
      GROUP BY currency
      ORDER BY currency
    ''');

    return results
        .map((row) => {
              'currency': row['currency'] as String,
              'total_balance':
                  MoneyHelper.readCalculatedMoney(row['total_balance']),
              'cash_box_count': row['cash_box_count'] as int,
            })
        .toList();
  }

  // ══════════════════════════════════════════════════════════════
  //  Currency Exchange (صرافة العملات) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrencyExchange(Map<String, dynamic> exchangeMap) async {
    // Check if fiscal period is closed before currency exchange
    final exchangeDate =
        exchangeMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(exchangeDate);

    final db = await _db;
    final fromCurrency = (exchangeMap['from_currency'] as String?) ?? 'YER';
    final toCurrency = (exchangeMap['to_currency'] as String?) ?? 'YER';
    final fromAmount = MoneyHelper.readMoney(exchangeMap['from_amount']);
    final toAmount = MoneyHelper.readMoney(exchangeMap['to_amount']);
    final gainLoss = MoneyHelper.readMoney(exchangeMap['gain_loss']);
    final gainLossType = (exchangeMap['gain_loss_type'] as String?) ?? '';
    final fromCashBoxId =
        (exchangeMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (exchangeMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toIso8601String();

    late int exchangeId;
    await db.transaction((txn) async {
      // إدراج سجل الصرافة
      exchangeId = await txn.insert(
          'currency_exchanges',
          MoneyHelper.toCentsMap(
              exchangeMap, ['from_amount', 'to_amount', 'gain_loss']));

      // القيود المحاسبية
      final journalId = generateUniqueJournalId();

      // حساب الصناديق والبنوك للعملة المستلمة (مدين)
      final toCodeOffset =
          toCurrency == 'SAR' ? 1 : (toCurrency == 'USD' ? 2 : 0);
      final toCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + toCodeOffset).toString(), toCurrency],
        limit: 1,
      );
      final toCashBanksAccountId = toCashBanksAccount.isNotEmpty
          ? toCashBanksAccount.first['id'] as int
          : null;

      // حساب الصناديق والبنوك للعملة المرسلة (دائن)
      final fromCodeOffset =
          fromCurrency == 'SAR' ? 1 : (fromCurrency == 'USD' ? 2 : 0);
      final fromCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + fromCodeOffset).toString(), fromCurrency],
        limit: 1,
      );
      final fromCashBanksAccountId = fromCashBanksAccount.isNotEmpty
          ? fromCashBanksAccount.first['id'] as int
          : null;

      // Look up exchange rates for currency conversion
      final toRate = await _getExchangeRate(txn, toCurrency);
      final fromRate = await _getExchangeRate(txn, fromCurrency);

      // مدين: حساب الصناديق والبنوك للعملة المستلمة
      if (toCashBanksAccountId != null && toAmount > 0) {
        await txn.insert('transactions', {
          'account_id': toCashBanksAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(toAmount),
          'credit': 0,
          'description':
              'صرافة: استلام $toCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
          'currency_code': toCurrency,
          'exchange_rate': toCurrency == 'YER' ? 1.0 : toRate,
          'amount_base': (MoneyHelper.toCents(toAmount) * toRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, toCashBanksAccountId, toAmount, 0.0, now);
      }

      // دائن: حساب الصناديق والبنوك للعملة المرسلة
      if (fromCashBanksAccountId != null && fromAmount > 0) {
        await txn.insert('transactions', {
          'account_id': fromCashBanksAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(fromAmount),
          'description':
              'صرافة: صرف $fromCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
          'currency_code': fromCurrency,
          'exchange_rate': fromCurrency == 'YER' ? 1.0 : fromRate,
          'amount_base': (MoneyHelper.toCents(fromAmount) * fromRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, fromCashBanksAccountId, 0.0, fromAmount, now);
      }

      // ── C-04: معالجة أرباح/خسائر الصرافة باستخدام حساب فروقات الصرف ──
      // لا نستخدم حساب المبيعات (4100) أو المصاريف العامة (5100) لأنها ليست إيراد تشغيلي
      if (gainLoss > 0) {
        // Use separate gain/loss accounts: 4700 for gains (REVENUE), 5300 for losses (EXPENSE)
        final isGain = gainLossType == 'gain';
        final exchangeAccountId =
            await _dbHelper.journal.getOrCreateExchangeAccount(isGain: isGain);

        if (gainLossType == 'gain') {
          // أرباح صرافة: دائن حساب فروقات الصرف (إيراد)
          await txn.insert('transactions', {
            'account_id': exchangeAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(gainLoss),
            'description': 'أرباح صرافة - ${exchangeMap['exchange_number']}',
            'date': now,
            'created_at': now,
            'currency_code': 'YER',
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(gainLoss),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, exchangeAccountId, 0.0, gainLoss, now);
        } else if (gainLossType == 'loss') {
          // خسائر صرافة: مدين حساب فروقات الصرف (مصروف)
          await txn.insert('transactions', {
            'account_id': exchangeAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(gainLoss),
            'credit': 0,
            'description': 'خسائر صرافة - ${exchangeMap['exchange_number']}',
            'date': now,
            'created_at': now,
            'currency_code': 'YER',
            'exchange_rate': 1.0,
            'amount_base': MoneyHelper.toCents(gainLoss),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, exchangeAccountId, gainLoss, 0.0, now);
        }
      }

      // تحديث أرصدة الصناديق (مع مراعاة نوع الرصيد)
      final exFromBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      final exFromBalanceType = exFromBox.isNotEmpty
          ? (exFromBox.first['balance_type'] as String? ?? 'credit')
          : 'credit';
      if (exFromBalanceType == 'credit') {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(fromAmount), now, fromCashBoxId]);
      } else {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(fromAmount), now, fromCashBoxId]);
      }
      final exToBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      final exToBalanceType = exToBox.isNotEmpty
          ? (exToBox.first['balance_type'] as String? ?? 'credit')
          : 'credit';
      if (exToBalanceType == 'credit') {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(toAmount), now, toCashBoxId]);
      } else {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(toAmount), now, toCashBoxId]);
      }
    });

    return exchangeId;
  }

  /// جلب جميع عمليات الصرافة
  Future<List<Map<String, dynamic>>> getAllCurrencyExchanges(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT ce.*,
        from_cb.name AS from_cash_box_name,
        to_cb.name AS to_cash_box_name
      FROM currency_exchanges ce
      LEFT JOIN cash_boxes from_cb ON ce.from_cash_box_id = from_cb.id
      LEFT JOIN cash_boxes to_cb ON ce.to_cash_box_id = to_cb.id
      ORDER BY ce.$orderBy
    ''');
  }

  /// جلب الرقم التالي لعملية الصرافة
  Future<String> getNextExchangeNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'CE-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(exchange_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM currency_exchanges WHERE exchange_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Cash Transfer (تحويل بين الصناديق) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCashTransfer(Map<String, dynamic> transferMap) async {
    // Check if fiscal period is closed before cash transfer
    final transferDate =
        transferMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(transferDate);

    final db = await _db;
    final fromCashBoxId =
        (transferMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (transferMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final amount = MoneyHelper.readMoney(transferMap['amount']);
    final transferCurrency = (transferMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    late int transferId;
    await db.transaction((txn) async {
      // إدراج سجل التحويل
      transferId = await txn.insert(
          'cash_transfers', MoneyHelper.toCentsMap(transferMap, ['amount']));

      // القيود المحاسبية
      final journalId = generateUniqueJournalId();

      // الحصول على حساب الصندوق المصدر (المرتبط أو الافتراضي)
      int? fromAccountId;
      final fromCashBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      if (fromCashBox.isNotEmpty) {
        final linkedId = fromCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          fromAccountId = linkedId;
        }
      }
      if (fromAccountId == null) {
        final codeOffset =
            transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final fromCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        fromAccountId = fromCashBanksAccount.isNotEmpty
            ? fromCashBanksAccount.first['id'] as int
            : null;
      }

      // الحصول على حساب الصندوق الوجهة (المرتبط أو الافتراضي)
      int? toAccountId;
      final toCashBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      if (toCashBox.isNotEmpty) {
        final linkedId = toCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          toAccountId = linkedId;
        }
      }
      if (toAccountId == null) {
        final codeOffset =
            transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final toCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        toAccountId = toCashBanksAccount.isNotEmpty
            ? toCashBanksAccount.first['id'] as int
            : null;
      }

      // Look up exchange rate for transfer currency
      final transferRate = await _getExchangeRate(txn, transferCurrency);

      // مدين: حساب الصناديق والبنوك للوجهة
      if (toAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': toAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description':
              'تحويل: استلام من صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
          'currency_code': transferCurrency,
          'exchange_rate': transferCurrency == 'YER' ? 1.0 : transferRate,
          'amount_base': (MoneyHelper.toCents(amount) * transferRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, toAccountId, amount, 0.0, now);
      }

      // دائن: حساب الصناديق والبنوك للمصدر
      if (fromAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': fromAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description':
              'تحويل: صرف إلى صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
          'currency_code': transferCurrency,
          'exchange_rate': transferCurrency == 'YER' ? 1.0 : transferRate,
          'amount_base': (MoneyHelper.toCents(amount) * transferRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, fromAccountId, 0.0, amount, now);
      }

      // تحديث أرصدة الصناديق (مع مراعاة نوع الرصيد)
      final fromBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      final fromBalanceType = fromBox.isNotEmpty
          ? (fromBox.first['balance_type'] as String? ?? 'credit')
          : 'credit';
      if (fromBalanceType == 'credit') {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(amount), now, fromCashBoxId]);
      } else {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(amount), now, fromCashBoxId]);
      }
      final toBox = await txn.query('cash_boxes',
          where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      final toBalanceType = toBox.isNotEmpty
          ? (toBox.first['balance_type'] as String? ?? 'credit')
          : 'credit';
      if (toBalanceType == 'credit') {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(amount), now, toCashBoxId]);
      } else {
        await txn.rawUpdate(
            'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
            [MoneyHelper.toCents(amount), now, toCashBoxId]);
      }
    });

    return transferId;
  }

  /// جلب جميع عمليات التحويل بين الصناديق
  Future<List<Map<String, dynamic>>> getAllCashTransfers(
      {String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT ct.*,
        from_cb.name AS from_cash_box_name,
        to_cb.name AS to_cash_box_name
      FROM cash_transfers ct
      LEFT JOIN cash_boxes from_cb ON ct.from_cash_box_id = from_cb.id
      LEFT JOIN cash_boxes to_cb ON ct.to_cash_box_id = to_cb.id
      ORDER BY ct.$orderBy
    ''');
  }

  /// جلب الرقم التالي لعملية التحويل
  Future<String> getNextTransferNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'TR-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(transfer_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM cash_transfers WHERE transfer_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Voucher (السندات) CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// إدراج سند مع بنوده وإنشاء قيود يومية
  Future<int> insertVoucher(
      Map<String, dynamic> voucherMap, List<Map<String, dynamic>> items) async {
    // ── التحقق من توازن القيد: مجموع المدين يجب أن يساوي مجموع الدائن ──
    final totalDebit = items.fold(
        0.0, (sum, item) => sum + MoneyHelper.readMoney(item['debit']));
    final totalCredit = items.fold(
        0.0, (sum, item) => sum + MoneyHelper.readMoney(item['credit']));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception(
          'القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit');
    }

    // ── التحقق من قفل الفترة المحاسبية ──
    final voucherDate =
        voucherMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(voucherDate);

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    int voucherId = 0;
    await db.transaction((txn) async {
      // إدراج السند
      voucherId = await txn.insert('vouchers',
          MoneyHelper.toCentsMap(voucherMap, MoneyHelper.voucherMoneyFields));

      // Look up voucher currency exchange rate
      final voucherCurrency = (voucherMap['currency'] as String?) ?? 'YER';
      final voucherRate = await _getExchangeRate(txn, voucherCurrency);

      // إدراج بنود السند وإنشاء قيود يومية
      for (final item in items) {
        final itemMap = Map<String, dynamic>.from(item);
        itemMap['voucher_id'] = voucherId;
        itemMap['created_at'] = now;
        await txn.insert(
            'voucher_items',
            MoneyHelper.toCentsMap(
                itemMap, MoneyHelper.transactionMoneyFields));

        // إنشاء قيد يومي لكل بند
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = MoneyHelper.readMoney(item['debit']);
        final credit = MoneyHelper.readMoney(item['credit']);
        if (accountId != null && (debit > 0 || credit > 0)) {
          final itemAmount = debit > 0 ? debit : credit;
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(debit),
            'credit': MoneyHelper.toCents(credit),
            'description': item['description'] ??
                voucherMap['description'] ??
                'سند ${voucherMap['voucher_number']}',
            'date': voucherMap['date'],
            'created_at': now,
            'currency_code': voucherCurrency,
            'exchange_rate': voucherCurrency == 'YER' ? 1.0 : voucherRate,
            'amount_base':
                (MoneyHelper.toCents(itemAmount) * voucherRate).round(),
          });

          // تحديث رصيد الحساب باستخدام منطق balance_type
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, accountId, debit, credit, now);
        }
      }

      // تحديث رصيد الصندوق إذا كان مرتبطاً بالسند (مع مراعاة balance_type)
      final cashBoxId = voucherMap['cash_box_id'];
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance =
              MoneyHelper.readMoney(cashBox.first['balance']);
          final cashBoxBalanceType =
              cashBox.first['balance_type'] as String? ?? 'credit';
          final totalAmount = MoneyHelper.readMoney(voucherMap['total_amount']);
          final voucherType =
              voucherMap['voucher_type'] as String? ?? 'receipt';
          // قبض: النقدية تدخل الصندوق | صرف: النقدية تخرج
          final isCashIn = voucherType == 'receipt';
          double newCashBalance;
          if (cashBoxBalanceType == 'credit') {
            newCashBalance = isCashIn
                ? currentBalance + totalAmount
                : currentBalance - totalAmount;
          } else {
            newCashBalance = isCashIn
                ? currentBalance - totalAmount
                : currentBalance + totalAmount;
          }
          await txn.update(
              'cash_boxes',
              {
                'balance': MoneyHelper.toCents(newCashBalance),
                'updated_at': now
              },
              where: 'id = ?',
              whereArgs: [cashBoxId]);
        }
      }

      // تحديث رصيد العميل/المورد/الموظف إذا كان مرتبطاً بالسند
      final customerId = voucherMap['customer_id'];
      final supplierId = voucherMap['supplier_id'];
      final employeeId = voucherMap['employee_id'];
      final totalAmount = MoneyHelper.readMoney(voucherMap['total_amount']);
      final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';

      // ── Update customer/supplier/employee balance with balance_type-aware logic ──
      // Receipt from customer: reduces what they owe us (credit effect)
      // Payment to customer: increases what they owe us (debit effect)
      // Payment to supplier: reduces what we owe them (debit effect)
      // Receipt from supplier: increases what we owe them (credit effect)
      // Receipt from employee (سند قبض): credit effect (employee's credit increases)
      // Payment to employee (سند صرف): debit effect (employee's debit increases)
      if (customerId != null && totalAmount > 0) {
        if (voucherType == 'receipt') {
          await EntityBalanceHelper.customerReceipt(
            txn: txn,
            customerId: customerId as int,
            amount: totalAmount,
            now: now,
          );
        } else if (voucherType == 'payment') {
          await EntityBalanceHelper.customerPayment(
            txn: txn,
            customerId: customerId as int,
            amount: totalAmount,
            now: now,
          );
        }
      }

      if (supplierId != null && totalAmount > 0) {
        if (voucherType == 'payment') {
          await EntityBalanceHelper.supplierPayment(
            txn: txn,
            supplierId: supplierId as int,
            amount: totalAmount,
            now: now,
          );
        } else if (voucherType == 'receipt') {
          await EntityBalanceHelper.supplierReceipt(
            txn: txn,
            supplierId: supplierId as int,
            amount: totalAmount,
            now: now,
          );
        }
      }

      if (employeeId != null && totalAmount > 0) {
        if (voucherType == 'receipt') {
          // Receipt from employee: credit effect (employee's credit position increases)
          await EntityBalanceHelper.applyEmployeeBalanceChange(
            txn: txn,
            employeeId: employeeId as int,
            creditEffect: totalAmount,
            debitEffect: 0,
            now: now,
          );
        } else if (voucherType == 'payment') {
          // Payment to employee: debit effect (employee's debit position increases)
          await EntityBalanceHelper.applyEmployeeBalanceChange(
            txn: txn,
            employeeId: employeeId as int,
            creditEffect: 0,
            debitEffect: totalAmount,
            now: now,
          );
        }
      }
    });
    return voucherId;
  }

  /// جلب جميع السندات مع فلتر اختياري حسب النوع
  Future<List<Map<String, dynamic>>> getAllVouchers(
      {String? type, String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    if (type != null) {
      return await db.query('vouchers',
          where: 'voucher_type = ?', whereArgs: [type], orderBy: orderBy);
    }
    return await db.query('vouchers', orderBy: orderBy);
  }

  /// جلب بنود سند معين
  Future<List<Map<String, dynamic>>> getVoucherItems(int voucherId) async {
    final db = await _db;
    return await db.query('voucher_items',
        where: 'voucher_id = ?', whereArgs: [voucherId]);
  }

  /// حذف سند وعكس القيود اليومية
  Future<int> deleteVoucher(int voucherId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Pre-check: verify the voucher's date is not in a closed fiscal period
    final voucherPreCheck = await db.query('vouchers',
        where: 'id = ?', whereArgs: [voucherId], limit: 1);
    if (voucherPreCheck.isNotEmpty) {
      final preCheckDate = voucherPreCheck.first['date'] as String? ?? now;
      await _dbHelper.journal.checkFiscalPeriodOpen(preCheckDate);
    }

    await db.transaction((txn) async {
      // جلب بيانات السند
      final voucher = await txn.query('vouchers',
          where: 'id = ?', whereArgs: [voucherId], limit: 1);
      if (voucher.isEmpty) return;

      final voucherData = voucher.first;
      final voucherDate = voucherData['date'] as String? ?? now;
      final voucherNumber = voucherData['voucher_number'] as String? ?? '';
      final voucherType = voucherData['voucher_type'] as String? ?? '';
      final totalAmount = MoneyHelper.readMoney(voucherData['total_amount']);
      final cashBoxId = voucherData['cash_box_id'];

      // Look up voucher currency exchange rate for reversal
      final voucherCurrency = (voucherData['currency'] as String?) ?? 'YER';
      final voucherRate = await _getExchangeRate(txn, voucherCurrency);

      // جلب بنود السند وعكس القيود
      final items = await txn.query('voucher_items',
          where: 'voucher_id = ?', whereArgs: [voucherId]);
      for (final item in items) {
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = MoneyHelper.readMoney(item['debit']);
        final credit = MoneyHelper.readMoney(item['credit']);
        if (accountId != null && (debit > 0 || credit > 0)) {
          // عكس القيد:debit يصبح credit والعكس
          final reversalAmount = credit > 0 ? credit : debit;
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': generateUniqueJournalId(),
            'debit': MoneyHelper.toCents(credit),
            'credit': MoneyHelper.toCents(debit),
            'description': 'عكس سند $voucherNumber',
            'date': voucherDate,
            'created_at': now,
            'currency_code': voucherCurrency,
            'exchange_rate': voucherCurrency == 'YER' ? 1.0 : voucherRate,
            'amount_base':
                (MoneyHelper.toCents(reversalAmount) * voucherRate).round(),
          });

          // تحديث رصيد الحساب (عكس) باستخدام منطق balance_type
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, accountId, credit, debit, now);
        }
      }

      // عكس تأثير الصندوق (مع مراعاة balance_type)
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance =
              MoneyHelper.readMoney(cashBox.first['balance']);
          final cashBoxBalanceType =
              cashBox.first['balance_type'] as String? ?? 'credit';
          // عكس: قبض (كان أدخل) → نخرج | صرف (كان أخرج) → ندخل
          final isReverseCashOut = voucherType == 'receipt';
          double newCashBalance;
          if (cashBoxBalanceType == 'credit') {
            newCashBalance = isReverseCashOut
                ? currentBalance - totalAmount
                : currentBalance + totalAmount;
          } else {
            newCashBalance = isReverseCashOut
                ? currentBalance + totalAmount
                : currentBalance - totalAmount;
          }
          await txn.update(
              'cash_boxes',
              {
                'balance': MoneyHelper.toCents(newCashBalance),
                'updated_at': now
              },
              where: 'id = ?',
              whereArgs: [cashBoxId]);
        }
      }

      // ── Reverse customer/supplier balance with balance_type-aware logic ──
      // REVERSAL: opposite of original operation
      final voucherCustomerId = voucherData['customer_id'];
      final voucherSupplierId = voucherData['supplier_id'];
      if (voucherCustomerId != null && totalAmount > 0) {
        if (voucherType == 'receipt') {
          // Original receipt: credit effect → reversal is debit effect
          await EntityBalanceHelper.customerPayment(
            txn: txn,
            customerId: voucherCustomerId as int,
            amount: totalAmount,
            now: now,
          );
        } else if (voucherType == 'payment') {
          // Original payment: debit effect → reversal is credit effect
          await EntityBalanceHelper.customerReceipt(
            txn: txn,
            customerId: voucherCustomerId as int,
            amount: totalAmount,
            now: now,
          );
        }
      }
      if (voucherSupplierId != null && totalAmount > 0) {
        if (voucherType == 'payment') {
          // Original payment: debit effect → reversal is credit effect
          await EntityBalanceHelper.supplierPurchaseOnCredit(
            txn: txn,
            supplierId: voucherSupplierId as int,
            amount: totalAmount,
            now: now,
          );
        } else if (voucherType == 'receipt') {
          // Original receipt: debit effect → reversal is credit effect
          await EntityBalanceHelper.supplierPurchaseReturn(
            txn: txn,
            supplierId: voucherSupplierId as int,
            amount: totalAmount,
            now: now,
          );
        }
      }

      // حذف بنود السند ثم السند نفسه
      await txn.delete('voucher_items',
          where: 'voucher_id = ?', whereArgs: [voucherId]);
      await txn.delete('vouchers', where: 'id = ?', whereArgs: [voucherId]);
    });
    return 1;
  }

  /// جلب سند برقمه
  Future<Map<String, dynamic>?> getVoucherByNumber(String number) async {
    final db = await _db;
    final result = await db.query('vouchers',
        where: 'voucher_number = ?', whereArgs: [number], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  /// Record opening balance journal entry for a new cash box.
  ///
  /// Creates double-entry transactions and updates account balances:
  /// - For debit balance: Debit Cash & Banks, Credit Opening Balance Equity
  /// - For credit balance: Credit Cash & Banks, Debit Opening Balance Equity
  ///
  /// **Fix (7.3):** Wrapped in a database transaction to ensure atomicity.
  /// Uses [updateAccountBalanceWithJournal] instead of the standalone
  /// [updateAccountBalance] so all operations succeed or fail together.
  Future<void> recordCashBoxOpeningBalance({
    required int linkedAccountId,
    required int openingBalanceAccountId,
    required double openingBalance,
    required String balanceType,
    required String cashBoxName,
    int? cashBoxId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();
    final referenceId = cashBoxId != null ? 'cash_box_$cashBoxId' : null;

    // Cash & Banks (1100) is an ASSET account (debit nature).
    // From the user's perspective:
    //   له (credit) = the safe HAS money = cash in = Debit Cash & Banks (asset increase)
    //   عليه (debit) = the safe OWES money = cash out = Credit Cash & Banks (asset decrease)
    //
    // **Fix (7.3):** Wrapped in db.transaction with updateAccountBalanceWithJournal
    // for atomicity (eliminates race condition from read-then-write).
    await db.transaction((txn) async {
      // Look up the linked account's currency for currency_code / exchange_rate / amount_base
      final linkedAccountRow = await txn.query('accounts',
          where: 'id = ?', whereArgs: [linkedAccountId], limit: 1);
      final linkedAccountCurrency = linkedAccountRow.isNotEmpty
          ? (linkedAccountRow.first['currency'] as String? ?? 'YER')
          : 'YER';
      final linkedAccountRate =
          await _getExchangeRate(txn, linkedAccountCurrency);

      if (balanceType == 'credit') {
        // له — Safe has money: Debit Cash & Banks, Credit Opening Balance Equity
        await txn.insert('transactions', {
          'account_id': linkedAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(openingBalance),
          'credit': 0,
          'description': 'رصيد افتتاحي صندوق - $cashBoxName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': referenceId,
          'currency_code': linkedAccountCurrency,
          'exchange_rate':
              linkedAccountCurrency == 'YER' ? 1.0 : linkedAccountRate,
          'amount_base':
              (MoneyHelper.toCents(openingBalance) * linkedAccountRate).round(),
        });
        await txn.insert('transactions', {
          'account_id': openingBalanceAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(openingBalance),
          'description': 'رصيد افتتاحي صندوق - $cashBoxName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': referenceId,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(openingBalance),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          linkedAccountId,
          openingBalance,
          0.0,
          now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          openingBalanceAccountId,
          0.0,
          openingBalance,
          now,
        );
      } else {
        // عليه — Safe owes money: Credit Cash & Banks, Debit Opening Balance Equity
        await txn.insert('transactions', {
          'account_id': linkedAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(openingBalance),
          'description': 'رصيد افتتاحي صندوق - $cashBoxName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': referenceId,
          'currency_code': linkedAccountCurrency,
          'exchange_rate':
              linkedAccountCurrency == 'YER' ? 1.0 : linkedAccountRate,
          'amount_base':
              (MoneyHelper.toCents(openingBalance) * linkedAccountRate).round(),
        });
        await txn.insert('transactions', {
          'account_id': openingBalanceAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(openingBalance),
          'credit': 0,
          'description': 'رصيد افتتاحي صندوق - $cashBoxName',
          'date': now,
          'created_at': now,
          'reference_type': 'opening_balance',
          'reference_id': referenceId,
          'currency_code': 'YER',
          'exchange_rate': 1.0,
          'amount_base': MoneyHelper.toCents(openingBalance),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          linkedAccountId,
          0.0,
          openingBalance,
          now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          openingBalanceAccountId,
          openingBalance,
          0.0,
          now,
        );
      }
    });
  }

  /// Look up the exchange rate for a currency from the currencies table.
  /// Falls back to hardcoded rates for SAR/USD if the table is unavailable.
  Future<double> _getExchangeRate(
      DatabaseExecutor executor, String currency) async {
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
          'CashBoxService._getExchangeRate($currency) فشل، استخدام السعر الاحتياطي: $e');
    }
    // Fallback defaults
    if (currency == 'SAR') return 140.0;
    if (currency == 'USD') return 530.0;
    return 1.0;
  }

  /// توليد رقم السند التالي حسب النوع
  Future<String> getNextVoucherNumber(String type) async {
    final db = await _db;
    final year = DateTime.now().year.toString();
    final prefixMap = {
      'receipt': 'REC',
      'payment': 'PAY',
      'settlement': 'SET',
      'compound': 'CMP',
      'inventory': 'INV',
    };
    final prefix = prefixMap[type] ?? 'VCH';
    final fullPrefix = '$prefix-$year-';

    final result = await db.rawQuery(
      "SELECT voucher_number FROM vouchers WHERE voucher_number LIKE ? ORDER BY id DESC LIMIT 1",
      ['$fullPrefix%'],
    );

    if (result.isEmpty) {
      return '$fullPrefix${1.toString().padLeft(3, '0')}';
    }

    final lastNumber = result.first['voucher_number'] as String;
    final parts = lastNumber.split('-');
    if (parts.length >= 3) {
      final lastSeq = int.tryParse(parts.last) ?? 0;
      return '$fullPrefix${(lastSeq + 1).toString().padLeft(3, '0')}';
    }
    return '$fullPrefix${1.toString().padLeft(3, '0')}';
  }
}
