import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Shared helper methods used by database migrations and schema operations.
class MigrationHelpers {
  /// Log a migration error instead of silently swallowing it (H-07)
  /// This helps debug database issues during upgrades.
  static void logMigrationError(String operation, dynamic error) {
    debugPrint('⚠️ DB Migration Warning [$operation]: $error');
    // Non-critical: migrations may fail if column already exists (idempotent)
  }

  /// Validate that total debits equal total credits for a journal entry (C-03)
  /// Throws an exception if the journal entry is unbalanced.
  static void validateJournalBalance(List<Map<String, dynamic>> entries) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final entry in entries) {
      totalDebit += MoneyHelper.readMoney(entry['debit']);
      totalCredit += MoneyHelper.readMoney(entry['credit']);
    }
    final difference = (totalDebit - totalCredit).abs();
    if (difference > 0.01) {
      debugPrint(
          '⚠️ UNBALANCED JOURNAL ENTRY: Debit=$totalDebit, Credit=$totalCredit, Diff=$difference');
      throw Exception(
          'قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference');
    }
  }

  /// Update an account's balance considering its balance_type.
  /// For credit-balance accounts (LIABILITY, REVENUE, EQUITY):
  ///   balance = balance + credit - debit
  /// For debit-balance accounts (ASSET, EXPENSE, COST):
  ///   balance = balance + debit - credit
  static Future<void> updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final account = await txn.query('accounts',
        where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceType = account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update('accounts',
          {'balance': MoneyHelper.toCents(newBalance), 'updated_at': now},
          where: 'id = ?', whereArgs: [accountId]);
    }
  }

  /// التحقق من أن الفترة المحاسبية مفتوحة قبل إجراء أي عملية
  /// يمنع تعديل أو إضافة قيود في فترات مغلقة
  static Future<void> checkFiscalPeriodOpen(
      DatabaseExecutor db, String dateStr) async {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return;
    final year = date.year;

    // تحقق من وجود سنة مالية مقفلة لهذه الفترة
    final result = await db.query(
      'fiscal_years',
      where: 'year = ? AND status = ?',
      whereArgs: [year, 'closed'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      throw Exception(
          'الفترة المحاسبية للعام $year مغلقة. لا يمكن إجراء عمليات في فترة مقفلة.');
    }
  }

  /// الحصول على أو إنشاء حساب مكاسب/خسائر الصرف الأجنبي
  static Future<int> getOrCreateExchangeAccount(DatabaseExecutor db) async {
    // البحث عن حساب مكاسب/خسائر الصرف
    final existing = await db.query(
      'accounts',
      where: "account_code LIKE '53%' AND is_system = 1",
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    // إنشاء حساب جديد
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('accounts', {
      'name_ar': 'مكاسب/خسائر فروقات الصرف',
      'name_en': 'Exchange Rate Gains/Losses',
      'account_code': '5300',
      'account_type': 'EXPENSE',
      'balance': 0,
      'currency': 'YER',
      'balance_type': 'credit',
      'is_active': 1,
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  /// التحقق الإلزامي من توازن القيد المزدوج قبل الحفظ
  /// يُستخدم كدالة مساعدة للتأكد من أن مجموع المدين = مجموع الدائن
  static void assertJournalBalance(List<Map<String, dynamic>> entries) {
    final totalDebit =
        entries.fold(0.0, (sum, e) => sum + MoneyHelper.readMoney(e['debit']));
    final totalCredit =
        entries.fold(0.0, (sum, e) => sum + MoneyHelper.readMoney(e['credit']));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception(
          'القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit. يجب أن يتساوى المدين والدائن.');
    }
  }
}
