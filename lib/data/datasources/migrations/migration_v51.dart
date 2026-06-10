import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v51 — Support dynamic currencies and base codes
///
/// 1. Add `code_offset` to `currencies` table.
/// 2. Add `base_code` to `accounts` table.
/// 3. Backfill existing data.
class MigrationV51 {
  static Future<void> migrate(Database db) async {
    // 1. Add code_offset to currencies
    await db.execute('ALTER TABLE currencies ADD COLUMN code_offset INTEGER DEFAULT 0');

    // 2. Add base_code to accounts
    await db.execute('ALTER TABLE accounts ADD COLUMN base_code INTEGER');

    // 3. Backfill currencies offsets
    await db.update('currencies', {'code_offset': 0}, where: "code = 'YER'");
    await db.update('currencies', {'code_offset': 1}, where: "code = 'SAR'");
    await db.update('currencies', {'code_offset': 2}, where: "code = 'USD'");

    // For any other existing currencies, assign incremental offsets
    final otherCurrencies = await db.query('currencies', 
        where: "code NOT IN ('YER', 'SAR', 'USD')",
        orderBy: 'id ASC');
    
    int nextOffset = 3;
    for (final c in otherCurrencies) {
      await db.update('currencies', 
          {'code_offset': nextOffset}, 
          where: "id = ?", 
          whereArgs: [c['id']]);
      nextOffset++;
    }

    // 4. Backfill base_code in accounts
    // We calculate base_code = account_code - offset
    final accounts = await db.query('accounts');
    for (final acc in accounts) {
      final String codeStr = acc['account_code'] as String;
      final String currency = acc['currency'] as String;
      final int? codeInt = int.tryParse(codeStr);
      
      if (codeInt != null) {
        int offset = 0;
        if (currency == 'SAR') offset = 1;
        else if (currency == 'USD') offset = 2;
        // For others, we'd need to look up the newly assigned offset
        else if (currency != 'YER') {
          final cRow = await db.query('currencies', where: 'code = ?', whereArgs: [currency], limit: 1);
          if (cRow.isNotEmpty) {
            offset = cRow.first['code_offset'] as int;
          }
        }
        
        await db.update('accounts', 
            {'base_code': codeInt - offset}, 
            where: 'id = ?', 
            whereArgs: [acc['id']]);
      }
    }
  }
}
