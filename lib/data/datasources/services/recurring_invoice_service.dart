import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

/// F-03: Recurring invoice service.
///
/// Manages recurring invoice templates and generates real invoices on
/// a schedule. The service is called on app launch (fire-and-forget)
/// and can be triggered manually from the recurring invoices screen.
///
/// Schedule:
///   - Each recurring invoice has a `frequency` (daily/weekly/monthly/
///     yearly), an `interval_value` (every N units), and a
///     `next_run_date`.
///   - On each run, the service finds all 'active' templates whose
///     next_run_date <= today and generates a real invoice for each.
///   - After generating, next_run_date is advanced by interval_value
///     units of frequency. If next_run_date > end_date, the template
///     is marked 'paused'.
///
/// Generated invoices:
///   - Use the same saveInvoiceWithJournalEntries path as manual
///     invoices, so they get full journal entries, stock updates, and
///     entity balance updates.
///   - For 'credit' payment mechanism, paid_amount = 0 (the invoice is
///     posted as credit, increasing the customer/supplier balance).
///   - For 'cash' payment mechanism, paid_amount = total (posted as
///     fully paid, cash box balance updated).
class RecurringInvoiceService {
  final DatabaseHelper _dbHelper;
  final InvoiceRepository _invoiceRepo;
  final ReferenceDataRepository _refRepo;
  RecurringInvoiceService(this._dbHelper, this._invoiceRepo, this._refRepo);

  Future<Database> get _db => _dbHelper.database;

  // ── CRUD: recurring invoice templates ────────────────────────────

