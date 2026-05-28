import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

class AuditService {
  final DatabaseHelper _dbHelper;
  AuditService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  /// Log an audit trail event (non-critical — errors are caught and printed)
  Future<void> logAuditEvent({
    required String action,
    required String tableName,
    int? recordId,
    String? recordType,
    String? oldValues,
    String? newValues,
    String? userName,
    int? shiftId,
  }) async {
    final db = await _db;
    try {
      await db.insert('audit_trail', {
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'record_type': recordType,
        'old_values': oldValues,
        'new_values': newValues,
        'user_name': userName,
        'shift_id': shiftId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Audit log error (non-critical): $e');
    }
  }
}
