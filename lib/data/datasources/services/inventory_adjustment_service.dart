import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/inventory/unit_conversion_policy.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

class InventoryAdjustmentLine {
  final int productId;
  final double actualQuantity;
  final double conversionFactor;
  final double unitCost;
  final String? notes;

  const InventoryAdjustmentLine({
    required this.productId,
    required this.actualQuantity,
    this.conversionFactor = 1.0,
    required this.unitCost,
    this.notes,
  });
}

class InventoryAdjustmentDraft {
  final String voucherNumber;
  final String date;
  final String? warehouseId;
  final String? description;
  final List<InventoryAdjustmentLine> lines;
  final String currency;

  const InventoryAdjustmentDraft({
    required this.voucherNumber,
    required this.date,
    this.warehouseId,
    this.description,
    required this.lines,
    this.currency = 'YER',
  });
}

/// Auditable inventory counting and adjustment workflow.
///
/// The voucher stores quantities in each product's base unit. Conversion is
/// applied once at draft creation; confirmation re-reads current stock and
/// recalculates the difference inside the transaction to avoid stale counts.
class InventoryAdjustmentService {
  final DatabaseHelper _dbHelper;

  InventoryAdjustmentService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  Future<int> createDraft(InventoryAdjustmentDraft draft) async {
    _validateDraft(draft);
    final db = await _db;
    final parsedDate = DateTime.tryParse(draft.date);
    if (parsedDate == null) throw ArgumentError('Inventory date is invalid.');

    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'inventory_vouchers',
        columns: ['id'],
        where: 'voucher_number = ?',
        whereArgs: [draft.voucherNumber.trim()],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Inventory voucher already exists: ${draft.voucherNumber}');
      }

      final now = DateTime.now().toIso8601String();
      final voucherId = await txn.insert('inventory_vouchers', {
        'voucher_number': draft.voucherNumber.trim(),
        'date': parsedDate.toIso8601String(),
        'warehouse_id': draft.warehouseId,
        'description': draft.description,
        'currency': draft.currency,
        'total_value': 0,
        'status': 'draft',
        'created_at': now,
        'updated_at': now,
      });

