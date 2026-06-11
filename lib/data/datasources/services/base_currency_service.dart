import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

class BaseCurrencyService {
  final DatabaseHelper _dbHelper;
  BaseCurrencyService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  String? _cachedBaseCurrencyCode;
  Map<String, int> _offsetCache = {};

  /// Get the functional (default) currency code of the system.
  /// Reads from `currencies.is_default` first; falls back to `settings.default_currency`
  /// and finally to hardcoded 'YER' if neither is configured.
  Future<String> getBaseCurrencyCode() async {
    if (_cachedBaseCurrencyCode != null) return _cachedBaseCurrencyCode!;
    
    final db = await _db;
    final result = await db.query('currencies', 
        where: 'is_default = 1', 
        limit: 1);
    
    if (result.isNotEmpty) {
      _cachedBaseCurrencyCode = result.first['code'] as String;
    } else {
      // Fallback 1: settings.default_currency (added in migration v53)
      final settingsResult = await db.query('settings',
          where: 'key = ?',
          whereArgs: ['default_currency'],
          limit: 1);
      if (settingsResult.isNotEmpty) {
        _cachedBaseCurrencyCode = settingsResult.first['value'] as String?;
      }
      // Fallback 2: universal hardcoded default
      _cachedBaseCurrencyCode ??= 'YER';
    }
    return _cachedBaseCurrencyCode!;
  }

  /// Check if a given currency code is the base currency.
  Future<bool> isBaseCurrency(String code) async {
    final base = await getBaseCurrencyCode();
    return base == code;
  }

  /// Get the account code offset for a specific currency.
  Future<int> getOffsetForCurrency(String code) async {
    if (_offsetCache.containsKey(code)) return _offsetCache[code]!;

    final db = await _db;
    final result = await db.query('currencies', 
        columns: ['code_offset'],
        where: 'code = ?', 
        whereArgs: [code],
        limit: 1);
    
    int offset = 0;
    if (result.isNotEmpty) {
      offset = result.first['code_offset'] as int? ?? 0;
    } else {
      // Hardcoded fallback for known legacy currencies if record missing
      if (code == 'SAR') offset = 1;
      else if (code == 'USD') offset = 2;
    }
    
    _offsetCache[code] = offset;
    return offset;
  }

  /// Get the VAT rate for a specific currency (default 0.0 if not found).
  Future<double> getVatRateForCurrency(String code) async {
    final db = await _db;
    final result = await db.query('currencies',
        columns: ['vat_rate'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1);
    if (result.isNotEmpty) {
      return (result.first['vat_rate'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  /// Reset cache when currency settings change.
  void clearCache() {
    _cachedBaseCurrencyCode = null;
    _offsetCache.clear();
  }
}
