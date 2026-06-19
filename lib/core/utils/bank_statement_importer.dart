import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import 'package:firstpro/data/models/bank_reconciliation_model.dart';

/// F-02: Bank statement importer.
///
/// Parses CSV and Excel files into [BankStatementLine] objects for
/// bulk import into a bank reconciliation session. The importer is
/// column-mapping-aware: it auto-detects common column names (date,
/// amount, credit, debit, reference, description, type) and allows
/// the caller to override the mapping.
///
/// Supported file formats:
///   - .csv (comma, semicolon, or tab-separated)
///   - .xlsx, .xls (Excel via the `excel` package)
///
/// The importer does NOT insert into the DB — it returns a list of
/// BankStatementLine objects. The caller (typically the import screen)
/// is responsible for setting reconciliationId and calling
/// BankReconciliationService.addStatementLines.
class BankStatementImporter {
  BankStatementImporter._();

  /// Parse a file and return a list of raw rows (each row is a map
  /// of column-name → cell-value as String).
  ///
  /// The first row is treated as a header row. Returns an empty list
  /// if the file is empty or unparseable.
  static Future<List<Map<String, String>>> parseFile(File file) async {
    final ext = file.path.toLowerCase().split('.').last;
    switch (ext) {
      case 'csv':
      case 'txt':
        return _parseCsv(file);
      case 'xlsx':
      case 'xls':
        return _parseExcel(file);
      default:
        throw UnsupportedError('صيغة الملف غير مدعومة: .$ext. يدعم .csv و .xlsx');
    }
  }

  /// Auto-detect column mapping from the header row.
  ///
  /// Returns a [ColumnMapping] with the best-guess column names for
  /// each field. The caller can override any field before calling
  /// [convertToStatementLines].
  static ColumnMapping autoDetectColumns(List<String> headers) {
    final lowerHeaders =
        headers.map((h) => h.toLowerCase().trim()).toList();

    String? findColumn(List<String> keywords) {
      for (final h in lowerHeaders) {
        for (final kw in keywords) {
          if (h.contains(kw)) return headers[lowerHeaders.indexOf(h)];
        }
      }
      return null;
    }

    return ColumnMapping(
      dateColumn: findColumn(['date', 'تاريخ', 'التاريخ']),
      amountColumn: findColumn(['amount', 'المبلغ', 'قيمة', 'value']),
      creditColumn: findColumn(['credit', 'دائن', 'إيداع', 'deposit', 'cr']),
      debitColumn: findColumn(['debit', 'مدين', 'سحب', 'withdraw', 'dr']),
      referenceColumn:
          findColumn(['ref', 'reference', 'مرجع', 'المرجع', 'رقم', 'no']),
      descriptionColumn: findColumn([
        'desc',
        'description',
        'details',
        'بيان',
        'البيان',
        'تفاصيل',
        'ملاحظات',
        'notes'
      ]),
      typeColumn: findColumn(['type', 'نوع', 'النوع', 'direction', 'اتجاه']),
    );
  }

  /// Convert raw rows into [BankStatementLine] objects using the given
  /// [mapping] and [cashBoxId].
  ///
  /// Rules:
  ///   - If creditColumn and debitColumn are both mapped, the line type
  ///     is 'credit' if credit > 0, 'debit' if debit > 0. The amount
  ///     is the absolute value of whichever is non-zero.
  ///   - If only amountColumn is mapped, the sign determines the type:
  ///     positive = 'credit' (deposit), negative = 'debit' (withdrawal).
  ///     The amount is the absolute value.
  ///   - If amountColumn + typeColumn are mapped, the type column value
  ///     is parsed: 'credit'/'دائن'/'إيداع' → credit, 'debit'/'مدين'/'سحب' → debit.
  ///
  /// Rows with unparseable dates or zero amounts are skipped.
  static List<BankStatementLine> convertToStatementLines({
    required List<Map<String, String>> rows,
    required ColumnMapping mapping,
    required int cashBoxId,
    int? reconciliationId,
  }) {
    final lines = <BankStatementLine>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];

