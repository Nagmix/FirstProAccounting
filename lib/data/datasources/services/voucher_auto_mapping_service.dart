import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/utils/entity_balance_helper.dart';
import '../../../core/utils/journal_id_helper.dart';
import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

/// خدمة التحويل التلقائي من الكيانات (عملاء/موردين/موظفين/مصروفات)
/// إلى حسابات شجرة المحاسبة وإنشاء القيود المحاسبية تلقائياً
///
/// وفق المعايير المحاسبية الدولية (IAS 1, IAS 21):
/// - سند القبض: مدين = الصندوق/البنك، دائن = حساب الكيان
/// - سند الصرف: مدين = حساب الكيان، دائن = الصندوق/البنك
/// - القيد العام: مدين = حساب "إلى"، دائن = حساب "من"
class VoucherAutoMappingService {
  final DatabaseHelper _dbHelper;
  VoucherAutoMappingService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// أنواع الكيانات المدعومة
  static const String entityCustomer = 'customer';
  static const String entitySupplier = 'supplier';
  static const String entityEmployee = 'employee';
  static const String entityExpense = 'expense';
  static const String entityOther = 'other';

  /// خريطة أنواع الكيانات بالعربية
  static const Map<String, String> entityTypeLabelsAr = {
    entityCustomer: 'عميل',
    entitySupplier: 'مورد',
    entityEmployee: 'موظف',
    entityExpense: 'مصروف',
    entityOther: 'أخرى',
  };

  /// أيقونات أنواع الكيانات
  static const Map<String, int> entityTypeIcons = {
    entityCustomer: 0xe85d, // Icons.person
    entitySupplier: 0xe8d5, // Icons.local_shipping
    entityEmployee: 0xe7fd, // Icons.badge
    entityExpense: 0xe870, // Icons.receipt_long
    entityOther: 0xe88e, // Icons.more_horiz
  };

  // ══════════════════════════════════════════════════════════════
  //  جلب الكيانات حسب النوع
  // ══════════════════════════════════════════════════════════════