      var totalValueMinor = 0;
      for (final line in draft.lines) {
        final productRows = await txn.query(
          'products',
          where: 'id = ? AND is_active = 1',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw StateError('Active stock product was not found: ${line.productId}');
        }
        final product = productRows.single;
        if ((product['track_stock'] as num?)?.toInt() != 1 ||
            (product['product_kind'] as String? ?? 'stock') == 'service') {
          throw StateError('Inventory adjustment requires a stock-tracked product.');
        }
        final actualBaseQuantity = line.actualQuantity == 0
            ? 0.0
            : UnitConversionPolicy.toBaseQuantity(
                quantity: line.actualQuantity,
                factor: line.conversionFactor,
              );
        if (!line.unitCost.isFinite || line.unitCost < 0) {
          throw ArgumentError.value(line.unitCost, 'unitCost');
        }
        final systemQuantity = (product['current_stock'] as num?)?.toDouble() ?? 0;
        final difference = actualBaseQuantity - systemQuantity;
        final totalLineMinor = MoneyHelper.toCents(difference.abs() * line.unitCost);
        totalValueMinor += totalLineMinor;
        await txn.insert('inventory_voucher_items', {
          'voucher_id': voucherId,
          'product_id': line.productId,
          'system_quantity': systemQuantity,
          'actual_quantity': actualBaseQuantity,
          'difference': difference,
          'unit_cost': MoneyHelper.toCents(line.unitCost),
          'total_value': totalLineMinor,
          'notes': _notesWithFactor(line.notes, line.conversionFactor),
        });
      }
      await txn.update(
        'inventory_vouchers',
        {'total_value': totalValueMinor, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [voucherId],
      );
      return voucherId;
    });
  }

  Future<void> confirm(int voucherId) async {
    final db = await _db;
    final initialRows = await db.query(
      'inventory_vouchers',
      columns: ['date', 'status'],
      where: 'id = ?',
      whereArgs: [voucherId],
      limit: 1,
    );
    if (initialRows.isEmpty) throw StateError('Inventory voucher not found: $voucherId');
    final voucherDate = initialRows.single['date'] as String?;
    if (voucherDate == null) throw StateError('Inventory voucher date is missing.');
    await _dbHelper.journal.checkFiscalPeriodOpen(voucherDate);

    await db.transaction((txn) async {
      final voucherRows = await txn.query(
        'inventory_vouchers',
        where: 'id = ?',
        whereArgs: [voucherId],
        limit: 1,
      );
      if (voucherRows.isEmpty) throw StateError('Inventory voucher not found: $voucherId');
      if (voucherRows.single['status'] != 'draft') {
        throw StateError('Only a draft inventory voucher can be confirmed.');
      }
      final items = await txn.query(
        'inventory_voucher_items',
        where: 'voucher_id = ?',
        whereArgs: [voucherId],
        orderBy: 'id ASC',
      );
      if (items.isEmpty) throw StateError('Inventory voucher must contain at least one item.');

      final now = DateTime.now().toIso8601String();
      final journalId = generateUniqueJournalId();
      final inventoryDebits = <int, int>{};
      final inventoryCredits = <int, int>{};
      var totalIncrease = 0;
      var totalDecrease = 0;

      for (final item in items) {
        final productId = (item['product_id'] as num).toInt();
        final actualQuantity = (item['actual_quantity'] as num).toDouble();
        if (!actualQuantity.isFinite || actualQuantity < 0) {
          throw StateError('Actual inventory quantity cannot be negative.');
        }
        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) throw StateError('Product not found: $productId');
        final product = productRows.single;
        final currentStock = (product['current_stock'] as num?)?.toDouble() ?? 0;
        final difference = actualQuantity - currentStock;
        final allowNegative = (product['allow_negative'] as num?)?.toInt() == 1;
        if (!allowNegative && currentStock + difference < -0.000001) {
          throw StateError('Inventory adjustment would create negative stock for $productId.');
        }
        final unitCost = MoneyHelper.readMoney(item['unit_cost']);
        final valueMinor = MoneyHelper.toCents(difference.abs() * unitCost);
        final inventoryAccountId = (product['inventory_account_id'] as num?)?.toInt();
        if (inventoryAccountId == null) {
          throw StateError('Inventory account is missing for product $productId.');
        }

        await txn.rawUpdate(
          'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
          [difference, now, productId],
        );
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'inventory_adjustment',
          'quantity': difference,
          'reference_type': 'inventory_adjustment',
          'reference_id': voucherId.toString(),
          'notes': 'Inventory adjustment voucher ${voucherId.toString()}',
          'unit_cost': MoneyHelper.toCents(unitCost),
          'created_at': now,
        });
        await txn.update(
          'inventory_voucher_items',
          {
            'system_quantity': currentStock,
            'difference': difference,
            'total_value': valueMinor,
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );

        if (difference > 0 && valueMinor > 0) {
          inventoryDebits[inventoryAccountId] =
              (inventoryDebits[inventoryAccountId] ?? 0) + valueMinor;
          totalIncrease += valueMinor;
        } else if (difference < 0 && valueMinor > 0) {
          inventoryCredits[inventoryAccountId] =
              (inventoryCredits[inventoryAccountId] ?? 0) + valueMinor;
          totalDecrease += valueMinor;
        }
      }

      final varianceIncomeId = await _getOrCreateSystemAccount(
        txn,
        code: '4400',
        nameAr: 'إيراد تفاوت الجرد',
        nameEn: 'Inventory variance income',
        type: 'REVENUE',
        balanceType: 'credit',
        now: now,
      );
      final varianceLossId = await _getOrCreateSystemAccount(
        txn,
        code: '5500',
        nameAr: 'خسارة تفاوت الجرد',
        nameEn: 'Inventory variance loss',
        type: 'EXPENSE',
        balanceType: 'debit',
        now: now,
      );

      if (totalIncrease > 0) {
        await _insertTransaction(
          txn,
          accountId: varianceIncomeId,
          journalId: journalId,
          referenceId: voucherId.toString(),
          debit: 0,
          credit: totalIncrease,
          date: voucherDate,
          createdAt: now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          varianceIncomeId,
          0,
          MoneyHelper.fromCents(totalIncrease),
          now,
        );
      }
      if (totalDecrease > 0) {
        await _insertTransaction(
          txn,
          accountId: varianceLossId,
          journalId: journalId,
          referenceId: voucherId.toString(),
          debit: totalDecrease,
          credit: 0,
          date: voucherDate,
          createdAt: now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          varianceLossId,
          MoneyHelper.fromCents(totalDecrease),
          0,
          now,
        );
      }
      for (final entry in inventoryDebits.entries) {
        await _insertTransaction(
          txn,
          accountId: entry.key,
          journalId: journalId,
          referenceId: voucherId.toString(),
          debit: entry.value,
          credit: 0,
          date: voucherDate,
          createdAt: now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          entry.key,
          MoneyHelper.fromCents(entry.value),
          0,
          now,
        );
      }
      for (final entry in inventoryCredits.entries) {
        await _insertTransaction(
          txn,
          accountId: entry.key,
          journalId: journalId,
          referenceId: voucherId.toString(),
          debit: 0,
          credit: entry.value,
          date: voucherDate,
          createdAt: now,
        );
        await _dbHelper.journal.updateAccountBalanceWithJournal(
          txn,
          entry.key,
          0,
          MoneyHelper.fromCents(entry.value),
          now,
        );
      }
      await _dbHelper.journal.validateJournalBalanceInTransaction(txn, journalId);
      await _dbHelper.journal.validateJournalBaseBalanceInTransaction(txn, journalId);
      await txn.update(
        'inventory_vouchers',
        {'status': 'approved', 'updated_at': now},
        where: 'id = ? AND status = ?',
        whereArgs: [voucherId, 'draft'],
      );
    });
  }

  void _validateDraft(InventoryAdjustmentDraft draft) {
    if (draft.voucherNumber.trim().isEmpty || draft.lines.isEmpty) {
      throw ArgumentError('Inventory voucher number and lines are required.');
    }
    if (draft.currency != 'YER') {
      throw ArgumentError('Inventory adjustments must be posted in base currency YER.');
    }
    for (final line in draft.lines) {
      if (line.productId <= 0 || !line.actualQuantity.isFinite || line.actualQuantity < 0) {
        throw ArgumentError('Inventory quantities must be finite and non-negative.');
      }
      UnitConversionPolicy.validateFactor(line.conversionFactor);
    }
  }

  String? _notesWithFactor(String? notes, double factor) {
    final suffix = 'conversion_factor=$factor';
    return notes == null || notes.trim().isEmpty ? suffix : '${notes.trim()} | $suffix';
  }

  Future<int> _getOrCreateSystemAccount(
    Transaction txn, {
    required String code,
    required String nameAr,
    required String nameEn,
    required String type,
    required String balanceType,
    required String now,
  }) async {
    final rows = await txn.query(
      'accounts',
      columns: ['id'],
      where: 'account_code = ? AND currency = ?',
      whereArgs: [code, 'YER'],
      limit: 1,
    );
    if (rows.isNotEmpty) return (rows.single['id'] as num).toInt();
    return txn.insert('accounts', {
      'name_ar': nameAr,
      'name_en': nameEn,
      'account_code': code,
      'account_type': type,
      'balance': 0,
      'currency': 'YER',
      'balance_type': balanceType,
      'is_active': 1,
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> _insertTransaction(
    Transaction txn, {
    required int accountId,
    required int journalId,
    required String referenceId,
    required int debit,
    required int credit,
    required String date,
    required String createdAt,
  }) async {
    await txn.insert('transactions', {
      'account_id': accountId,
      'journal_id': journalId,
      'debit': debit,
      'credit': credit,
      'description': 'Inventory adjustment',
      'date': date,
      'created_at': createdAt,
      'reference_type': 'inventory_adjustment',
      'reference_id': referenceId,
      'currency_code': 'YER',
      'exchange_rate': 1.0,
      'amount_base': debit + credit,
    });
  }
}