      // Parse date.
      final dateStr = mapping.dateColumn != null
          ? row[mapping.dateColumn!]?.trim() ?? ''
          : '';
      if (dateStr.isEmpty) continue;
      final date = _parseDate(dateStr);
      if (date == null) continue;

      // Determine amount and type.
      double amount = 0;
      String type = 'credit'; // default

      if (mapping.creditColumn != null && mapping.debitColumn != null) {
        // Separate credit/debit columns.
        final credit = _parseAmount(row[mapping.creditColumn!] ?? '');
        final debit = _parseAmount(row[mapping.debitColumn!] ?? '');
        if (credit > 0) {
          amount = credit;
          type = 'credit';
        } else if (debit > 0) {
          amount = debit;
          type = 'debit';
        } else {
          continue; // both zero — skip
        }
      } else if (mapping.amountColumn != null) {
        final rawAmount = _parseAmount(row[mapping.amountColumn!] ?? '');
        if (rawAmount == 0) continue;

        if (mapping.typeColumn != null) {
          // Use type column.
          final typeStr =
              (row[mapping.typeColumn!] ?? '').toLowerCase().trim();
          if (typeStr.contains('credit') ||
              typeStr.contains('دائن') ||
              typeStr.contains('إيداع') ||
              typeStr.contains('deposit')) {
            type = 'credit';
            amount = rawAmount.abs();
          } else if (typeStr.contains('debit') ||
              typeStr.contains('مدين') ||
              typeStr.contains('سحب') ||
              typeStr.contains('withdraw')) {
            type = 'debit';
            amount = rawAmount.abs();
          } else {
            // Unknown type — use sign.
            type = rawAmount > 0 ? 'credit' : 'debit';
            amount = rawAmount.abs();
          }
        } else {
          // No type column — use sign.
          type = rawAmount > 0 ? 'credit' : 'debit';
          amount = rawAmount.abs();
        }
      } else {
        continue; // no amount columns — skip
      }

      if (amount <= 0) continue;

