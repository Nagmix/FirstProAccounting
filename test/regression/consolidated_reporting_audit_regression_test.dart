import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards for consolidated reporting and accounting audit.
///
/// Consolidated reports must use the base-currency amount captured when a
/// journal was posted. Revaluing historical rows with today's currency rate
/// changes previously reported balances and makes reports non-reproducible.
void main() {
  group('consolidated reporting and audit regressions', () {
    late String reportSource;
    late String auditSource;

    setUpAll(() {
      reportSource = File(
        'lib/data/datasources/services/report_service.dart',
      ).readAsStringSync();
      auditSource = File(
        'lib/data/datasources/services/audit_service.dart',
      ).readAsStringSync();
    });

    test('consolidated trial balance aggregates signed historical amount_base', () {
      final start = reportSource.indexOf(
        'Future<List<Map<String, dynamic>>> getConsolidatedTrialBalanceReport',
      );
      expect(start, greaterThan(0));
      final end = reportSource.indexOf(
        '\n  // ── 16. Customer Statement',
        start,
      );
      final body = reportSource.substring(start, end > start ? end : reportSource.length);

      expect(
        body.contains('SUM(CASE WHEN t.debit > 0 THEN t.amount_base ELSE -t.amount_base END)'),
        isTrue,
        reason: 'Historical consolidated balances must use the signed amount_base captured at posting time.',
      );
      expect(
        body.contains('exchange_rate_used'),
        isTrue,
        reason: 'The report should expose the posting/conversion metadata used for auditability.',
      );
      expect(
        body.contains('SUM(t.debit)') && body.contains('cur.rate') &&
            body.contains(') *\n          CASE WHEN a.currency = ?'),
        isFalse,
        reason: 'Current currency rates must not revalue historical consolidated balances.',
      );
    });

    test('general ledger report exposes transaction currency metadata', () {
      final start = reportSource.indexOf(
        'Future<List<Map<String, dynamic>>> getAllAccountMovementReport',
      );
      expect(start, greaterThan(0));
      final end = reportSource.indexOf(
        '\n  // ── 15. Trial Balance',
        start,
      );
      final body = reportSource.substring(start, end > start ? end : reportSource.length);

      expect(
        body.contains('t.currency_code') && body.contains('t.exchange_rate') && body.contains('t.amount_base'),
        isTrue,
        reason: 'General ledger rows must preserve currency, rate, and historical base amount for audit.',
      );
    });

    test('audit service exposes an explicit unbalanced-journal query', () {
      expect(auditSource.contains('Future<List<Map<String, dynamic>>> getUnbalancedJournals'), isTrue);
      expect(auditSource.contains('HAVING ABS(SUM(t.debit) - SUM(t.credit)) > 0.01'), isTrue);
    });
  });
}