  /// Create a new recurring invoice template.
  ///
  /// [template] must include all required fields (name, invoice_type,
  /// payment_mechanism, frequency, interval_value, next_run_date,
  /// currency, etc.). Money fields (discount_amount, transport_charges)
  /// should be in human-readable doubles — they'll be converted to
  /// cents internally.
  ///
  /// [items] is the list of line items. Each item should have:
  ///   - product_id (int?)
  ///   - product_name (String)
  ///   - quantity (double)
  ///   - unit_price (double)
  ///   - total_price (double)
  ///   - unit_name (String?)
  ///   - conversion_factor (double, default 1.0)
  ///   - base_quantity (double, default = quantity * conversion_factor)
  ///
  /// Returns the ID of the newly created template.
  Future<int> createTemplate({
    required Map<String, dynamic> template,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Convert money fields to cents.
    final dbTemplate = Map<String, dynamic>.from(template);
    dbTemplate['discount_amount'] =
        MoneyHelper.toCents(MoneyHelper.readMoney(template['discount_amount']));
    dbTemplate['transport_charges'] =
        MoneyHelper.toCents(MoneyHelper.readMoney(template['transport_charges']));
    dbTemplate['created_at'] = now;
    dbTemplate['updated_at'] = now;
    dbTemplate['generated_count'] = 0;
    dbTemplate['status'] ??= 'active';

    return await db.transaction((txn) async {
      final id = await txn.insert('recurring_invoices', dbTemplate);

      // Insert items (convert money fields to cents).
      for (final item in items) {
        final dbItem = Map<String, dynamic>.from(item);
        dbItem['recurring_invoice_id'] = id;
        dbItem['unit_price'] =
            MoneyHelper.toCents(MoneyHelper.readMoney(item['unit_price']));
        dbItem['total_price'] =
            MoneyHelper.toCents(MoneyHelper.readMoney(item['total_price']));
        dbItem['conversion_factor'] ??= 1.0;
        dbItem['base_quantity'] ??=
            (item['quantity'] as num?)?.toDouble() ?? 1.0;
        await txn.insert('recurring_invoice_items', dbItem);
      }

      return id;
    });
  }

  /// Update an existing template.
  Future<void> updateTemplate(
    int id, {
    required Map<String, dynamic> template,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final dbTemplate = Map<String, dynamic>.from(template);
    dbTemplate['discount_amount'] =
        MoneyHelper.toCents(MoneyHelper.readMoney(template['discount_amount']));
    dbTemplate['transport_charges'] =
        MoneyHelper.toCents(MoneyHelper.readMoney(template['transport_charges']));
    dbTemplate['updated_at'] = now;

    await db.transaction((txn) async {
      await txn.update('recurring_invoices', dbTemplate,
          where: 'id = ?', whereArgs: [id]);
      // Replace items: delete old, insert new.
      await txn.delete('recurring_invoice_items',
          where: 'recurring_invoice_id = ?', whereArgs: [id]);
      for (final item in items) {
        final dbItem = Map<String, dynamic>.from(item);
        dbItem['recurring_invoice_id'] = id;
        dbItem['unit_price'] =
            MoneyHelper.toCents(MoneyHelper.readMoney(item['unit_price']));
        dbItem['total_price'] =
            MoneyHelper.toCents(MoneyHelper.readMoney(item['total_price']));
        dbItem['conversion_factor'] ??= 1.0;
        dbItem['base_quantity'] ??=
            (item['quantity'] as num?)?.toDouble() ?? 1.0;
        await txn.insert('recurring_invoice_items', dbItem);
      }
    });
  }

  /// Delete a template (cascades to items via FK).
  Future<void> deleteTemplate(int id) async {
    final db = await _db;
    await db.delete('recurring_invoices', where: 'id = ?', whereArgs: [id]);
  }

  /// Pause a template (set status='paused').
  Future<void> pauseTemplate(int id) async {
    final db = await _db;
    await db.update('recurring_invoices', {'status': 'paused', 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Resume a template (set status='active').
  /// Also recalculates next_run_date if it's in the past.
  Future<void> resumeTemplate(int id) async {
    final db = await _db;
    final rows = await db.query('recurring_invoices',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    final nextRun = row['next_run_date'] as String?;
    var newNextRun = nextRun;
    if (nextRun != null) {
      try {
        final nextDate = DateTime.parse(nextRun);
        if (nextDate.isBefore(DateTime.now())) {
          // Advance to the next valid run date from today.
          newNextRun = _advanceNextRunDate(
            DateTime.now(),
            row['frequency'] as String? ?? 'monthly',
            (row['interval_value'] as num?)?.toInt() ?? 1,
          ).toIso8601String().substring(0, 10);
        }
      } catch (_) {}
    }
    await db.update('recurring_invoices', {
      'status': 'active',
      'next_run_date': newNextRun,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Get all templates (with optional status filter).
  Future<List<Map<String, dynamic>>> getAllTemplates({String? status}) async {
    final db = await _db;
    if (status != null) {
      return await db.query('recurring_invoices',
          where: 'status = ?', whereArgs: [status], orderBy: 'next_run_date ASC');
    }
    return await db.query('recurring_invoices', orderBy: 'next_run_date ASC');
  }

  /// Get a single template by ID.
  Future<Map<String, dynamic>?> getTemplate(int id) async {
    final db = await _db;
    final rows = await db.query('recurring_invoices',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Get the items for a template.
  Future<List<Map<String, dynamic>>> getTemplateItems(int templateId) async {
    final db = await _db;
    return await db.query('recurring_invoice_items',
        where: 'recurring_invoice_id = ?',
        whereArgs: [templateId],
        orderBy: 'id ASC');
  }

  // ── Generation: process due templates ────────────────────────────

  /// Process all due templates: generate invoices for any template
  /// whose status='active' and next_run_date <= today.
  ///
  /// Returns a [RecurringGenerationResult] with counts of generated,
  /// skipped, and failed templates.
  ///
  /// Safe to call repeatedly — advances next_run_date after each
  /// generation so the same template isn't processed twice for the
  /// same date.
  Future<RecurringGenerationResult> processDueTemplates() async {
    final db = await _db;
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);

    // Find all active templates whose next_run_date <= today AND
    // (end_date IS NULL OR end_date >= today).
    final dueTemplates = await db.rawQuery(
      "SELECT * FROM recurring_invoices "
      "WHERE status = 'active' AND date(next_run_date) <= date(?) "
      "AND (end_date IS NULL OR date(end_date) >= date(next_run_date)) "
      "ORDER BY next_run_date ASC",
      [todayStr],
    );

    int generated = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    for (final template in dueTemplates) {
      try {
        final invoiceId = await _generateInvoiceFromTemplate(template, today);
        if (invoiceId != null) {
          generated++;
          // Advance next_run_date.
          final frequency = template['frequency'] as String? ?? 'monthly';
          final interval = (template['interval_value'] as num?)?.toInt() ?? 1;
          final currentNextRun =
              DateTime.parse(template['next_run_date'] as String);
          var newNextRun = _advanceNextRunDate(currentNextRun, frequency, interval);

          // Check if we've passed the end_date.
          final endDateStr = template['end_date'] as String?;
          bool shouldPause = false;
          if (endDateStr != null) {
            try {
              final endDate = DateTime.parse(endDateStr);
              if (newNextRun.isAfter(endDate)) {
                shouldPause = true;
              }
            } catch (_) {}
          }

          // Update the template.
          final updates = <String, dynamic>{
            'next_run_date': newNextRun.toIso8601String().substring(0, 10),
            'generated_count':
                ((template['generated_count'] as num?)?.toInt() ?? 0) + 1,
            'last_generated_invoice_id': invoiceId,
            'updated_at': DateTime.now().toIso8601String(),
          };
          if (shouldPause) {
            updates['status'] = 'paused';
          }
          await db.update('recurring_invoices', updates,
              where: 'id = ?', whereArgs: [template['id']]);
        } else {
          skipped++;
        }
      } catch (e) {
        failed++;
        errors.add('Template ${template['id']}: $e');
        if (kDebugMode) {
          debugPrint('RecurringInvoiceService.processDueTemplates: $e');
        }
      }
    }

    return RecurringGenerationResult(
      generated: generated,
      skipped: skipped,
      failed: failed,
      errors: errors,
    );
  }

  /// Generate a single invoice from a template.
  ///
  /// Returns the generated invoice ID, or null if the template has no
  /// items (nothing to generate).
  Future<String?> _generateInvoiceFromTemplate(
    Map<String, dynamic> template,
    DateTime runDate,
  ) async {
    final templateId = template['id'] as int;

    // Load items.
    final items = await getTemplateItems(templateId);
    if (items.isEmpty) return null;

    // Build the invoice map.
    final invoiceType = template['invoice_type'] as String? ?? 'sale';
    final paymentMechanism =
        template['payment_mechanism'] as String? ?? 'credit';
    final isSale = invoiceType == 'sale' || invoiceType == 'pos';

    // Generate invoice ID.
    final datePrefix = _formatDatePrefix(runDate);
    final seq = await _invoiceRepo.getNextInvoiceSequence(datePrefix, invoiceType);
    final invoiceId = '${invoiceType.toUpperCase()}-$datePrefix-${seq.toString().padLeft(4, '0')}';

    // Compute totals from items.
    double subtotal = 0;
    for (final item in items) {
      subtotal += MoneyHelper.readMoney(item['total_price']);
    }
    final discountAmount = MoneyHelper.readMoney(template['discount_amount']);
    final transportCharges =
        MoneyHelper.readMoney(template['transport_charges']);
    final vatRate = (template['vat_rate'] as num?)?.toDouble() ?? 0.0;
    final taxAmount = (subtotal - discountAmount) * (vatRate / 100);
    final total = subtotal - discountAmount + taxAmount + transportCharges;
    final paidAmount =
        paymentMechanism == 'cash' ? total : 0.0;

    final invoiceMap = <String, dynamic>{
      'id': invoiceId,
      'type': invoiceType,
      'payment_mechanism': paymentMechanism,
      'payment_method': paymentMechanism == 'cash' ? 'cash' : 'credit',
      'is_return': 0,
      'cash_box_id': template['cash_box_id'],
      'customer_id': isSale ? template['customer_id'] : null,
      'supplier_id': !isSale ? template['supplier_id'] : null,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'transport_charges': transportCharges,
      'total': total,
      'paid_amount': paidAmount,
      'remaining': total - paidAmount,
      'status': paidAmount >= total - 0.005 ? 'paid' : 'unpaid',
      'currency': template['currency'] ?? 'YER',
      'exchange_rate': template['exchange_rate'] ?? 1.0,
      'notes': template['notes'],
      'is_posted': 1,
      'created_at': runDate.toIso8601String(),
    };

    // Build items map for saveInvoiceWithJournalEntries.
    final itemsMaps = items.map((item) => <String, dynamic>{
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'total_price': item['total_price'],
          'unit_name': item['unit_name'],
          'conversion_factor': item['conversion_factor'] ?? 1.0,
          'base_quantity': item['base_quantity'],
        }).toList();

    // Generate the invoice via the standard path (posts journal entries,
    // updates stock, updates entity balances).
    await _invoiceRepo.saveInvoiceWithJournalEntries(
      invoiceMap,
      itemsMaps,
      invoiceType: invoiceType,
      paymentMechanism: paymentMechanism,
      isReturn: false,
      cashBoxId: template['cash_box_id'] as int?,
      transportChargesParam: transportCharges,
      paidAmount: paidAmount,
    );

    return invoiceId;
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Advance a date by [interval] units of [frequency].
  DateTime _advanceNextRunDate(
      DateTime current, String frequency, int interval) {
    switch (frequency) {
      case 'daily':
        return current.add(Duration(days: interval));
      case 'weekly':
        return current.add(Duration(days: 7 * interval));
      case 'monthly':
        return DateTime(current.year, current.month + interval, current.day);
      case 'yearly':
        return DateTime(current.year + interval, current.month, current.day);
      default:
        return current.add(Duration(days: 30 * interval));
    }
  }

  /// Format a date as YYYYMMDD (for invoice ID prefix).
  String _formatDatePrefix(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}

/// Result of a recurring invoice generation run.
class RecurringGenerationResult {
  final int generated;
  final int skipped;
  final int failed;
  final List<String> errors;

  const RecurringGenerationResult({
    required this.generated,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  @override
  String toString() =>
      'RecurringGenerationResult(generated: $generated, skipped: $skipped, '
      'failed: $failed, errors: ${errors.length})';
}
