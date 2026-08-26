import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/models/capability_state_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class CapabilityRepository {
  final DatabaseHelper _dbHelper;

  CapabilityRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  Future<List<CapabilityState>> getAllStates() async {
    final db = await _db;
    final rows = await db.query(
      'business_capabilities',
      orderBy: 'capability_code ASC',
    );
    return rows.map(CapabilityState.fromRow).toList(growable: false);
  }

  Future<Set<String>> getEnabledCodes() async {
    final states = await getAllStates();
    return states
        .where((state) => state.enabled)
        .map((state) => state.capabilityCode)
        .toSet();
  }

  Future<void> replaceEnabledCodes(
    Iterable<String> requested, {
    required String source,
  }) async {
    final resolved = CapabilityCatalog.resolveDependencies(requested)
      ..addAll(_coreCodes);
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final currentEnabled = await getEnabledCodes();

    for (final code in currentEnabled.difference(resolved)) {
      _ensureCanDisable(code, resultingEnabled: resolved);
    }

    await db.transaction((txn) async {
      final existing = await txn.query(
        'business_capabilities',
        columns: ['capability_code'],
      );
      final existingCodes = existing
          .map((row) => row['capability_code'] as String)
          .toSet();

      for (final code in existingCodes.difference(resolved)) {
        await _setEnabled(txn, code, false, source, now);
      }
      for (final code in resolved) {
        await _setEnabled(txn, code, true, source, now);
      }
    });
  }

  Future<void> setEnabled(
    String code,
    bool enabled, {
    required String source,
  }) async {
    final definition = CapabilityCatalog.byCode(code);
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final currentEnabled = await getEnabledCodes();
    final resolved = enabled
        ? CapabilityCatalog.resolveDependencies(<String>{code})
        : <String>{definition.code};

    if (!enabled) {
      _ensureCanDisable(
        code,
        currentEnabled: currentEnabled,
        resultingEnabled: {...currentEnabled}..remove(code),
      );
    }

    await db.transaction((txn) async {
      for (final resolvedCode in resolved) {
        await _setEnabled(txn, resolvedCode, enabled, source, now);
      }
    });
  }

  Future<bool> hasDataFor(String code) async {
    CapabilityCatalog.byCode(code);
    final db = await _db;
    final checks = <String, List<(String, String, List<Object?>)>>{
      'sell': <(String, String, List<Object?>)>[
        ('invoices', 'is_posted = 1', <Object?>[]),
      ],
      'buy': <(String, String, List<Object?>)>[
        ('invoices', "is_posted = 1 AND type = 'purchase'", <Object?>[]),
      ],
      'stock': <(String, String, List<Object?>)>[
        ('stock_movements', '1 = 1', <Object?>[]),
        ('inventory_vouchers', '1 = 1', <Object?>[]),
      ],
      'service': <(String, String, List<Object?>)>[
        ('service_orders', '1 = 1', <Object?>[]),
      ],
      'schedule': <(String, String, List<Object?>)>[
        ('service_orders', 'promised_at IS NOT NULL', <Object?>[]),
      ],
      'transform': <(String, String, List<Object?>)>[
        ('production_orders', '1 = 1', <Object?>[]),
        ('recipes', '1 = 1', <Object?>[]),
      ],
      'settle': <(String, String, List<Object?>)>[
        ('transactions', '1 = 1', <Object?>[]),
        ('vouchers', '1 = 1', <Object?>[]),
      ],
      'reporting': <(String, String, List<Object?>)>[
        ('transactions', '1 = 1', <Object?>[]),
      ],
      'backup': <(String, String, List<Object?>)>[],
      'settings': <(String, String, List<Object?>)>[],
      'audit': <(String, String, List<Object?>)>[
        ('audit_log', '1 = 1', <Object?>[]),
      ],
    };

    for (final check in checks[code] ?? const <(String, String, List<Object?>)>[]) {
      try {
        final rows = await db.query(
          check.$1,
          columns: ['1'],
          where: check.$2,
          whereArgs: check.$3,
          limit: 1,
        );
        if (rows.isNotEmpty) return true;
      } on DatabaseException {
        // A capability may refer to a table introduced by a later optional
        // module. Missing table means there is no data for this capability.
      }
    }
    return false;
  }

  static final Set<String> _coreCodes = CapabilityCatalog.definitions
      .where((definition) => definition.isCore)
      .map((definition) => definition.code)
      .toSet();

  void _ensureCanDisable(
    String code, {
    Set<String>? currentEnabled,
    required Set<String> resultingEnabled,
  }) {
    final definition = CapabilityCatalog.byCode(code);
    if (definition.isCore) {
      throw StateError('لا يمكن تعطيل وظيفة أساسية للنظام');
    }

    for (final candidate in CapabilityCatalog.definitions) {
      if (candidate.code == code || !resultingEnabled.contains(candidate.code)) {
        continue;
      }
      if (candidate.dependencies.contains(code) &&
          (currentEnabled == null || currentEnabled.contains(candidate.code))) {
        throw StateError('لا يمكن تعطيل وظيفة مطلوبة لوظيفة مفعلة');
      }
    }
  }

  Future<void> _setEnabled(
    DatabaseExecutor db,
    String code,
    bool enabled,
    String source,
    String now,
  ) async {
    final values = <String, Object?>{
      'capability_code': code,
      'enabled': enabled ? 1 : 0,
      'source': source,
      'definition_version': 1,
      'enabled_at': enabled ? now : null,
      'disabled_at': enabled ? null : now,
      'created_at': now,
      'updated_at': now,
    };
    await db.insert(
      'business_capabilities',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