      lines.add(BankStatementLine(
        reconciliationId: reconciliationId,
        cashBoxId: cashBoxId,
        transactionDate: date,
        transactionType: type,
        amount: amount,
        reference: mapping.referenceColumn != null
            ? row[mapping.referenceColumn!]?.trim()
            : null,
        description: mapping.descriptionColumn != null
            ? row[mapping.descriptionColumn!]?.trim()
            : null,
        matchStatus: 'unmatched',
        isBookEntry: false,
        sourceType: 'imported',
      ));
    }

    return lines;
  }

  // ── CSV parsing ──────────────────────────────────────────────────

  static Future<List<Map<String, String>>> _parseCsv(File file) async {
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];

    // Detect delimiter: comma, semicolon, or tab.
    final firstLine = content.split('\n').first;
    String delimiter;
    if (firstLine.contains('\t')) {
      delimiter = '\t';
    } else if (firstLine.contains(';')) {
      delimiter = ';';
    } else {
      delimiter = ',';
    }

    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];

    final headers = _splitCsvLine(lines.first, delimiter)
        .map((h) => h.trim().replaceAll('"', ''))
        .toList();

    final rows = <Map<String, String>>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i], delimiter);
      final row = <String, String>{};
      for (var j = 0; j < headers.length && j < cells.length; j++) {
        row[headers[j]] = cells[j].trim().replaceAll('"', '');
      }
      rows.add(row);
    }

    return rows;
  }

  /// Split a CSV line, handling quoted fields with embedded delimiters.
  static List<String> _splitCsvLine(String line, String delimiter) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  // ── Excel parsing ────────────────────────────────────────────────

  static Future<List<Map<String, String>>> _parseExcel(File file) async {
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final sheet = excel.tables.values.first;
    if (sheet == null || sheet.rows.isEmpty) return [];

    // First row = headers.
    final headerRow = sheet.rows.first;
    final headers = <String>[];
    for (final cell in headerRow) {
      headers.add((cell?.value?.toString() ?? '').trim());
    }

    final rows = <Map<String, String>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final rowCells = sheet.rows[i];
      final row = <String, String>{};
      for (var j = 0; j < headers.length && j < rowCells.length; j++) {
        row[headers[j]] = (rowCells[j]?.value?.toString() ?? '').trim();
      }
      // Skip completely empty rows.
      if (row.values.every((v) => v.isEmpty)) continue;
      rows.add(row);
    }

    return rows;
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Parse a date from various common formats.
  /// Supports: YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, DD-MM-YYYY.
  static DateTime? _parseDate(String dateStr) {
    dateStr = dateStr.trim();
    if (dateStr.isEmpty) return null;

    // Try ISO format first.
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}

    // Try DD/MM/YYYY or MM/DD/YYYY.
    final parts = dateStr.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      final p1 = int.tryParse(parts[0]) ?? 0;
      final p2 = int.tryParse(parts[1]) ?? 0;
      final p3 = int.tryParse(parts[2]) ?? 0;
      if (p3 > 31) {
        // p3 is the year → DD/MM/YYYY or MM/DD/YYYY
        if (p1 > 12) {
          // p1 is the day → DD/MM/YYYY
          return DateTime(p3, p2, p1);
        } else {
          // Ambiguous — assume DD/MM/YYYY (common outside US).
          return DateTime(p3, p2, p1);
        }
      } else if (p1 > 31) {
        // p1 is the year → YYYY/MM/DD
        return DateTime(p1, p2, p3);
      }
    }

    if (kDebugMode) {
      debugPrint('BankStatementImporter._parseDate: unparseable "$dateStr"');
    }
    return null;
  }

  /// Parse an amount from various formats.
  /// Handles: "1,234.56", "1234.56", "1.234,56" (European), "-50.00".
  static double _parseAmount(String amountStr) {
    amountStr = amountStr.trim();
    if (amountStr.isEmpty) return 0;

    // Remove currency symbols and spaces.
    // Match "ر.ي" as a whole sequence first, then individual symbols.
    // DO NOT put \. in a character class — it would strip decimal dots.
    amountStr = amountStr.replaceAll(RegExp(r'ر\.ي|[ري\$€£]|YER|SAR|USD'), '');
    amountStr = amountStr.trim();

    // Handle European format: 1.234,56 → 1234.56
    if (amountStr.contains('.') && amountStr.contains(',')) {
      if (amountStr.lastIndexOf(',') > amountStr.lastIndexOf('.')) {
        // Comma is the decimal separator.
        amountStr = amountStr.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // Dot is the decimal separator, comma is thousands.
        amountStr = amountStr.replaceAll(',', '');
      }
    } else if (amountStr.contains(',') && !amountStr.contains('.')) {
      // Only comma — could be decimal or thousands.
      if (amountStr.split(',').last.length == 2) {
        // Likely decimal: 1234,56 → 1234.56
        amountStr = amountStr.replaceAll(',', '.');
      } else {
        // Likely thousands: 1,234 → 1234
        amountStr = amountStr.replaceAll(',', '');
      }
    }

    return double.tryParse(amountStr) ?? 0;
  }
}

/// Column mapping for bank statement import.
///
/// The importer uses this to know which column in the parsed file
/// corresponds to each field. Any field can be null if the file
/// doesn't have a column for it.
class ColumnMapping {
  final String? dateColumn;
  final String? amountColumn;
  final String? creditColumn;
  final String? debitColumn;
  final String? referenceColumn;
  final String? descriptionColumn;
  final String? typeColumn;

  const ColumnMapping({
    this.dateColumn,
    this.amountColumn,
    this.creditColumn,
    this.debitColumn,
    this.referenceColumn,
    this.descriptionColumn,
    this.typeColumn,
  });

  ColumnMapping copyWith({
    String? dateColumn,
    String? amountColumn,
    String? creditColumn,
    String? debitColumn,
    String? referenceColumn,
    String? descriptionColumn,
    String? typeColumn,
  }) {
    return ColumnMapping(
      dateColumn: dateColumn ?? this.dateColumn,
      amountColumn: amountColumn ?? this.amountColumn,
      creditColumn: creditColumn ?? this.creditColumn,
      debitColumn: debitColumn ?? this.debitColumn,
      referenceColumn: referenceColumn ?? this.referenceColumn,
      descriptionColumn: descriptionColumn ?? this.descriptionColumn,
      typeColumn: typeColumn ?? this.typeColumn,
    );
  }
}
