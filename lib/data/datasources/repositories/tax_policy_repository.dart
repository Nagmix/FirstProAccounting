import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/models/document_tax_snapshot_model.dart';
import 'package:firstpro/data/models/tax_profile_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class TaxPolicyRepository {
  final DatabaseHelper _dbHelper;

  TaxPolicyRepository(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  Future<int> save(TaxProfile profile) async {
    _validateProfile(profile);
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    return db.insert(
      'tax_profiles',
      profile.toColumns(now: now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TaxProfile?> resolveActive({
    required String countryCode,
    required DateTime date,
  }) async {
    final normalizedCountry = countryCode.trim().toUpperCase();
    if (normalizedCountry.isEmpty) return null;

    final db = await _db;
    final rows = await db.query(
      'tax_profiles',
      where: 'country_code = ? AND is_active = 1 AND valid_from <= ? '
          'AND (valid_to IS NULL OR valid_to >= ?)',
      whereArgs: [
        normalizedCountry,
        date.toIso8601String(),
        date.toIso8601String(),
      ],
      orderBy: 'valid_from DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TaxProfile.fromRow(rows.first);
  }

  Future<void> saveSnapshot(DocumentTaxSnapshot snapshot) async {
    _validateSnapshot(snapshot);
    final db = await _db;
    final existing = await db.query(
      'document_tax_snapshots',
      where: 'document_type = ? AND document_id = ?',
      whereArgs: [snapshot.documentType, snapshot.documentId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final stored = DocumentTaxSnapshot.fromRow(existing.first);
      if (!_sameSnapshot(stored, snapshot)) {
        throw StateError('لا يمكن تعديل لقطة الضريبة بعد حفظها');
      }
      return;
    }

    final now = DateTime.now().toIso8601String();
    await db.insert('document_tax_snapshots', snapshot.toColumns(now: now));
  }

  Future<DocumentTaxSnapshot?> getSnapshot(
    String documentType,
    String documentId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'document_tax_snapshots',
      where: 'document_type = ? AND document_id = ?',
      whereArgs: [documentType, documentId],
      limit: 1,
    );
    return rows.isEmpty ? null : DocumentTaxSnapshot.fromRow(rows.first);
  }

  void _validateProfile(TaxProfile profile) {
    if (profile.countryCode.trim().isEmpty ||
        profile.regimeCode.trim().isEmpty ||
        profile.nameAr.trim().isEmpty) {
      throw ArgumentError('بيانات سياسة الضريبة الأساسية مطلوبة');
    }
    if (profile.rateBasisPoints < 0 || profile.rateBasisPoints > 100000) {
      throw ArgumentError.value(
        profile.rateBasisPoints,
        'rateBasisPoints',
        'يجب أن تكون بين 0% و1000%',
      );
    }
    if (!{'exclusive', 'inclusive'}.contains(profile.calculationMethod)) {
      throw ArgumentError.value(
        profile.calculationMethod,
        'calculationMethod',
        'يجب أن تكون exclusive أو inclusive',
      );
    }
    if (profile.validTo != null && profile.validTo!.isBefore(profile.validFrom)) {
      throw ArgumentError('validTo لا يمكن أن يسبق validFrom');
    }
  }

  void _validateSnapshot(DocumentTaxSnapshot snapshot) {
    if (snapshot.documentType.trim().isEmpty ||
        snapshot.documentId.trim().isEmpty ||
        snapshot.countryCode.trim().isEmpty ||
        snapshot.regimeCode.trim().isEmpty) {
      throw ArgumentError('هوية المستند وبيانات السياسة مطلوبة');
    }
    if (snapshot.rateBasisPoints < 0 || snapshot.rateBasisPoints > 100000) {
      throw ArgumentError.value(snapshot.rateBasisPoints, 'rateBasisPoints');
    }
    final allowsSignedAmounts = snapshot.documentType == 'credit_note' ||
        snapshot.documentType == 'return' ||
        snapshot.documentType.endsWith('_return');
    if (!allowsSignedAmounts &&
        (snapshot.taxableSubtotalMinor < 0 ||
            snapshot.taxableTransportMinor < 0 ||
            snapshot.discountMinor < 0 ||
            snapshot.taxMinor < 0)) {
      throw ArgumentError('قيم الضريبة لا يمكن أن تكون سالبة للمستندات العادية');
    }
  }

  bool _sameSnapshot(DocumentTaxSnapshot a, DocumentTaxSnapshot b) {
    return a.documentType == b.documentType &&
        a.documentId == b.documentId &&
        a.taxProfileId == b.taxProfileId &&
        a.countryCode == b.countryCode &&
        a.regimeCode == b.regimeCode &&
        a.rateBasisPoints == b.rateBasisPoints &&
        a.calculationMethod == b.calculationMethod &&
        a.transportTaxable == b.transportTaxable &&
        a.taxableSubtotalMinor == b.taxableSubtotalMinor &&
        a.taxableTransportMinor == b.taxableTransportMinor &&
        a.discountMinor == b.discountMinor &&
        a.taxMinor == b.taxMinor &&
        a.roundingMode == b.roundingMode &&
        a.source == b.source;
  }
}
