import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/models/business_profile_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class BusinessProfileRepository {
  final DatabaseHelper _dbHelper;

  BusinessProfileRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  Future<BusinessProfile> getOrCreateProfile() async {
    final db = await _db;
    final typedRows = await db.query(
      'business_profile',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (typedRows.isNotEmpty) {
      return BusinessProfile.fromRow(typedRows.first);
    }

    final legacy = <String, String?>{
      'business_name': await _readSetting(db, 'business_name'),
      'business_phone': await _readSetting(db, 'business_phone'),
      'business_email': await _readSetting(db, 'business_email'),
      'business_address': await _readSetting(db, 'business_address'),
      'business_logo_path': await _readSetting(db, 'business_logo_path'),
    };
    final legacyCurrency = await _readSetting(db, 'default_currency');
    final defaultCurrency = legacyCurrency ?? await _readDefaultCurrency(db);
    final hasLegacyValues = legacy.values.any((value) => value != null) ||
        legacyCurrency != null;

    return BusinessProfile(
      businessName: legacy['business_name'],
      phone: legacy['business_phone'],
      email: legacy['business_email'],
      address: legacy['business_address'],
      logoPath: legacy['business_logo_path'],
      countryCode: 'YE',
      baseCurrencyCode: defaultCurrency ?? 'YER',
      locale: 'ar',
      timezone: 'Asia/Aden',
      taxMode: 'none',
      setupStatus: 'not_started',
      setupVersion: 1,
      source: hasLegacyValues ? 'legacy_settings' : 'migration',
    );
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    if (profile.countryCode.trim().isEmpty ||
        profile.baseCurrencyCode.trim().isEmpty) {
      throw ArgumentError('countryCode and baseCurrencyCode are required');
    }

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final existing = await txn.query(
        'business_profile',
        columns: ['created_at', 'base_currency_code'],
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      final createdAt = existing.isNotEmpty
          ? existing.first['created_at'] as String? ?? now
          : now;
      final normalizedBaseCurrencyCode =
          profile.baseCurrencyCode.trim().toUpperCase();
      final existingBaseCurrencyCode = existing.isNotEmpty
          ? (existing.first['base_currency_code'] as String?)
              ?.trim()
              .toUpperCase()
          : null;
      if (existingBaseCurrencyCode != null &&
          existingBaseCurrencyCode != normalizedBaseCurrencyCode &&
          await _hasPostedFinancialData(txn)) {
        throw StateError(
          'Base currency cannot be changed after financial data has been posted',
        );
      }

      final matchingCurrency = await txn.query(
        'currencies',
        columns: ['code'],
        where: 'code = ? AND is_active = 1',
        whereArgs: [normalizedBaseCurrencyCode],
        limit: 1,
      );
      if (matchingCurrency.isEmpty) {
        throw ArgumentError.value(
          profile.baseCurrencyCode,
          'baseCurrencyCode',
          'currency does not exist',
        );
      }
      await txn.update('currencies', {'is_default': 0});
      await txn.update(
        'currencies',
        {'is_default': 1},
        where: 'code = ?',
        whereArgs: [normalizedBaseCurrencyCode],
      );

      await txn.insert(
        'business_profile',
        {
          'id': 1,
          'business_name': profile.businessName,
          'phone': profile.phone,
          'email': profile.email,
          'address': profile.address,
          'logo_path': profile.logoPath,
          'country_code': profile.countryCode,
          'base_currency_code': normalizedBaseCurrencyCode,
          'locale': profile.locale,
          'timezone': profile.timezone,
          'tax_mode': profile.taxMode,
          'setup_status': profile.setupStatus,
          'setup_version': profile.setupVersion,
          'source': profile.source,
          'created_at': createdAt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await _writeLegacySetting(txn, 'business_name', profile.businessName, now);
      await _writeLegacySetting(txn, 'business_phone', profile.phone, now);
      await _writeLegacySetting(txn, 'business_email', profile.email, now);
      await _writeLegacySetting(txn, 'business_address', profile.address, now);
      await _writeLegacySetting(txn, 'business_logo_path', profile.logoPath, now);
      await _writeLegacySetting(
        txn,
        'default_currency',
        normalizedBaseCurrencyCode,
        now,
      );
    });
  }

  Future<bool> hasPostedFinancialData() async {
    return _hasPostedFinancialData(await _db);
  }

  Future<bool> _hasPostedFinancialData(DatabaseExecutor db) async {
    final postedInvoices = await db.rawQuery(
      'SELECT 1 FROM invoices WHERE is_posted = 1 LIMIT 1',
    );
    if (postedInvoices.isNotEmpty) return true;

    final transactions = await db.rawQuery(
      'SELECT 1 FROM transactions LIMIT 1',
    );
    return transactions.isNotEmpty;
  }

  Future<bool> canChangeBaseCurrency(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;

    final current = (await getOrCreateProfile()).baseCurrencyCode.toUpperCase();
    if (current == normalized) return true;
    return !(await hasPostedFinancialData());
  }

  Future<String?> _readSetting(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<String?> _readDefaultCurrency(DatabaseExecutor db) async {
    final rows = await db.query(
      'currencies',
      columns: ['code'],
      where: 'is_default = ?',
      whereArgs: [1],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['code'] as String?;
  }

  Future<void> _writeLegacySetting(
    DatabaseExecutor db,
    String key,
    String? value,
    String now,
  ) async {
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert(
      'settings',
      {'key': key, 'value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
