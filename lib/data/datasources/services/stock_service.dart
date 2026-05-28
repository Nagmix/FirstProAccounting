import 'package:sqflite/sqflite.dart';

import '../../../core/utils/money_helper.dart';
import '../database_helper.dart';

class StockService {
  final DatabaseHelper _dbHelper;
  StockService(this._dbHelper);

  Future<Database> get _db => _dbHelper.database;

  // ══════════════════════════════════════════════════════════════
  //  Stock Transfer methods (تحويل مخزني)
  // ══════════════════════════════════════════════════════════════

  /// إدراج تحويل مخزني وتحديث المخزون + تسجيل حركات المخزون
  Future<int> insertStockTransfer(Map<String, dynamic> transferMap) async {
    // H-12: تحقق من الفترة المالية قبل التحويل المخزني
    final transferDate = transferMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(transferDate);

    final db = await _db;
    final productId = transferMap['product_id'] as int;
    final quantity = (transferMap['quantity'] as num).toDouble();
    final fromWarehouseId = transferMap['from_warehouse_id'] as int;
    final toWarehouseId = transferMap['to_warehouse_id'] as int;

    return await db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();

      // إدراج سجل التحويل
      final id = await txn.insert('stock_transfers', transferMap);

      // جلب متوسط تكلفة المنتج المصدر
      final sourceProductRow = await txn.query(
        'products',
        columns: ['average_cost'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final sourceAvgCost = sourceProductRow.isNotEmpty
          ? MoneyHelper.readMoney(sourceProductRow.first['average_cost'])
          : 0.0;

      // خصم الكمية من مخزن المصدر
      final fromProducts = await txn.query(
        'products',
        where: 'id = ? AND warehouse_id = ?',
        whereArgs: [productId, fromWarehouseId],
        limit: 1,
      );

      if (fromProducts.isNotEmpty) {
        final currentStock = (fromProducts.first['current_stock'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'products',
          {
            'current_stock': (currentStock - quantity).clamp(0.0, double.infinity),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      // ── T16: تسجيل حركة مخزون صادر من المصدر ──
      await txn.insert('stock_movements', {
        'product_id': productId,
        'movement_type': 'transfer_out',
        'quantity': -quantity,
        'reference_type': 'transfer',
        'reference_id': id.toString(),
        'notes': 'تحويل من مخزن #$fromWarehouseId إلى مخزن #$toWarehouseId',
        'unit_cost': MoneyHelper.toCents(sourceAvgCost),
        'created_at': now,
      });

      // إضافة الكمية لمخزن الوجهة
      final sourceProduct = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (sourceProduct.isNotEmpty) {
        final productName = sourceProduct.first['name_ar'] as String;
        final toProduct = await txn.query(
          'products',
          where: 'name_ar = ? AND warehouse_id = ?',
          whereArgs: [productName, toWarehouseId],
          limit: 1,
        );

        if (toProduct.isNotEmpty) {
          final currentStock = (toProduct.first['current_stock'] as num?)?.toDouble() ?? 0.0;
          final toProductId = toProduct.first['id'] as int;
          await txn.update(
            'products',
            {
              'current_stock': currentStock + quantity,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [toProductId],
          );
          // ── T16: تسجيل حركة مخزون وارد إلى الوجهة (منتج موجود) ──
          await txn.insert('stock_movements', {
            'product_id': toProductId,
            'movement_type': 'transfer_in',
            'quantity': quantity,
            'reference_type': 'transfer',
            'reference_id': id.toString(),
            'notes': 'تحويل من مخزن #$fromWarehouseId إلى مخزن #$toWarehouseId',
            'unit_cost': MoneyHelper.toCents(sourceAvgCost),
            'created_at': now,
          });
        } else {
          // إنشاء نسخة من المنتج في المخزن الهدف
          final newProduct = Map<String, dynamic>.from(sourceProduct.first);
          newProduct.remove('id');
          newProduct['warehouse_id'] = toWarehouseId;
          newProduct['current_stock'] = quantity;
          newProduct['created_at'] = now;
          newProduct['updated_at'] = now;
          final newProductId = await txn.insert('products', newProduct);
          // ── T16: تسجيل حركة مخزون وارد إلى الوجهة (منتج جديد) ──
          await txn.insert('stock_movements', {
            'product_id': newProductId,
            'movement_type': 'transfer_in',
            'quantity': quantity,
            'reference_type': 'transfer',
            'reference_id': id.toString(),
            'notes': 'تحويل من مخزن #$fromWarehouseId إلى مخزن #$toWarehouseId',
            'unit_cost': MoneyHelper.toCents(sourceAvgCost),
            'created_at': now,
          });
        }
      }

      return id;
    });
  }

  /// جلب جميع التحويلات المخزنية مع أسماء المستودعات والمنتجات
  Future<List<Map<String, dynamic>>> getAllStockTransfers() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT st.*,
        fw.name AS from_warehouse_name,
        tw.name AS to_warehouse_name,
        p.name_ar AS product_name
      FROM stock_transfers st
      LEFT JOIN warehouses fw ON st.from_warehouse_id = fw.id
      LEFT JOIN warehouses tw ON st.to_warehouse_id = tw.id
      LEFT JOIN products p ON st.product_id = p.id
      ORDER BY st.created_at DESC
    ''');
  }

  // ══════════════════════════════════════════════════════════════
  //  Stocktaking methods (جرد المخازن)
  // ══════════════════════════════════════════════════════════════

  /// إنشاء جلسة جرد مع عناصرها
  Future<int> createStocktakingSession(
    Map<String, dynamic> sessionMap,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await _db;
    return await db.transaction<int>((txn) async {
      final sessionId = await txn.insert('stocktaking_sessions', sessionMap);

      for (final item in items) {
        item['session_id'] = sessionId;
        await txn.insert('stocktaking_items', item);
      }

      return sessionId;
    });
  }

  /// إكمال جلسة الجرد وتحديث المخزون الفعلي مع تسجيل الفرق والتدقيق + قيود يومية + حركات مخزون
  Future<void> completeStocktakingSession(int sessionId) async {
    final db = await _db;
    // Check if fiscal period is closed before completing stocktaking
    final sessionRows = await db.query('stocktaking_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (sessionRows.isNotEmpty) {
      final sessionDate = sessionRows.first['date'] as String? ?? DateTime.now().toIso8601String();
      await _dbHelper.journal.checkFiscalPeriodOpen(sessionDate);
    }

    await db.transaction((txn) async {
      // جلب عناصر الجرد
      final items = await txn.query(
        'stocktaking_items',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      // حساب المطابق وغير المطابق
      int matched = 0;
      int mismatched = 0;

      // معرف القيد الموحد لجميع بنود الجرد
      final journalId = DateTime.now().millisecondsSinceEpoch;
      final now = DateTime.now().toIso8601String();

      // ── تحديد حسابات تعديل المخزون (إنشاء تلقائي إذا لم تكن موجودة) ──
      // العملة الافتراضية للجرد هي YER (المنتجات لا تحمل عملة)
      const stocktakingCurrency = 'YER';
      const codeOffset = 0; // YER offset

      // حساب المخزون (1300+offset)
      final inventoryAccountRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1300 + codeOffset).toString(), stocktakingCurrency],
        limit: 1,
      );
      final inventoryAccountId = inventoryAccountRows.isNotEmpty
          ? inventoryAccountRows.first['id'] as int
          : null;

      // حساب خسارة تفاوت الجرد (5400+offset) — مصروف
      final varianceLossCode = (5400 + codeOffset).toString();
      final varianceLossRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [varianceLossCode, stocktakingCurrency],
        limit: 1,
      );
      int? varianceLossAccountId;
      if (varianceLossRows.isNotEmpty) {
        varianceLossAccountId = varianceLossRows.first['id'] as int;
      } else {
        // إنشاء حساب خسارة تفاوت الجرد تلقائياً
        varianceLossAccountId = await txn.insert('accounts', {
          'name_ar': 'خسارة تفاوت الجرد (ر.ي)',
          'name_en': 'Inventory Variance Loss (YER)',
          'account_code': varianceLossCode,
          'account_type': 'EXPENSE',
          'balance': 0,
          'currency': stocktakingCurrency,
          'balance_type': 'debit',
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
      }

      // حساب إيراد تفاوت الجرد (4400+offset) — إيراد
      final varianceIncomeCode = (4400 + codeOffset).toString();
      final varianceIncomeRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [varianceIncomeCode, stocktakingCurrency],
        limit: 1,
      );
      int? varianceIncomeAccountId;
      if (varianceIncomeRows.isNotEmpty) {
        varianceIncomeAccountId = varianceIncomeRows.first['id'] as int;
      } else {
        // إنشاء حساب إيراد تفاوت الجرد تلقائياً
        varianceIncomeAccountId = await txn.insert('accounts', {
          'name_ar': 'إيراد تفاوت الجرد (ر.ي)',
          'name_en': 'Inventory Variance Income (YER)',
          'account_code': varianceIncomeCode,
          'account_type': 'REVENUE',
          'balance': 0,
          'currency': stocktakingCurrency,
          'balance_type': 'credit',
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
      }

      // تحديث المخزون لكل منتج بالكمية الفعلية + حساب وتسجيل الفرق + سجل التدقيق
      for (final item in items) {
        final productId = item['product_id'] as int;
        final systemQuantity = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
        final actualQuantity = (item['actual_quantity'] as num).toDouble();
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;

        // حساب الفرق (variance) بين الكمية بالنظام والكمية الفعلية
        final variance = actualQuantity - systemQuantity;

        // جلب الكمية الحالية وتكلفة المنتج قبل التحديث (للسجل والقيود)
        final productRows = await txn.query(
          'products',
          columns: ['current_stock', 'average_cost'],
          where: 'id = ?',
          whereArgs: [productId],
        );
        final oldStock = productRows.isNotEmpty
            ? (productRows.first['current_stock'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        final averageCost = productRows.isNotEmpty
            ? MoneyHelper.readMoney(productRows.first['average_cost'])
            : 0.0;

        // تحديث المخزون بالكمية الفعلية
        await txn.update(
          'products',
          {
            'current_stock': actualQuantity,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );

        // تحديث حقل الفرق في عنصر الجرد
        await txn.update(
          'stocktaking_items',
          {'variance': variance},
          where: 'id = ?',
          whereArgs: [item['id']],
        );

        if (variance.abs() < 0.005) {
          matched++;
        } else {
          mismatched++;

          // ── T16: تسجيل حركة المخزون ──
          await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'adjustment',
            'quantity': variance,
            'reference_type': 'stocktaking',
            'reference_id': sessionId.toString(),
            'notes': variance > 0 ? 'زيادة جرد' : 'نقص جرد',
            'unit_cost': MoneyHelper.toCents(averageCost),
            'created_at': now,
          });

          // ── إضافة سجل تدقيق لكل منتج تغير مخزونه ──
          await txn.insert('audit_trail', {
            'action': 'stocktake_adjust',
            'table_name': 'products',
            'record_id': productId,
            'record_type': 'stock_adjustment',
            'old_values': oldStock.toString(),
            'new_values': actualQuantity.toString(),
            'user_name': null,
            'shift_id': null,
            'created_at': now,
          });

          // ── T15: إنشاء قيود يومية لتعديلات الجرد ──
          final adjustmentAmount = variance * averageCost;
          if (adjustmentAmount.abs() >= 0.005) {
            if (variance > 0) {
              // زيادة مخزون: مدين = المخزون، دائن = إيراد تفاوت الجرد
              if (inventoryAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(adjustmentAmount),
                  'credit': 0,
                  'description': 'تعديل جرد زيادة - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, adjustmentAmount, 0.0, now);
              }
              if (varianceIncomeAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': varianceIncomeAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(adjustmentAmount),
                  'description': 'تعديل جرد زيادة - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, varianceIncomeAccountId, 0.0, adjustmentAmount, now);
              }
            } else {
              // نقص مخزون: مدين = خسارة تفاوت الجرد، دائن = المخزون
              final lossAmount = adjustmentAmount.abs();
              if (varianceLossAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': varianceLossAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(lossAmount),
                  'credit': 0,
                  'description': 'تعديل جرد نقص - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, varianceLossAccountId, lossAmount, 0.0, now);
              }
              if (inventoryAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(lossAmount),
                  'description': 'تعديل جرد نقص - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, lossAmount, now);
              }
            }
          }
        }
      }

      // تحديث حالة الجرد إلى مكتمل
      await txn.update(
        'stocktaking_sessions',
        {
          'status': 'completed',
          'matched_items': matched,
          'mismatched_items': mismatched,
          'total_items': items.length,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  /// جلب جميع جلسات الجرد
  Future<List<Map<String, dynamic>>> getStocktakingSessions() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT ss.*, w.name AS warehouse_name
      FROM stocktaking_sessions ss
      LEFT JOIN warehouses w ON ss.warehouse_id = w.id
      ORDER BY ss.created_at DESC
    ''');
  }

  /// جلب عناصر جلسة الجرد
  Future<List<Map<String, dynamic>>> getStocktakingItems(int sessionId) async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT si.*, p.name_ar AS product_name, p.current_stock
      FROM stocktaking_items si
      LEFT JOIN products p ON si.product_id = p.id
      WHERE si.session_id = ?
      ORDER BY p.name_ar ASC
    ''', [sessionId]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Inventory Voucher Methods (سندات الجرد) - v22
  // ══════════════════════════════════════════════════════════════

  Future<String> getNextInventoryVoucherNumber() async {
    final db = await _db;
    final now = DateTime.now();
    final prefix = 'IV-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM inventory_vouchers WHERE voucher_number LIKE ?",
      ['$prefix%'],
    );
    final count = (result.first['cnt'] as num?)?.toInt() ?? 0;
    return '$prefix-${(count + 1).toString().padLeft(4, '0')}';
  }

  Future<int> insertInventoryVoucher(
    Map<String, dynamic> voucherMap,
    List<Map<String, dynamic>> items,
  ) async {
    // Check if fiscal period is closed before creating inventory voucher
    final ivDate = voucherMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _dbHelper.journal.checkFiscalPeriodOpen(ivDate);

    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Determine if stock & journal entries should be applied immediately.
    // Draft vouchers defer stock changes and journal entries until confirmed.
    final status = voucherMap['status'] as String? ?? 'approved';
    final applyStockAndJournal = status == 'approved';

    int voucherId = 0;
    await db.transaction((txn) async {
      // Insert voucher header
      voucherId = await txn.insert('inventory_vouchers', {
        ...voucherMap,
        'created_at': voucherMap['created_at'] as String? ?? now,
        'updated_at': voucherMap['updated_at'] as String? ?? now,
      });

      double totalIncreaseValue = 0.0;
      double totalDecreaseValue = 0.0;

      for (final item in items) {
        final productId = item['product_id'] as int;
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;
        final unitCost = MoneyHelper.readMoney(item['unit_cost']);
        final totalValue = difference.abs() * unitCost;

        // Insert voucher item
        await txn.insert('inventory_voucher_items', {
          'voucher_id': voucherId,
          'product_id': productId,
          'system_quantity': (item['system_quantity'] as num?)?.toDouble() ?? 0.0,
          'actual_quantity': (item['actual_quantity'] as num?)?.toDouble() ?? 0.0,
          'difference': difference,
          'unit_cost': MoneyHelper.toCents(unitCost),
          'total_value': MoneyHelper.toCents(totalValue),
          'notes': item['notes'] as String?,
        });

        // Only update product stock when voucher is approved
        if (applyStockAndJournal) {
          final product = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
          if (product.isNotEmpty) {
            final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
            await txn.update('products', {
              'current_stock': currentStock + difference,
              'updated_at': now,
            }, where: 'id = ?', whereArgs: [productId]);
          }

          // Log stock movement
          await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'adjustment',
            'quantity': difference,
            'reference_type': 'inventory_voucher',
            'reference_id': voucherId.toString(),
            'notes': 'سند جرد - تعديل المخزون',
            'unit_cost': MoneyHelper.toCents(unitCost),
            'created_at': now,
          });
        }

        if (difference > 0) {
          totalIncreaseValue += totalValue;
        } else if (difference < 0) {
          totalDecreaseValue += totalValue;
        }
      }

      // Update voucher total value
      await txn.update('inventory_vouchers', {
        'total_value': totalIncreaseValue + totalDecreaseValue,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [voucherId]);

      // Only create journal entries when voucher is approved
      if (applyStockAndJournal) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        // Get currency for this voucher
        final currency = voucherMap['currency'] as String? ?? 'YER';

        // Find accounts by code and currency
        // Inventory account code = 1300 + offset
        final inventoryAccount = await _dbHelper.journal.findAccountByCodeAndCurrency(txn, '1300', currency);
        // COGS account code = 3200 + offset
        final cogsAccount = await _dbHelper.journal.findAccountByCodeAndCurrency(txn, '3200', currency);

      // Journal entries for inventory increase (difference > 0)
      if (totalIncreaseValue > 0) {
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          // Debit Inventory (asset increase)
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(totalIncreaseValue),
            'credit': 0,
            'description': 'سند جرد - زيادة مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccId, totalIncreaseValue, 0.0, now);
        }
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          // Credit COGS (reducing cost of goods sold)
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(totalIncreaseValue),
            'description': 'سند جرد - زيادة مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccId, 0.0, totalIncreaseValue, now);
        }
      }

      // Journal entries for inventory decrease (difference < 0)
      if (totalDecreaseValue > 0) {
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          // Debit COGS (increasing cost)
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(totalDecreaseValue),
            'credit': 0,
            'description': 'سند جرد - نقص مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccId, totalDecreaseValue, 0.0, now);
        }
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          // Credit Inventory (asset decrease)
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(totalDecreaseValue),
            'description': 'سند جرد - نقص مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccId, 0.0, totalDecreaseValue, now);
        }
      }
      } // end if (applyStockAndJournal)
    });

    return voucherId;
  }

  Future<List<Map<String, dynamic>>> getInventoryVouchers({String? searchQuery}) async {
    final db = await _db;
    String query = '''
      SELECT iv.*, w.name as warehouse_name
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
    ''';
    List<dynamic> args = [];
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query += ' WHERE iv.voucher_number LIKE ? OR iv.description LIKE ? OR w.name LIKE ?';
      final likeQuery = '%$searchQuery%';
      args = [likeQuery, likeQuery, likeQuery];
    }
    query += ' ORDER BY iv.created_at DESC';
    return await db.rawQuery(query, args);
  }

  Future<Map<String, dynamic>?> getInventoryVoucherDetails(int voucherId) async {
    final db = await _db;
    final voucherResult = await db.rawQuery('''
      SELECT iv.*, w.name as warehouse_name
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
      WHERE iv.id = ?
    ''', [voucherId]);
    if (voucherResult.isEmpty) return null;

    final items = await db.rawQuery('''
      SELECT ivi.*, p.name_ar as product_name, p.barcode, p.item_code
      FROM inventory_voucher_items ivi
      LEFT JOIN products p ON ivi.product_id = p.id
      WHERE ivi.voucher_id = ?
      ORDER BY ivi.id
    ''', [voucherId]);

    return {
      ...voucherResult.first,
      'items': items,
    };
  }

  /// Get all inventory vouchers with warehouse name and item count.
  /// Returns aliases `voucher_date` → iv.date, `total_diff_value` → iv.total_value
  /// so callers can use either the raw column names or the aliases.
  Future<List<Map<String, dynamic>>> getAllInventoryVouchers() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT
        iv.*,
        iv.date AS voucher_date,
        iv.total_value AS total_diff_value,
        w.name AS warehouse_name,
        (SELECT COUNT(*) FROM inventory_voucher_items ivi WHERE ivi.voucher_id = iv.id) AS item_count
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
      ORDER BY iv.created_at DESC
    ''');
  }

  /// Delete an inventory voucher and its items.
  /// If the voucher was previously approved, the stock changes are reversed
  /// (product current_stock is adjusted back) and a reversal stock movement
  /// is logged for each item.
  Future<void> deleteInventoryVoucher(int id) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    // Pre-check: verify the inventory voucher's date is not in a closed fiscal period
    final ivPreCheck = await db.query('inventory_vouchers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (ivPreCheck.isNotEmpty) {
      final preCheckDate = ivPreCheck.first['date'] as String? ?? now;
      await _dbHelper.journal.checkFiscalPeriodOpen(preCheckDate);
    }

    await db.transaction((txn) async {
      // Fetch the voucher to check its status
      final voucherRows = await txn.query(
        'inventory_vouchers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (voucherRows.isEmpty) return;

      final status = voucherRows.first['status'] as String? ?? 'draft';

      // If the voucher was approved, reverse all stock changes
      if (status == 'approved') {
        final items = await txn.query(
          'inventory_voucher_items',
          where: 'voucher_id = ?',
          whereArgs: [id],
        );

        for (final item in items) {
          final productId = item['product_id'] as int;
          final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;
          final unitCost = MoneyHelper.readMoney(item['unit_cost']);

          // Reverse: subtract the difference that was added
          final product = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (product.isNotEmpty) {
            final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
            await txn.update(
              'products',
              {
                'current_stock': currentStock - difference,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [productId],
            );
          }

          // Log a reversal stock movement
          await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'adjustment',
            'quantity': -difference, // reverse the original adjustment
            'reference_type': 'inventory_voucher',
            'reference_id': id.toString(),
            'notes': 'حذف سند جرد - عكس تعديل المخزون',
            'unit_cost': MoneyHelper.toCents(unitCost),
            'created_at': now,
          });
        }

        // Reverse journal entries for this voucher
        // Find transactions that were created with a journal_id pattern from this voucher
        final voucherDate = voucherRows.first['date'] as String? ?? now.substring(0, 10);
        final voucherCurrency = voucherRows.first['currency'] as String? ?? 'YER';
        final voucherDesc = 'سند جرد';

        // Find and reverse related transactions by description pattern and date
        final relatedTxns = await txn.rawQuery(
          '''SELECT * FROM transactions
             WHERE date = ? AND description LIKE ?
             ORDER BY id DESC''',
          [voucherDate, '%$voucherDesc%'],
        );

        // Only reverse the exact number of transactions this voucher created (max 4)
        // Insertions were: up to 2 for increase, up to 2 for decrease
        final voucherNumber = voucherRows.first['voucher_number'] as String? ?? '';
        final exactTxns = relatedTxns.where((t) {
          final desc = (t['description'] as String?) ?? '';
          return desc.contains(voucherNumber) || desc.contains('سند جرد');
        }).take(4).toList();

        for (final txnRow in exactTxns) {
          final accId = txnRow['account_id'] as int;
          final debit = MoneyHelper.readMoney(txnRow['debit']);
          final credit = MoneyHelper.readMoney(txnRow['credit']);

          // Reverse: swap debit and credit
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': DateTime.now().millisecondsSinceEpoch,
            'debit': MoneyHelper.toCents(credit),
            'credit': MoneyHelper.toCents(debit),
            'description': 'عكس قيد - حذف سند جرد رقم $voucherNumber',
            'date': now.substring(0, 10),
            'created_at': now,
          });

          // Reverse the account balance
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, accId, credit, debit, now);
        }
      }

