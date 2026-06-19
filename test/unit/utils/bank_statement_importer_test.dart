import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/utils/bank_statement_importer.dart';

/// F-02 unit tests for BankStatementImporter.
///
/// Tests the column auto-detection, date parsing, amount parsing,
/// and the full convertToStatementLines flow. CSV/Excel file parsing
/// is tested indirectly (the parseFile method requires I/O; the
/// parsing logic is exercised via the public convertToStatementLines
/// API with pre-parsed row data).
void main() {
  group('BankStatementImporter.autoDetectColumns', () {
    test('detects English column names', () {
      final headers = ['Date', 'Description', 'Amount', 'Reference'];
      final mapping = BankStatementImporter.autoDetectColumns(headers);
      expect(mapping.dateColumn, 'Date');
      expect(mapping.amountColumn, 'Amount');
      expect(mapping.referenceColumn, 'Reference');
      expect(mapping.descriptionColumn, 'Description');
    });

    test('detects Arabic column names', () {
      final headers = ['التاريخ', 'البيان', 'المبلغ', 'المرجع'];
      final mapping = BankStatementImporter.autoDetectColumns(headers);
      expect(mapping.dateColumn, 'التاريخ');
      expect(mapping.amountColumn, 'المبلغ');
      expect(mapping.referenceColumn, 'المرجع');
      expect(mapping.descriptionColumn, 'البيان');
    });

    test('detects separate credit/debit columns', () {
      final headers = ['Date', 'Credit', 'Debit', 'Description'];
      final mapping = BankStatementImporter.autoDetectColumns(headers);
      expect(mapping.dateColumn, 'Date');
      expect(mapping.creditColumn, 'Credit');
      expect(mapping.debitColumn, 'Debit');
      expect(mapping.descriptionColumn, 'Description');
      expect(mapping.amountColumn, isNull);
    });

    test('detects Arabic credit/debit columns', () {
      final headers = ['تاريخ', 'دائن', 'مدين', 'بيان'];
      final mapping = BankStatementImporter.autoDetectColumns(headers);
      expect(mapping.creditColumn, 'دائن');
      expect(mapping.debitColumn, 'مدين');
    });

    test('returns nulls for unrecognized headers', () {
      final headers = ['col1', 'col2', 'col3'];
      final mapping = BankStatementImporter.autoDetectColumns(headers);
      expect(mapping.dateColumn, isNull);
      expect(mapping.amountColumn, isNull);
    });
  });

  group('BankStatementImporter.convertToStatementLines — amount column', () {
    test('positive amount = credit (deposit)', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '1000.00', 'Description': 'Deposit'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        descriptionColumn: 'Description',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines, hasLength(1));
      expect(lines.first.transactionType, 'credit');
      expect(lines.first.amount, 1000.0);
    });

    test('negative amount = debit (withdrawal)', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '-500.00'},
      ];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines, hasLength(1));
      expect(lines.first.transactionType, 'debit');
      expect(lines.first.amount, 500.0);
    });

    test('zero amount is skipped', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '0.00'},
        {'Date': '2026-06-19', 'Amount': '100.00'},
      ];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines, hasLength(1), reason: 'Zero-amount rows should be skipped.');
    });

    test('type column overrides sign-based detection', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '1000.00', 'Type': 'debit'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        typeColumn: 'Type',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines.first.transactionType, 'debit',
          reason: 'Type column should override the positive-amount=credit default.');
      expect(lines.first.amount, 1000.0);
    });

    test('Arabic type values are recognized', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '500', 'Type': 'سحب'},
        {'Date': '2026-06-19', 'Amount': '300', 'Type': 'إيداع'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        typeColumn: 'Type',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines[0].transactionType, 'debit');
      expect(lines[1].transactionType, 'credit');
    });
  });

  group('BankStatementImporter.convertToStatementLines — credit/debit columns', () {
    test('credit column value > 0 → credit line', () {
      final rows = [
        {'Date': '2026-06-19', 'Credit': '1000', 'Debit': ''},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        creditColumn: 'Credit',
        debitColumn: 'Debit',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines, hasLength(1));
      expect(lines.first.transactionType, 'credit');
      expect(lines.first.amount, 1000.0);
    });

    test('debit column value > 0 → debit line', () {
      final rows = [
        {'Date': '2026-06-19', 'Credit': '', 'Debit': '500'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        creditColumn: 'Credit',
        debitColumn: 'Debit',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines.first.transactionType, 'debit');
      expect(lines.first.amount, 500.0);
    });

    test('both zero → skipped', () {
      final rows = [
        {'Date': '2026-06-19', 'Credit': '0', 'Debit': '0'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        creditColumn: 'Credit',
        debitColumn: 'Debit',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 1,
      );
      expect(lines, isEmpty);
    });
  });

  group('BankStatementImporter — date parsing', () {
    test('parses ISO format (YYYY-MM-DD)', () {
      final rows = [{'Date': '2026-06-19', 'Amount': '100'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.transactionDate.year, 2026);
      expect(lines.first.transactionDate.month, 6);
      expect(lines.first.transactionDate.day, 19);
    });

    test('parses DD/MM/YYYY format', () {
      final rows = [{'Date': '19/06/2026', 'Amount': '100'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.transactionDate.year, 2026);
      expect(lines.first.transactionDate.month, 6);
      expect(lines.first.transactionDate.day, 19);
    });

    test('skips rows with unparseable dates', () {
      final rows = [
        {'Date': 'invalid', 'Amount': '100'},
        {'Date': '2026-06-19', 'Amount': '200'},
      ];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines, hasLength(1), reason: 'Unparseable date rows should be skipped.');
    });
  });

  group('BankStatementImporter — amount parsing edge cases', () {
    test('handles comma as thousands separator (1,234.56)', () {
      final rows = [{'Date': '2026-06-19', 'Amount': '1,234.56'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.amount, 1234.56);
    });

    test('handles European format (1.234,56)', () {
      final rows = [{'Date': '2026-06-19', 'Amount': '1.234,56'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.amount, 1234.56);
    });

    test('handles comma as decimal (1234,56)', () {
      final rows = [{'Date': '2026-06-19', 'Amount': '1234,56'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.amount, 1234.56);
    });

    test('strips currency symbols', () {
      final rows = [{'Date': '2026-06-19', 'Amount': '500.00 SAR'}];
      final mapping =
          const ColumnMapping(dateColumn: 'Date', amountColumn: 'Amount');
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows, mapping: mapping, cashBoxId: 1);
      expect(lines.first.amount, 500.0);
    });
  });

  group('BankStatementImporter.convertToStatementLines — output properties', () {
    test('sets correct default fields', () {
      final rows = [
        {'Date': '2026-06-19', 'Amount': '100', 'Ref': 'TX001', 'Desc': 'Test'},
      ];
      final mapping = const ColumnMapping(
        dateColumn: 'Date',
        amountColumn: 'Amount',
        referenceColumn: 'Ref',
        descriptionColumn: 'Desc',
      );
      final lines = BankStatementImporter.convertToStatementLines(
        rows: rows,
        mapping: mapping,
        cashBoxId: 42,
        reconciliationId: 7,
      );
      expect(lines.first.cashBoxId, 42);
      expect(lines.first.reconciliationId, 7);
      expect(lines.first.reference, 'TX001');
      expect(lines.first.description, 'Test');
      expect(lines.first.matchStatus, 'unmatched');
      expect(lines.first.isBookEntry, isFalse);
      expect(lines.first.sourceType, 'imported');
    });
  });
}
