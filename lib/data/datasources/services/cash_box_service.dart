import 'package:sqflite_sqlcipher/sqflite.dart';

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
    return await db.insert('cash_boxes', MoneyHelper.toCentsMap(cashBoxMap, MoneyHelper.cashBoxMoneyFields));
  }

  Future<List<Map<String, dynamic>>> getAllCashBoxes() async {
    final db = await _db;
    return await db.query('cash_boxes', where: 'is_active = ?', whereArgs: [1], orderBy: 'type ASC, name ASC');
  }

  Future<List<Map<String, dynamic>>> getCashBoxesByType(String type) async {
    final db = await _db;
    return await db.query('cash_boxes', where: 'type = ? AND is_active = ?', whereArgs: [type, 1], orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getCashBoxById(int id) async {
    final db = await _db;
    final results = await db.query('cash_boxes', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCashBox(int id, Map<String, dynamic> cashBoxMap) async {
    final db = await _db;
    return await db.update('cash_boxes', MoneyHelper.toCentsMap(cashBoxMap, MoneyHelper.cashBoxMoneyFields), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCashBox(int id) async {
    final db = await _db;
    return await db.delete('cash_boxes', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalCashBalance() async {
    final db = await _db;
    final result = await db.rawQuery("SELECT CAST(COALESCE(SUM(CASE WHEN balance_type = 'credit' THEN balance ELSE -balance END), 0) AS INTEGER) AS total FROM cash_boxes WHERE is_active = 1");
    return MoneyHelper.readCalculatedMoney(result.first['total']);
  }

  /// جلب الصناديق حسب العملة
  /// Get cash boxes filtered by currency (via linked account currency).
  Future<List<Map<String, dynamic>>> getCashBoxesByCurrency(String currency) async {
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

  // ══════════════════════════════════════════════════════════════
  //  Currency Exchange (صرافة العملات) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrencyExchange(Map<String, dynamic> exchangeMap) async {
    // Check if fiscal period is closed before currency exchange
    final exchangeDate = exchangeMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(exchangeDate);

    final db = await _db;
    final fromCurrency = (exchangeMap['from_currency'] as String?) ?? 'YER';
    final toCurrency = (exchangeMap['to_currency'] as String?) ?? 'YER';
    final fromAmount = MoneyHelper.readMoney(exchangeMap['from_amount']);
    final toAmount = MoneyHelper.readMoney(exchangeMap['to_amount']);
    final gainLoss = MoneyHelper.readMoney(exchangeMap['gain_loss']);
    final gainLossType = (exchangeMap['gain_loss_type'] as String?) ?? '';
    final fromCashBoxId = (exchangeMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (exchangeMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toIso8601String();

    late int exchangeId;
    await db.transaction((txn) async {
      // إدراج سجل الصرافة
      exchangeId = await txn.insert('currency_exchanges', MoneyHelper.toCentsMap(exchangeMap, ['from_amount', 'to_amount', 'gain_loss']));

      // القيود المحاسبية
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // حساب الصناديق والبنوك للعملة المستلمة (مدين)
      final toCodeOffset = toCurrency == 'SAR' ? 1 : (toCurrency == 'USD' ? 2 : 0);
      final toCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + toCodeOffset).toString(), toCurrency],
        limit: 1,
      );
      final toCashBanksAccountId = toCashBanksAccount.isNotEmpty ? toCashBanksAccount.first['id'] as int : null;

      // حساب الصناديق والبنوك للعملة المرسلة (دائن)
      final fromCodeOffset = fromCurrency == 'SAR' ? 1 : (fromCurrency == 'USD' ? 2 : 0);
      final fromCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + fromCodeOffset).toString(), fromCurrency],
        limit: 1,
      );
      final fromCashBanksAccountId = fromCashBanksAccount.isNotEmpty ? fromCashBanksAccount.first['id'] as int : null;

      // مدين: حساب الصناديق والبنوك للعملة المستلمة
      if (toCashBanksAccountId != null && toAmount > 0) {
        await txn.insert('transactions', {
          'account_id': toCashBanksAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(toAmount),
          'credit': 0,
          'description': 'صرافة: استلام $toCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, toCashBanksAccountId, toAmount, 0.0, now);
      }

      // دائن: حساب الصناديق والبنوك للعملة المرسلة
      if (fromCashBanksAccountId != null && fromAmount > 0) {
        await txn.insert('transactions', {
          'account_id': fromCashBanksAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(fromAmount),
          'description': 'صرافة: صرف $fromCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, fromCashBanksAccountId, 0.0, fromAmount, now);
      }

      // ── C-04: معالجة أرباح/خسائر الصرافة باستخدام حساب فروقات الصرف (5300) ──
      // لا نستخدم حساب المبيعات (4100) أو المصاريف العامة (5100) لأنها ليست إيراد تشغيلي
      if (gainLoss > 0) {
        // استخدام حساب فروقات الصرف من journal_service (5300)
        final exchangeAccountId = await _dbHelper.journal.getOrCreateExchangeAccount();

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
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, exchangeAccountId, 0.0, gainLoss, now);
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
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, exchangeAccountId, gainLoss, 0.0, now);
        }
      }

      // تحديث أرصدة الصناديق (مع مراعاة نوع الرصيد)
      final exFromBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      final exFromBalanceType = exFromBox.isNotEmpty ? (exFromBox.first['balance_type'] as String? ?? 'credit') : 'credit';
      if (exFromBalanceType == 'credit') {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(fromAmount), now, fromCashBoxId]);
      } else {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(fromAmount), now, fromCashBoxId]);
      }
      final exToBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      final exToBalanceType = exToBox.isNotEmpty ? (exToBox.first['balance_type'] as String? ?? 'credit') : 'credit';
      if (exToBalanceType == 'credit') {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(toAmount), now, toCashBoxId]);
      } else {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(toAmount), now, toCashBoxId]);
      }
    });

    return exchangeId;
  }

  /// جلب جميع عمليات الصرافة
  Future<List<Map<String, dynamic>>> getAllCurrencyExchanges({String orderBy = 'created_at DESC'}) async {
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
    final transferDate = transferMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(transferDate);

    final db = await _db;
    final fromCashBoxId = (transferMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (transferMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final amount = MoneyHelper.readMoney(transferMap['amount']);
    final transferCurrency = (transferMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    late int transferId;
    await db.transaction((txn) async {
      // إدراج سجل التحويل
      transferId = await txn.insert('cash_transfers', MoneyHelper.toCentsMap(transferMap, ['amount']));

      // القيود المحاسبية
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // الحصول على حساب الصندوق المصدر (المرتبط أو الافتراضي)
      int? fromAccountId;
      final fromCashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      if (fromCashBox.isNotEmpty) {
        final linkedId = fromCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          fromAccountId = linkedId;
        }
      }
      if (fromAccountId == null) {
        final codeOffset = transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final fromCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        fromAccountId = fromCashBanksAccount.isNotEmpty ? fromCashBanksAccount.first['id'] as int : null;
      }

      // الحصول على حساب الصندوق الوجهة (المرتبط أو الافتراضي)
      int? toAccountId;
      final toCashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      if (toCashBox.isNotEmpty) {
        final linkedId = toCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          toAccountId = linkedId;
        }
      }
      if (toAccountId == null) {
        final codeOffset = transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final toCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        toAccountId = toCashBanksAccount.isNotEmpty ? toCashBanksAccount.first['id'] as int : null;
      }

      // مدين: حساب الصناديق والبنوك للوجهة
      if (toAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': toAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(amount),
          'credit': 0,
          'description': 'تحويل: استلام من صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, toAccountId, amount, 0.0, now);
      }

      // دائن: حساب الصناديق والبنوك للمصدر
      if (fromAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': fromAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(amount),
          'description': 'تحويل: صرف إلى صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(txn, fromAccountId, 0.0, amount, now);
      }

      // تحديث أرصدة الصناديق (مع مراعاة نوع الرصيد)
      final fromBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      final fromBalanceType = fromBox.isNotEmpty ? (fromBox.first['balance_type'] as String? ?? 'credit') : 'credit';
      if (fromBalanceType == 'credit') {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amount), now, fromCashBoxId]);
      } else {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amount), now, fromCashBoxId]);
      }
      final toBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      final toBalanceType = toBox.isNotEmpty ? (toBox.first['balance_type'] as String? ?? 'credit') : 'credit';
      if (toBalanceType == 'credit') {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amount), now, toCashBoxId]);
      } else {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(amount), now, toCashBoxId]);
      }
    });

    return transferId;
  }

  /// جلب جميع عمليات التحويل بين الصناديق
  Future<List<Map<String, dynamic>>> getAllCashTransfers({String orderBy = 'created_at DESC'}) async {
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
  Future<int> insertVoucher(Map<String, dynamic> voucherMap, List<Map<String, dynamic>> items) async {
    // ── التحقق من توازن القيد: مجموع المدين يجب أن يساوي مجموع الدائن ──
    final totalDebit = items.fold(0.0, (sum, item) => sum + MoneyHelper.readMoney(item['debit']));
    final totalCredit = items.fold(0.0, (sum, item) => sum + MoneyHelper.readMoney(item['credit']));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception('القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit');
    }

    // ── التحقق من قفل الفترة المحاسبية ──
    final voucherDate = voucherMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(voucherDate);

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    int voucherId = 0;
    await db.transaction((txn) async {
      // إدراج السند
      voucherId = await txn.insert('vouchers', MoneyHelper.toCentsMap(voucherMap, MoneyHelper.voucherMoneyFields));

      // إدراج بنود السند وإنشاء قيود يومية
      for (final item in items) {
        final itemMap = Map<String, dynamic>.from(item);
        itemMap['voucher_id'] = voucherId;
        itemMap['created_at'] = now;
        await txn.insert('voucher_items', MoneyHelper.toCentsMap(itemMap, MoneyHelper.transactionMoneyFields));

        // إنشاء قيد يومي لكل بند
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = MoneyHelper.readMoney(item['debit']);
        final credit = MoneyHelper.readMoney(item['credit']);
        if (accountId != null && (debit > 0 || credit > 0)) {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(debit),
            'credit': MoneyHelper.toCents(credit),
            'description': item['description'] ?? voucherMap['description'] ?? 'سند ${voucherMap['voucher_number']}',
            'date': voucherMap['date'],
            'created_at': now,
          });

          // تحديث رصيد الحساب باستخدام منطق balance_type
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, debit, credit, now);
        }
      }

      // تحديث رصيد الصندوق إذا كان مرتبطاً بالسند
      final cashBoxId = voucherMap['cash_box_id'];
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = MoneyHelper.readMoney(cashBox.first['balance']);
          final totalAmount = MoneyHelper.readMoney(voucherMap['total_amount']);
          final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';
          double newCashBalance;
          if (voucherType == 'receipt') {
            newCashBalance = currentBalance + totalAmount;
          } else if (voucherType == 'payment') {
            newCashBalance = currentBalance - totalAmount;
          } else {
            newCashBalance = currentBalance;
          }
          await txn.update('cash_boxes', {'balance': MoneyHelper.toCents(newCashBalance), 'updated_at': now}, where: 'id = ?', whereArgs: [cashBoxId]);
        }
      }

      // تحديث رصيد العميل/المورد إذا كان مرتبطاً بالسند
      final customerId = voucherMap['customer_id'];
      final supplierId = voucherMap['supplier_id'];
      final totalAmount = MoneyHelper.readMoney(voucherMap['total_amount']);
      final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';

      // ── M-07: تحديث رصيد العميل/المورد حسب الطريقة المعتمدة عالمياً ──
      // سند قبض من عميل = العميل يدفع → رصيده ينقص (ذمته تقل)
      // سند صرف لعميل = نعيد للعميل أموال → رصيده ينقص (ذمته تقل)
      // سند صرف لمورد = ندفع للمورد → رصيده ينقص (ما علينا يقل)
      // سند قبض من مورد = المورد يعيد لنا أموال → رصيده ينقص (ما علينا يقل)
      if (customerId != null && totalAmount > 0) {
        // في كلتا الحالتين (قبض أو صرف) رصيد العميل ينقص:
        // قبض: العميل سدد دينه → ينقص
        // صرف: أعدنا أموال للعميل → ذمته تقل → ينقص
        await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(totalAmount), now, customerId]);
      }

      if (supplierId != null && totalAmount > 0) {
        // في كلتا الحالتين (قبض أو صرف) رصيد المورد ينقص:
        // صرف: سددنا ديننا للمورد → ينقص
        // قبض: المورد أعاد لنا أموال → ما علينا يقل → ينقص
        await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(totalAmount), now, supplierId]);
      }
    });
    return voucherId;
  }

  /// جلب جميع السندات مع فلتر اختياري حسب النوع
  Future<List<Map<String, dynamic>>> getAllVouchers({String? type, String orderBy = 'created_at DESC'}) async {
    final db = await _db;
    if (type != null) {
      return await db.query('vouchers', where: 'voucher_type = ?', whereArgs: [type], orderBy: orderBy);
    }
    return await db.query('vouchers', orderBy: orderBy);
  }

  /// جلب بنود سند معين
  Future<List<Map<String, dynamic>>> getVoucherItems(int voucherId) async {
    final db = await _db;
    return await db.query('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
  }

  /// حذف سند وعكس القيود اليومية
  Future<int> deleteVoucher(int voucherId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Pre-check: verify the voucher's date is not in a closed fiscal period
    final voucherPreCheck = await db.query('vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
    if (voucherPreCheck.isNotEmpty) {
      final preCheckDate = voucherPreCheck.first['date'] as String? ?? now;
      await _dbHelper.journal.checkFiscalPeriodOpen(preCheckDate);
    }

    await db.transaction((txn) async {
      // جلب بيانات السند
      final voucher = await txn.query('vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
      if (voucher.isEmpty) return;

      final voucherData = voucher.first;
      final voucherDate = voucherData['date'] as String? ?? now;
      final voucherNumber = voucherData['voucher_number'] as String? ?? '';
      final voucherType = voucherData['voucher_type'] as String? ?? '';
      final totalAmount = MoneyHelper.readMoney(voucherData['total_amount']);
      final cashBoxId = voucherData['cash_box_id'];

      // جلب بنود السند وعكس القيود
      final items = await txn.query('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
      for (final item in items) {
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = MoneyHelper.readMoney(item['debit']);
        final credit = MoneyHelper.readMoney(item['credit']);
        if (accountId != null && (debit > 0 || credit > 0)) {
          // عكس القيد:debit يصبح credit والعكس
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': DateTime.now().millisecondsSinceEpoch,
            'debit': MoneyHelper.toCents(credit),
            'credit': MoneyHelper.toCents(debit),
            'description': 'عكس سند $voucherNumber',
            'date': voucherDate,
            'created_at': now,
          });

          // تحديث رصيد الحساب (عكس) باستخدام منطق balance_type
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accountId, credit, debit, now);
        }
      }

      // عكس تأثير الصندوق
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = MoneyHelper.readMoney(cashBox.first['balance']);
          double newCashBalance;
          if (voucherType == 'receipt') {
            newCashBalance = currentBalance - totalAmount;
          } else if (voucherType == 'payment') {
            newCashBalance = currentBalance + totalAmount;
          } else {
            newCashBalance = currentBalance;
          }
          await txn.update('cash_boxes', {'balance': MoneyHelper.toCents(newCashBalance), 'updated_at': now}, where: 'id = ?', whereArgs: [cashBoxId]);
        }
      }

      // ── M-07: عكس تأثير رصيد العميل/المورد (عكس العملية الأصلية) ──
      // العكس: حيث أن العملية الأصلية كانت تنقص الرصيد، فالعكس يزيد الرصيد
      final customerId = voucherData['customer_id'];
      final supplierId = voucherData['supplier_id'];
      if (customerId != null && totalAmount > 0) {
        // عكس العملية الأصلية: كان ينقص → الآن يزيد
        await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(totalAmount), now, customerId]);
      }
      if (supplierId != null && totalAmount > 0) {
        // عكس العملية الأصلية: كان ينقص → الآن يزيد
        await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [MoneyHelper.toCents(totalAmount), now, supplierId]);
      }

      // حذف بنود السند ثم السند نفسه
      await txn.delete('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
      await txn.delete('vouchers', where: 'id = ?', whereArgs: [voucherId]);
    });
    return 1;
  }

  /// جلب سند برقمه
  Future<Map<String, dynamic>?> getVoucherByNumber(String number) async {
    final db = await _db;
    final result = await db.query('vouchers', where: 'voucher_number = ?', whereArgs: [number], limit: 1);
    return result.isNotEmpty ? result.first : null;
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