      // Delete items first (though CASCADE should handle it)
      await txn.delete(
        'inventory_voucher_items',
        where: 'voucher_id = ?',
        whereArgs: [id],
      );

      // Delete the voucher
      await txn.delete(
        'inventory_vouchers',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Confirm (approve) a draft inventory voucher.
  /// Updates status to 'approved', adjusts product stock quantities,
  /// creates stock movements, and generates journal entries.
  Future<void> confirmInventoryVoucher(int id) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Fetch the voucher
      final voucherRows = await txn.query(
        'inventory_vouchers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (voucherRows.isEmpty) {
        throw Exception('سند الجرد غير موجود');
      }

      final currentStatus = voucherRows.first['status'] as String?;
      if (currentStatus != 'draft') {
        throw Exception('لا يمكن تأكيد سند جرد بحالة "$currentStatus" — يجب أن يكون مسودة');
      }

      final currency = voucherRows.first['currency'] as String? ?? 'YER';
      final voucherDate = voucherRows.first['date'] as String? ?? now.substring(0, 10);

      // Fetch items
      final items = await txn.query(
        'inventory_voucher_items',
        where: 'voucher_id = ?',
        whereArgs: [id],
      );

      double totalIncreaseValue = 0.0;
      double totalDecreaseValue = 0.0;

      for (final item in items) {
        final productId = item['product_id'] as int;
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;
        final unitCost = MoneyHelper.readMoney(item['unit_cost']);
        final totalValue = difference.abs() * unitCost;

        // Update product stock
        final product = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (product.isNotEmpty) {
          final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'products',
            {
              'current_stock': currentStock + difference,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [productId],
          );
        }

        // Create stock movement
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'adjustment',
          'quantity': difference,
          'reference_type': 'inventory_voucher',
          'reference_id': id.toString(),
          'notes': 'تأكيد سند جرد - تعديل المخزون',
          'unit_cost': MoneyHelper.toCents(unitCost),
          'created_at': now,
        });