  /// جلب جميع الكيانات النشطة من جميع الأنواع
  /// كل جدول يتم جلبه بشكل مستقل مع معالجة الأخطاء
  /// بحيث لا يفشل التحميل بالكامل إذا لم يكن جدول موجوداً
  Future<List<Map<String, dynamic>>> getAllEntities() async {
    final db = await _db;
    final entities = <Map<String, dynamic>>[];

    // العملاء (لا يوجد عمود is_active في جدول العملاء)
    try {
      final customers = await db.query('customers',
          orderBy: 'name ASC');
      for (final c in customers) {
        entities.add({
          'id': c['id'],
          'name': c['name'] ?? '',
          'type': entityCustomer,
          'currency': c['currency'] ?? 'YER',
          'balance': MoneyHelper.readMoney(c['balance']),
          'balance_type': c['balance_type'] ?? 'debit',
          'account_id': c['account_id'],
        });
      }
    } catch (_) {
      // جدول العملاء غير موجود أو هيكل مختلف
    }

    // الموردين (لا يوجد عمود is_active في جدول الموردين)
    try {
      final suppliers = await db.query('suppliers',
          orderBy: 'name ASC');
      for (final s in suppliers) {
        entities.add({
          'id': s['id'],
          'name': s['name'] ?? '',
          'type': entitySupplier,
          'currency': s['currency'] ?? 'YER',
          'balance': MoneyHelper.readMoney(s['balance']),
          'balance_type': s['balance_type'] ?? 'credit',
          'account_id': s['account_id'],
        });
      }
    } catch (_) {
      // جدول الموردين غير موجود أو هيكل مختلف
    }

    // الموظفين
    try {
      final employees = await db.query('employees',
          where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
      for (final e in employees) {
        entities.add({
          'id': e['id'],
          'name': e['name'] ?? '',
          'type': entityEmployee,
          'currency': e['currency'] ?? 'YER',
          'balance': MoneyHelper.readMoney(e['balance']),
          'balance_type': e['balance_type'] ?? 'credit',
          'account_id': e['account_id'],
        });
      }
    } catch (_) {
      // جدول الموظفين غير موجود أو هيكل مختلف
    }

    // حسابات المصروفات الفرعية
    try {
      final expenseSubAccounts = await db.query('expense_sub_accounts',
          where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
      for (final e in expenseSubAccounts) {
        entities.add({
          'id': e['id'],
          'name': e['name'] ?? '',
          'type': entityExpense,
          'currency': '',
          'balance': 0.0,
          'balance_type': 'debit',
          'account_id': null,
        });
      }
    } catch (_) {
      // جدول المصروفات الفرعية غير موجود أو هيكل مختلف
    }

    return entities;
  }

  /// جلب الكيانات حسب النوع
  Future<List<Map<String, dynamic>>> getEntitiesByType(String type) async {
    final db = await _db;
    final entities = <Map<String, dynamic>>[];

    try {
      switch (type) {
        case entityCustomer:
          final rows = await db.query('customers',
              orderBy: 'name ASC');
          for (final c in rows) {
            entities.add({
              'id': c['id'],
              'name': c['name'] ?? '',
              'type': entityCustomer,
              'currency': c['currency'] ?? 'YER',
              'balance': MoneyHelper.readMoney(c['balance']),
              'balance_type': c['balance_type'] ?? 'debit',
              'account_id': c['account_id'],
            });
          }
          break;

        case entitySupplier:
          final rows = await db.query('suppliers',
              orderBy: 'name ASC');
          for (final s in rows) {
            entities.add({
              'id': s['id'],
              'name': s['name'] ?? '',
              'type': entitySupplier,
              'currency': s['currency'] ?? 'YER',
              'balance': MoneyHelper.readMoney(s['balance']),
              'balance_type': s['balance_type'] ?? 'credit',
              'account_id': s['account_id'],
            });
          }
          break;

        case entityEmployee:
          final rows = await db.query('employees',
              where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
          for (final e in rows) {
            entities.add({
              'id': e['id'],
              'name': e['name'] ?? '',
              'type': entityEmployee,
              'currency': e['currency'] ?? 'YER',
              'balance': MoneyHelper.readMoney(e['balance']),
              'balance_type': e['balance_type'] ?? 'credit',
              'account_id': e['account_id'],
            });
          }
          break;

        case entityExpense:
          final rows = await db.query('expense_sub_accounts',
              where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
          for (final e in rows) {
            entities.add({
              'id': e['id'],
              'name': e['name'] ?? '',
              'type': entityExpense,
              'currency': '',
              'balance': 0.0,
              'balance_type': 'debit',
              'account_id': null,
            });
          }
          break;
      }
    } catch (_) {
      // الجدول غير موجود أو هيكل مختلف
    }

    return entities;
  }

  // ══════════════════════════════════════════════════════════════
  //  تحويل الكيان إلى حساب في شجرة المحاسبة
  // ══════════════════════════════════════════════════════════════

  /// حساب إزاحة كود الحساب حسب العملة
  /// YER = 0, SAR = 1, USD = 2
  int _getCodeOffset(String currency) {
    switch (currency) {
      case 'SAR':
        return 1;
      case 'USD':
        return 2;
      default:
        return 0;
    }
  }

  /// الكود الأساسي لكل نوع كيان في شجرة المحاسبة
  int _getBaseAccountCode(String entityType) {
    switch (entityType) {
      case entityCustomer:
        return 1200; // العملاء (أصول)
      case entitySupplier:
        return 2100; // الموردين (خصوم)
      case entityEmployee:
        return 5100; // الموظفين (مصروفات)
      case entityExpense:
        return 5000; // المصروفات
      default:
        return 5000;
    }
  }

  /// البحث عن حساب في شجرة المحاسبة بناءً على نوع الكيان والعملة
  Future<int?> _resolveEntityAccountId(
    String entityType,
    String currency, {
    int? entityAccountId,
    Transaction? txn,
  }) async {
    // إذا كان الكيان لديه account_id محدد، نستخدمه
    if (entityAccountId != null) {
      return entityAccountId;
    }

    // وإلا نبحث بالكود والعملة
    final baseCode = _getBaseAccountCode(entityType);
    final offset = _getCodeOffset(currency);
    final accountCode = (baseCode + offset).toString();

    List<Map<String, dynamic>> results;
    if (txn != null) {
      results = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ? AND is_active = 1',
        whereArgs: [accountCode, currency],
        limit: 1,
      );
    } else {
      final db = await _db;
      results = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ? AND is_active = 1',
        whereArgs: [accountCode, currency],
        limit: 1,
      );
    }

    if (results.isNotEmpty) {
      return results.first['id'] as int;
    }
    return null;
  }

  /// البحث عن حساب الصندوق/البنك
  Future<int?> _resolveCashAccountId(
    int? cashBoxId,
    String currency, {
    Transaction? txn,
  }) async {
    // إذا كان هناك صندوق محدد، نأخذ حسابه المرتبط
    if (cashBoxId != null) {
      List<Map<String, dynamic>> cashBoxRows;
      if (txn != null) {
        cashBoxRows = await txn.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
      } else {
        final db = await _db;
        cashBoxRows = await db.query('cash_boxes',
            where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
      }
      if (cashBoxRows.isNotEmpty) {
        final linkedAccountId = cashBoxRows.first['linked_account_id'] as int?;
        if (linkedAccountId != null) return linkedAccountId;
      }
    }

    // افتراضي: كود 1100 + offset
    final offset = _getCodeOffset(currency);
    final accountCode = (1100 + offset).toString();

    List<Map<String, dynamic>> results;
    if (txn != null) {
      results = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ? AND is_active = 1',
        whereArgs: [accountCode, currency],
        limit: 1,
      );
    } else {
      final db = await _db;
      results = await db.query(
        'accounts',
        where: 'account_code = ? AND currency = ? AND is_active = 1',
        whereArgs: [accountCode, currency],
        limit: 1,
      );
    }

    if (results.isNotEmpty) {
      return results.first['id'] as int;
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  //  إنشاء سندات القبض والصرف تلقائياً
  // ══════════════════════════════════════════════════════════════

  /// إنشاء سند قبض أو صرف مع القيد المحاسبي التلقائي
  ///
  /// [voucherType] 'receipt' أو 'payment'
  /// [entityType] نوع الكيان (عميل/مورد/موظف/مصروف)
  /// [entityId] معرف الكيان
  /// [entityAccountId] معرف حساب الكيان في شجرة المحاسبة (اختياري)
  /// [cashBoxId] معرف الصندوق
  /// [amount] المبلغ
  /// [currency] العملة
  /// [date] التاريخ
  /// [description] البيان
  ///
  /// القيد المحاسبي:
  /// سند قبض: مدين = الصندوق، دائن = حساب الكيان
  /// سند صرف: مدين = حساب الكيان، دائن = الصندوق
  Future<int> createReceiptPaymentVoucher({
    required String voucherType,
    required String entityType,
    required int entityId,
    int? entityAccountId,
    int? cashBoxId,
    required double amount,
    required String currency,
    required String date,
    String? description,
  }) async {
    // التحقق من قفل الفترة المحاسبية
    await _dbHelper.journal.checkFiscalPeriodOpen(date);

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    // تحديد حسابات القيد
    final entityAccount = await _resolveEntityAccountId(
      entityType, currency,
      entityAccountId: entityAccountId,
    );
    final cashAccount = await _resolveCashAccountId(cashBoxId, currency);

    if (entityAccount == null) {
      throw Exception('لم يتم العثور على حساب $entityType بالعملة $currency في شجرة الحسابات');
    }
    if (cashAccount == null) {
      throw Exception('لم يتم العثور على حساب الصندوق بالعملة $currency في شجرة الحسابات');
    }

    // توليد رقم السند
    final voucherNumber =
        await _dbHelper.cashBoxes.getNextVoucherNumber(voucherType);

    // تحديد اسم الكيان للبيان
    final entityName = await _getEntityName(entityType, entityId);

    // تحديد مدين ودائن حسب نوع السند
    // سند قبض: مدين = الصندوق (النقد يدخل)، دائن = حساب الكيان (مصدر النقد)
    // سند صرف: مدين = حساب الكيان (وجهة النقد)، دائن = الصندوق (النقد يخرج)
    final int debitAccountId;
    final int creditAccountId;

    if (voucherType == 'receipt') {
      debitAccountId = cashAccount;
      creditAccountId = entityAccount;
    } else {
      debitAccountId = entityAccount;
      creditAccountId = cashAccount;
    }

    final autoDescription = description?.trim().isNotEmpty == true
        ? description!
        : '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - $entityName';

    late int voucherId;
    await db.transaction((txn) async {
      // إدراج السند
      voucherId = await txn.insert(
        'vouchers',
        MoneyHelper.toCentsMap({
          'voucher_number': voucherNumber,
          'voucher_type': voucherType,
          'date': date,
          'description': autoDescription,
          'currency': currency,
          'total_amount': amount,
          'cash_box_id': cashBoxId,
          'customer_id': entityType == entityCustomer ? entityId : null,
          'supplier_id': entityType == entitySupplier ? entityId : null,
          'employee_id': entityType == entityEmployee ? entityId : null,
          'is_posted': 1,
          'created_at': now,
          'updated_at': now,
        }, MoneyHelper.voucherMoneyFields),
      );

      // إدراج بنود السند (مدين)
      await txn.insert(
        'voucher_items',
        MoneyHelper.toCentsMap({
          'voucher_id': voucherId,
          'account_id': debitAccountId,
          'debit': amount,
          'credit': 0.0,
          'description': autoDescription,
          'created_at': now,
        }, MoneyHelper.transactionMoneyFields),
      );

      // إدراج بنود السند (دائن)
      await txn.insert(
        'voucher_items',
        MoneyHelper.toCentsMap({
          'voucher_id': voucherId,
          'account_id': creditAccountId,
          'debit': 0.0,
          'credit': amount,
          'description': autoDescription,
          'created_at': now,
        }, MoneyHelper.transactionMoneyFields),
      );

      // إنشاء قيود يومية - مدين
      await txn.insert('transactions', {
        'account_id': debitAccountId,
        'journal_id': journalId,
        'debit': MoneyHelper.toCents(amount),
        'credit': 0,
        'description': autoDescription,
        'date': date,
        'created_at': now,
        'reference_type': voucherType,
        'reference_id': 'voucher_$voucherId',
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, debitAccountId, amount, 0.0, now);

      // إنشاء قيود يومية - دائن
      await txn.insert('transactions', {
        'account_id': creditAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': MoneyHelper.toCents(amount),
        'description': autoDescription,
        'date': date,
        'created_at': now,
        'reference_type': voucherType,
        'reference_id': 'voucher_$voucherId',
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, creditAccountId, 0.0, amount, now);

      // تحديث رصيد الصندوق
      if (cashBoxId != null) {
        await _updateCashBoxBalance(txn, cashBoxId, amount, voucherType, now);
      }

      // تحديث رصيد الكيان
      await _updateEntityBalance(
          txn, entityType, entityId, amount, voucherType, now);
    });

    return voucherId;
  }

  // ══════════════════════════════════════════════════════════════
  //  إنشاء القيد العام تلقائياً
  // ══════════════════════════════════════════════════════════════

  /// إنشاء قيد عام (من حساب → إلى حساب) مع القيد المحاسبي التلقائي
  ///
  /// القيد المحاسبي:
  /// مدين = حساب "إلى" (الوجهة - يستقبل القيمة)
  /// دائن = حساب "من" (المصدر - يعطي القيمة)
  Future<int> createGeneralEntry({
    required String fromEntityType,
    required int fromEntityId,
    int? fromEntityAccountId,
    required double fromAmount,
    required String fromCurrency,
    required String toEntityType,
    required int toEntityId,
    int? toEntityAccountId,
    required double toAmount,
    required String toCurrency,
    required String date,
    String? description,
  }) async {
    // M-04: Validate that fromAmount == toAmount when currencies are the same
    if (fromCurrency == toCurrency && (fromAmount - toAmount).abs() >= 0.005) {
      throw Exception('مبالغ القيد غير متوازنة: المبلغ من ($fromAmount) لا يساوي المبلغ إلى ($toAmount) مع نفس العملة');
    }
    // التحقق من قفل الفترة المحاسبية
    await _dbHelper.journal.checkFiscalPeriodOpen(date);

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = generateUniqueJournalId();

    // تحديد حسابات القيد
    final fromAccount = await _resolveEntityAccountId(
      fromEntityType, fromCurrency,
      entityAccountId: fromEntityAccountId,
    );
    final toAccount = await _resolveEntityAccountId(
      toEntityType, toCurrency,
      entityAccountId: toEntityAccountId,
    );

    if (fromAccount == null) {
      throw Exception(
          'لم يتم العثور على حساب $fromEntityType بالعملة $fromCurrency في شجرة الحسابات');
    }
    if (toAccount == null) {
      throw Exception(
          'لم يتم العثور على حساب $toEntityType بالعملة $toCurrency في شجرة الحسابات');
    }

    // توليد رقم السند
    final voucherNumber =
        await _dbHelper.cashBoxes.getNextVoucherNumber('settlement');

    final fromEntityName = await _getEntityName(fromEntityType, fromEntityId);
    final toEntityName = await _getEntityName(toEntityType, toEntityId);

    final autoDescription = description?.trim().isNotEmpty == true
        ? description!
        : 'قيد عام: من $fromEntityName إلى $toEntityName';

    // تحديد العملة الأساسية (العملة الأكثر مبلغاً أو YER)
    final mainCurrency = fromAmount >= toAmount ? fromCurrency : toCurrency;
    final totalAmount = fromAmount >= toAmount ? fromAmount : toAmount;

    late int voucherId;
    await db.transaction((txn) async {
      // إدراج السند
      voucherId = await txn.insert(
        'vouchers',
        MoneyHelper.toCentsMap({
          'voucher_number': voucherNumber,
          'voucher_type': 'settlement',
          'date': date,
          'description': autoDescription,
          'currency': mainCurrency,
          'total_amount': totalAmount,
          'cash_box_id': null,
          'customer_id': fromEntityType == entityCustomer
              ? fromEntityId
              : (toEntityType == entityCustomer ? toEntityId : null),
          'supplier_id': fromEntityType == entitySupplier
              ? fromEntityId
              : (toEntityType == entitySupplier ? toEntityId : null),
          'employee_id': fromEntityType == entityEmployee
              ? fromEntityId
              : (toEntityType == entityEmployee ? toEntityId : null),
          'is_posted': 1,
          'created_at': now,
          'updated_at': now,
        }, MoneyHelper.voucherMoneyFields),
      );

      // بند مدين - حساب "إلى" (الوجهة)
      await txn.insert(
        'voucher_items',
        MoneyHelper.toCentsMap({
          'voucher_id': voucherId,
          'account_id': toAccount,
          'debit': toAmount,
          'credit': 0.0,
          'description': autoDescription,
          'created_at': now,
        }, MoneyHelper.transactionMoneyFields),
      );

      // بند دائن - حساب "من" (المصدر)
      await txn.insert(
        'voucher_items',
        MoneyHelper.toCentsMap({
          'voucher_id': voucherId,
          'account_id': fromAccount,
          'debit': 0.0,
          'credit': fromAmount,
          'description': autoDescription,
          'created_at': now,
        }, MoneyHelper.transactionMoneyFields),
      );

      // معالجة فروقات الصرف إذا اختلفت العملات
      if (fromCurrency != toCurrency) {
        await _handleExchangeDifference(
          txn: txn,
          journalId: journalId,
          fromAmount: fromAmount,
          fromCurrency: fromCurrency,
          toAmount: toAmount,
          toCurrency: toCurrency,
          date: date,
          now: now,
        );
      }

      // قيد يومي - مدين (حساب "إلى")
      await txn.insert('transactions', {
        'account_id': toAccount,
        'journal_id': journalId,
        'debit': MoneyHelper.toCents(toAmount),
        'credit': 0,
        'description': autoDescription,
        'date': date,
        'created_at': now,
        'reference_type': 'settlement',
        'reference_id': 'voucher_$voucherId',
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, toAccount, toAmount, 0.0, now);

      // قيد يومي - دائن (حساب "من")
      await txn.insert('transactions', {
        'account_id': fromAccount,
        'journal_id': journalId,
        'debit': 0,
        'credit': MoneyHelper.toCents(fromAmount),
        'description': autoDescription,
        'date': date,
        'created_at': now,
        'reference_type': 'settlement',
        'reference_id': 'voucher_$voucherId',
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, fromAccount, 0.0, fromAmount, now);

      // تحديث أرصدة الكيانات
      await _updateEntityBalanceForGeneralEntry(
        txn,
        fromEntityType, fromEntityId, fromAmount, fromCurrency,
        toEntityType, toEntityId, toAmount, toCurrency,
        now,
      );
    });

    return voucherId;
  }

  // ══════════════════════════════════════════════════════════════
  //  دوال مساعدة داخلية
  // ══════════════════════════════════════════════════════════════

  /// جلب اسم الكيان
  Future<String> _getEntityName(String entityType, int entityId) async {
    final db = await _db;
    String tableName;
    switch (entityType) {
      case entityCustomer:
        tableName = 'customers';
        break;
      case entitySupplier:
        tableName = 'suppliers';
        break;
      case entityEmployee:
        tableName = 'employees';
        break;
      case entityExpense:
        tableName = 'expense_sub_accounts';
        break;
      default:
        tableName = 'customers';
    }

    final rows =
        await db.query(tableName, where: 'id = ?', whereArgs: [entityId], limit: 1);
    if (rows.isNotEmpty) {
      return rows.first['name'] as String? ?? '';
    }
    return '';
  }

  /// تحديث رصيد الصندوق
  /// Uses signed-balance convention (same as EntityBalanceHelper) to correctly
  /// flip balance_type when the balance crosses zero.
  ///
  /// Convention: credit (له) = +balance, debit (عليه) = -balance
  /// Cash boxes are normally credit (positive = cash available).
  Future<void> _updateCashBoxBalance(
    Transaction txn,
    int cashBoxId,
    double amount,
    String voucherType,
    String now,
  ) async {
    final cashBox = await txn.query('cash_boxes',
        where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
    if (cashBox.isEmpty) return;

    final currentBalance = MoneyHelper.readMoney(cashBox.first['balance']);
    final balanceType =
        cashBox.first['balance_type'] as String? ?? 'credit';
    final isCashIn = voucherType == 'receipt';

    // Convert to signed value: credit = +balance, debit = -balance
    double signedBalance = balanceType == 'credit' ? currentBalance : -currentBalance;

    // Apply change: cash in increases credit (+), cash out decreases credit (-)
    signedBalance += isCashIn ? amount : -amount;

    // Convert back to magnitude + direction
    final newBalance = signedBalance.abs();
    final newType = signedBalance >= 0 ? 'credit' : 'debit';

    await txn.update('cash_boxes', {
      'balance': MoneyHelper.toCents(newBalance),
      'balance_type': newType,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [cashBoxId]);
  }

  /// تحديث رصيد الكيان حسب نوع السند
  Future<void> _updateEntityBalance(
    Transaction txn,
    String entityType,
    int entityId,
    double amount,
    String voucherType,
    String now,
  ) async {
    String tableName;
    switch (entityType) {
      case entityCustomer:
        tableName = 'customers';
        break;
      case entitySupplier:
        tableName = 'suppliers';
        break;
      case entityEmployee:
        tableName = 'employees';
        break;
      case entityExpense:
        // المصروفات لا تحتاج تحديث رصيد هنا لأنها تُحدث عبر expense_repository
        return;
      default:
        return;
    }

    // ── Update entity balance with balance_type-aware logic ──
    // Receipt from customer: credit effect (reduces what they owe)
    // Payment to customer: debit effect (increases what they owe)
    // Payment to supplier: debit effect (reduces what we owe)
    // Receipt from supplier: debit effect (increases what they owe us)
    if (entityType == entityCustomer) {
      if (voucherType == 'receipt') {
        await EntityBalanceHelper.customerReceipt(
          txn: txn, customerId: entityId, amount: amount, now: now,
        );
      } else {
        await EntityBalanceHelper.customerPayment(
          txn: txn, customerId: entityId, amount: amount, now: now,
        );
      }
    } else if (entityType == entitySupplier) {
      if (voucherType == 'payment') {
        await EntityBalanceHelper.supplierPayment(
          txn: txn, supplierId: entityId, amount: amount, now: now,
        );
      } else {
        await EntityBalanceHelper.supplierReceipt(
          txn: txn, supplierId: entityId, amount: amount, now: now,
        );
      }
    } else if (entityType == entityEmployee) {
      if (voucherType == 'receipt') {
        // Receipt for employee: credit effect (increases what we owe them)
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: entityId, creditEffect: amount, debitEffect: 0, now: now,
        );
      } else {
        // Payment to employee: debit effect (increases what they owe us)
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: entityId, creditEffect: 0, debitEffect: amount, now: now,
        );
      }
    }
  }

  /// تحديث أرصدة الكيانات في القيد العام
  Future<void> _updateEntityBalanceForGeneralEntry(
    Transaction txn,
    String fromEntityType, int fromEntityId, double fromAmount, String fromCurrency,
    String toEntityType, int toEntityId, double toAmount, String toCurrency,
    String now,
  ) async {
    // القيد العام: من حساب (دائن) إلى حساب (مدين)
    // "من" يعطي قيمة → رصيده ينقص (credit)
    // "إلى" يستقبل قيمة → رصيده يزيد (debit)

    // تحديث رصيد "من" (ينقص)
    await _updateEntityForGeneralEntry(
      txn, fromEntityType, fromEntityId, fromAmount, isSource: true, now: now,
    );

    // تحديث رصيد "إلى" (يزيد)
    await _updateEntityForGeneralEntry(
      txn, toEntityType, toEntityId, toAmount, isSource: false, now: now,
    );
  }

  Future<void> _updateEntityForGeneralEntry(
    Transaction txn,
    String entityType,
    int entityId,
    double amount, {
    required bool isSource,
    required String now,
  }) async {
    // General entry: "from" gives value (credit effect), "to" receives value (debit effect)
    //
    // For customers:
    //   Source (from) customer gives value → credit effect (they pay us → reduces what they owe)
    //   Destination (to) customer receives value → debit effect (we pay them → they owe us more)
    //
    // For suppliers:
    //   Source (from) supplier gives value → debit effect (they pay us → reduces what we owe)
    //   Destination (to) supplier receives value → credit effect (we pay them → we owe more)
    //
    // For employees:
    //   Source (from) employee gives value → credit effect (they earn more)
    //   Destination (to) employee receives value → debit effect (they owe more)

    if (entityType == entityCustomer) {
      if (isSource) {
        // "From" customer: credit effect (reduces what they owe us)
        await EntityBalanceHelper.customerReceipt(
          txn: txn, customerId: entityId, amount: amount, now: now,
        );
      } else {
        // "To" customer: debit effect (increases what they owe us)
        await EntityBalanceHelper.customerPayment(
          txn: txn, customerId: entityId, amount: amount, now: now,
        );
      }
    } else if (entityType == entitySupplier) {
      if (isSource) {
        // "From" supplier: debit effect (reduces what we owe them)
        await EntityBalanceHelper.supplierPayment(
          txn: txn, supplierId: entityId, amount: amount, now: now,
        );
      } else {
        // "To" supplier: credit effect (increases what we owe them)
        await EntityBalanceHelper.supplierPurchaseOnCredit(
          txn: txn, supplierId: entityId, amount: amount, now: now,
        );
      }
    } else if (entityType == entityEmployee) {
      if (isSource) {
        // "From" employee: credit effect (increases what we owe them)
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: entityId, creditEffect: amount, debitEffect: 0, now: now,
        );
      } else {
        // "To" employee: debit effect (increases what they owe us)
        await EntityBalanceHelper.applyEmployeeBalanceChange(
          txn: txn, employeeId: entityId, creditEffect: 0, debitEffect: amount, now: now,
        );
      }
    }
  }

  /// معالجة فروقات الصرف عند اختلاف العملات في القيد العام
  Future<void> _handleExchangeDifference({
    required Transaction txn,
    required int journalId,
    required double fromAmount,
    required String fromCurrency,
    required double toAmount,
    required String toCurrency,
    required String date,
    required String now,
  }) async {
    // تحويل كلا المبلغين إلى العملة الوظيفية (YER) للمقارنة
    final rates = await _getExchangeRates(txn);
    final fromInYER = fromAmount * (rates[fromCurrency] ?? 1.0);
    final toInYER = toAmount * (rates[toCurrency] ?? 1.0);

    final difference = (toInYER - fromInYER).abs();
    if (difference < 0.01) return; // لا يوجد فرق معنوي

    final isGain = toInYER > fromInYER;

    // حساب فروقات الصرف
    final exchangeAccountId =
        await _dbHelper.journal.getOrCreateExchangeAccount(isGain: isGain);

    if (isGain) {
      // مكسب صرف: دائن حساب فروقات الصرف
      await txn.insert('transactions', {
        'account_id': exchangeAccountId,
        'journal_id': journalId,
        'debit': 0,
        'credit': MoneyHelper.toCents(difference),
        'description': 'مكسب فروقات صرف - قيد عام',
        'date': date,
        'created_at': now,
        'reference_type': 'exchange_difference',
        'reference_id': journalId,
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, exchangeAccountId, 0.0, difference, now);
    } else {
      // خسارة صرف: مدين حساب فروقات الصرف
      await txn.insert('transactions', {
        'account_id': exchangeAccountId,
        'journal_id': journalId,
        'debit': MoneyHelper.toCents(difference),
        'credit': 0,
        'description': 'خسارة فروقات صرف - قيد عام',
        'date': date,
        'created_at': now,
        'reference_type': 'exchange_difference',
        'reference_id': journalId,
      });
      await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn, exchangeAccountId, difference, 0.0, now);
    }
  }

  /// جلب أسعار الصرف
  Future<Map<String, double>> _getExchangeRates(Transaction txn) async {
    final rates = <String, double>{'YER': 1.0};
    try {
      final currencies = await txn.query('currencies');
      for (final c in currencies) {
        final code = c['code'] as String? ?? '';
        final rate = (c['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        if (code.isNotEmpty) rates[code] = rate;
      }
    } catch (_) {
      rates['SAR'] = 140.0;
      rates['USD'] = 530.0;
    }
    return rates;
  }
}