        if (difference > 0) {
          totalIncreaseValue += totalValue;
        } else if (difference < 0) {
          totalDecreaseValue += totalValue;
        }
      }

      // Find accounts by code and currency
      final inventoryAccount = await _dbHelper.journal.findAccountByCodeAndCurrency(txn, '1300', currency);
      final cogsAccount = await _dbHelper.journal.findAccountByCodeAndCurrency(txn, '3200', currency);

      final voucherNumber = voucherRows.first['voucher_number'] as String? ?? '';

      // Journal entries for inventory increase (difference > 0)
      if (totalIncreaseValue > 0) {
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(totalIncreaseValue),
            'credit': 0,
            'description': 'تأكيد سند جرد $voucherNumber - زيادة مخزون',
            'date': voucherDate,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccId, totalIncreaseValue, 0.0, now);
        }
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(totalIncreaseValue),
            'description': 'تأكيد سند جرد $voucherNumber - زيادة مخزون',
            'date': voucherDate,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccId, 0.0, totalIncreaseValue, now);
        }
      }

      // Journal entries for inventory decrease (difference < 0)
      if (totalDecreaseValue > 0) {
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(totalDecreaseValue),
            'credit': 0,
            'description': 'تأكيد سند جرد $voucherNumber - نقص مخزون',
            'date': voucherDate,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, cogsAccId, totalDecreaseValue, 0.0, now);
        }
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(totalDecreaseValue),
            'description': 'تأكيد سند جرد $voucherNumber - نقص مخزون',
            'date': voucherDate,
            'created_at': now,
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(txn, invAccId, 0.0, totalDecreaseValue, now);
        }
      }

      // Update voucher status to approved
      await txn.update(
        'inventory_vouchers',
        {
          'status': 'approved',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
