import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/utils/journal_id_helper.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

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
    final transferDate =
        transferMap['date'] as String? ?? DateTime.now().toIso8601String();
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

      // جلب تكلفة المنتج المصدر — A-09: استخدام محرك التكلفة لـ FIFO/LIFO
      final sourceProductRow = await txn.query(
        'products',
        columns: ['average_cost', 'costing_method', 'cost_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      double sourceAvgCost;
      if (sourceProductRow.isNotEmpty) {
        final costingMethodStr =
            sourceProductRow.first['costing_method'] as String? ??
                'weighted_average';
        // A-09: For FIFO/LIFO products, use the costing engine for actual cost
        if (costingMethodStr != 'weighted_average') {
          try {
            final avgCost =
                MoneyHelper.readMoney(sourceProductRow.first['average_cost']);
            sourceAvgCost = avgCost > 0
                ? avgCost
                : MoneyHelper.readMoney(sourceProductRow.first['cost_price']);
          } catch (_) {
            sourceAvgCost =
                MoneyHelper.readMoney(sourceProductRow.first['average_cost']);
          }
        } else {
          sourceAvgCost =
              MoneyHelper.readMoney(sourceProductRow.first['average_cost']);
        }
      } else {
        sourceAvgCost = 0.0;
      }

      // خصم الكمية من مخزن المصدر
      final fromProducts = await txn.query(
        'products',
        where: 'id = ? AND warehouse_id = ?',
        whereArgs: [productId, fromWarehouseId],
        limit: 1,
      );

      if (fromProducts.isNotEmpty) {
        final currentStock =
            (fromProducts.first['current_stock'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'products',
          {
            'current_stock':
                (currentStock - quantity).clamp(0.0, double.infinity),
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
          final currentStock =
              (toProduct.first['current_stock'] as num?)?.toDouble() ?? 0.0;
          final toProductId = toProduct.first['id'] as int;
          final newStock = currentStock + quantity;

          // ── W-05: إعادة حساب متوسط التكلفة المرجح في المستودع الوجهة ──
          // حسب IAS 2: تكلفة المخزون تشمل كل تكاليف الشراء
          double toAvgCost =
              MoneyHelper.readMoney(toProduct.first['average_cost']);
          double newAvgCost;
          if (currentStock > 0 && toAvgCost > 0) {
            // المتوسط المرجح = (رصيد حالي × متوسط تكلفة حالي + كمية محولة × متوسط تكلفة مصدر) ÷ الرصيد الجديد
            final totalValue =
                (currentStock * toAvgCost) + (quantity * sourceAvgCost);
            newAvgCost = totalValue / newStock;
          } else {
            // لا يوجد مخزون مسبق: نستخدم تكلفة المصدر
            newAvgCost = sourceAvgCost;
          }

          await txn.update(
            'products',
            {
              'current_stock': newStock,
              'average_cost': MoneyHelper.toCents(newAvgCost),
              'cost_price': MoneyHelper.toCents(newAvgCost),
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
          // P-08: Create a copy of the product in the destination warehouse
          // but modify item_code and barcode to avoid duplicates across warehouses
          final newProduct = Map<String, dynamic>.from(sourceProduct.first);
          newProduct.remove('id');
          newProduct['warehouse_id'] = toWarehouseId;
          newProduct['current_stock'] = quantity;
          newProduct['created_at'] = now;
          newProduct['updated_at'] = now;
          // P-08: Suffix item_code and barcode to avoid conflicts with source warehouse product
          final whSuffix = '-W$toWarehouseId';
          if (newProduct['item_code'] != null) {
            newProduct['item_code'] = '${newProduct['item_code']}$whSuffix';
          }
          if (newProduct['barcode'] != null &&
              (newProduct['barcode'] as String).isNotEmpty) {
            newProduct['barcode'] = '${newProduct['barcode']}$whSuffix';
          }
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

      // ── C-08: إنشاء قيود يومية للتحويل المخزني ──
      final transferValue = quantity * sourceAvgCost;
      final transferCurrency = (transferMap['currency'] as String?) ?? 'YER';

      if (transferValue.abs() >= 0.005) {
        final journalId = generateUniqueJournalId();
        final codeOffset =
            transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final transferRate = await _getExchangeRate(txn, transferCurrency);

        // محاولة استخدام حساب المخزون المرتبط بالمستودع، أو الافتراضي
        int? fromInventoryAccountId;
        int? toInventoryAccountId;

        final fromWarehouseRow = await txn.query('warehouses',
            where: 'id = ?', whereArgs: [fromWarehouseId], limit: 1);
        if (fromWarehouseRow.isNotEmpty) {
          fromInventoryAccountId =
              fromWarehouseRow.first['inventory_account_id'] as int?;
        }
        fromInventoryAccountId ??= await _getDefaultInventoryAccountId(
            txn, codeOffset, transferCurrency);

        final toWarehouseRow = await txn.query('warehouses',
            where: 'id = ?', whereArgs: [toWarehouseId], limit: 1);
        if (toWarehouseRow.isNotEmpty) {
          toInventoryAccountId =
              toWarehouseRow.first['inventory_account_id'] as int?;
        }
        toInventoryAccountId ??= await _getDefaultInventoryAccountId(
            txn, codeOffset, transferCurrency);

        // إذا كان المستودعان مرتبطين بنفس الحساب، لا حاجة لقيود تحويل
        if (fromInventoryAccountId != null &&
            toInventoryAccountId != null &&
            fromInventoryAccountId != toInventoryAccountId) {
          // مدين: حساب المخزون الوجهة (زيادة أصول)
          await txn.insert('transactions', {
            'account_id': toInventoryAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(transferValue),
            'credit': 0,
            'description':
                'تحويل مخزني من مستودع #$fromWarehouseId إلى #$toWarehouseId - منتج #$productId',
            'date': now,
            'created_at': now,
            'currency_code': transferCurrency,
            'exchange_rate': transferCurrency == 'YER' ? 1.0 : transferRate,
            'amount_base':
                (MoneyHelper.toCents(transferValue) * transferRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, toInventoryAccountId, transferValue, 0.0, now);

          // دائن: حساب المخزون المصدر (نقص أصول)
          await txn.insert('transactions', {
            'account_id': fromInventoryAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(transferValue),
            'description':
                'تحويل مخزني من مستودع #$fromWarehouseId إلى #$toWarehouseId - منتج #$productId',
            'date': now,
            'created_at': now,
            'currency_code': transferCurrency,
            'exchange_rate': transferCurrency == 'YER' ? 1.0 : transferRate,
            'amount_base':
                (MoneyHelper.toCents(transferValue) * transferRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, fromInventoryAccountId, 0.0, transferValue, now);
        }
      }

      // ── W-05: إعادة حساب متوسط التكلفة المرجح في المستودع الوجهة ──
      // تم التعامل معه كجزء من إنشاء المنتج في الوجهة أعلاه
      // حيث يحتفظ بنفس التكلفة من المصدر

      return id;
    });
  }

  /// Helper: Get default inventory account ID by code offset and currency
  Future<int?> _getDefaultInventoryAccountId(
      Transaction txn, int codeOffset, String currency) async {
    final accountCode = (1300 + codeOffset).toString();
    final rows = await txn.query('accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [accountCode, currency],
        limit: 1);
    return rows.isNotEmpty ? rows.first['id'] as int : null;
  }

  /// Helper: Look up exchange rate from currencies table for a given currency code.
  /// Returns 1.0 for YER, falls back to hardcoded rates if not found in DB.
  Future<double> _getExchangeRate(
      DatabaseExecutor executor, String currency) async {
    if (currency == 'YER') return 1.0;
    try {
      final rows = await executor.query('currencies',
          where: 'code = ?', whereArgs: [currency], limit: 1);
      if (rows.isNotEmpty) {
        return (rows.first['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      }
    } catch (e) {
      // B-8: لا نبتلع الأخطاء بصمت في كود مالي — سجّل ثم تابع المسار الاحتياطي
      debugPrint(
          'StockService._getExchangeRate($currency) فشل، استخدام السعر الاحتياطي: $e');
    }
    // Fallback defaults
    if (currency == 'SAR') return 140.0;
    if (currency == 'USD') return 530.0;
    return 1.0;
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
    final sessionRows = await db.query('stocktaking_sessions',
        where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (sessionRows.isNotEmpty) {
      final sessionDate = sessionRows.first['date'] as String? ??
          DateTime.now().toIso8601String();
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
      final journalId = generateUniqueJournalId();
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

      // حساب خسارة تفاوت الجرد (5500+offset) — مصروف
      final varianceLossCode = (5500 + codeOffset).toString();
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
        final systemQuantity =
            (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
        final actualQuantity = (item['actual_quantity'] as num).toDouble();
        // ignore: unused_local_variable
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;

        // حساب الفرق (variance) بين الكمية بالنظام والكمية الفعلية
        final variance = actualQuantity - systemQuantity;

        // جلب الكمية الحالية وتكلفة المنتج قبل التحديث (للسجل والقيود)
        // P-09: Also fetch product-specific inventory account
        final productRows = await txn.query(
          'products',
          columns: ['current_stock', 'average_cost', 'inventory_account_id'],
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
          // P-09: Use product-specific inventory account when available
          final adjustmentAmount = variance * averageCost;
          // Resolve effective inventory account: product-specific > default
          final productInventoryAccountId = productRows.isNotEmpty
              ? productRows.first['inventory_account_id'] as int?
              : null;
          final effectiveInventoryAccountId =
              productInventoryAccountId ?? inventoryAccountId;
          if (adjustmentAmount.abs() >= 0.005) {
            if (variance > 0) {
              // زيادة مخزون: مدين = المخزون، دائن = إيراد تفاوت الجرد
              if (effectiveInventoryAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': effectiveInventoryAccountId,
                  'journal_id': journalId,
                  'debit': MoneyHelper.toCents(adjustmentAmount),
                  'credit': 0,
                  'description':
                      'تعديل جرد زيادة - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                  'currency_code': 'YER',
                  'exchange_rate': 1.0,
                  'amount_base': MoneyHelper.toCents(adjustmentAmount),
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(txn,
                    effectiveInventoryAccountId, adjustmentAmount, 0.0, now);
              }
              await txn.insert('transactions', {
                'account_id': varianceIncomeAccountId,
                'journal_id': journalId,
                'debit': 0,
                'credit': MoneyHelper.toCents(adjustmentAmount),
                'description':
                    'تعديل جرد زيادة - منتج #$productId - جلسة #$sessionId',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'amount_base': MoneyHelper.toCents(adjustmentAmount),
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, varianceIncomeAccountId, 0.0, adjustmentAmount, now);
            } else {
              // نقص مخزون: مدين = خسارة تفاوت الجرد، دائن = المخزون
              final lossAmount = adjustmentAmount.abs();
              await txn.insert('transactions', {
                'account_id': varianceLossAccountId,
                'journal_id': journalId,
                'debit': MoneyHelper.toCents(lossAmount),
                'credit': 0,
                'description':
                    'تعديل جرد نقص - منتج #$productId - جلسة #$sessionId',
                'date': now,
                'created_at': now,
                'currency_code': 'YER',
                'exchange_rate': 1.0,
                'amount_base': MoneyHelper.toCents(lossAmount),
              });
              await _dbHelper.journal.updateAccountBalanceWithJournal(
                  txn, varianceLossAccountId, lossAmount, 0.0, now);
              if (effectiveInventoryAccountId != null) {
                await txn.insert('transactions', {
                  'account_id': effectiveInventoryAccountId,
                  'journal_id': journalId,
                  'debit': 0,
                  'credit': MoneyHelper.toCents(lossAmount),
                  'description':
                      'تعديل جرد نقص - منتج #$productId - جلسة #$sessionId',
                  'date': now,
                  'created_at': now,
                  'currency_code': 'YER',
                  'exchange_rate': 1.0,
                  'amount_base': MoneyHelper.toCents(lossAmount),
                });
                await _dbHelper.journal.updateAccountBalanceWithJournal(
                    txn, effectiveInventoryAccountId, 0.0, lossAmount, now);
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
    final ivDate =
        voucherMap['date'] as String? ?? DateTime.now().toIso8601String();
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
      voucherId = await txn.insert(
          'inventory_vouchers',
          MoneyHelper.toCentsMap({
            ...voucherMap,
            'created_at': voucherMap['created_at'] as String? ?? now,
            'updated_at': voucherMap['updated_at'] as String? ?? now,
          }, [
            'total_value'
          ]));

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
          'system_quantity':
              (item['system_quantity'] as num?)?.toDouble() ?? 0.0,
          'actual_quantity':
              (item['actual_quantity'] as num?)?.toDouble() ?? 0.0,
          'difference': difference,
          'unit_cost': MoneyHelper.toCents(unitCost),
          'total_value': MoneyHelper.toCents(totalValue),
          'notes': item['notes'] as String?,
        });

        // Only update product stock when voucher is approved
        if (applyStockAndJournal) {
          final product = await txn.query('products',
              where: 'id = ?', whereArgs: [productId], limit: 1);
          if (product.isNotEmpty) {
            final currentStock =
                (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
            await txn.update(
                'products',
                {
                  'current_stock': currentStock + difference,
                  'updated_at': now,
                },
                where: 'id = ?',
                whereArgs: [productId]);
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

      // ── M-09: تحديث إجمالي قيمة السند بالفرق الصافي بدل المجموع ──
      await txn.update(
          'inventory_vouchers',
          {
            'total_value':
                MoneyHelper.toCents(totalIncreaseValue - totalDecreaseValue),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [voucherId]);

      // Only create journal entries when voucher is approved
      if (applyStockAndJournal) {
        final journalId = generateUniqueJournalId();
        // Get currency for this voucher
        final currency = voucherMap['currency'] as String? ?? 'YER';
        final voucherRate = await _getExchangeRate(txn, currency);

        // ── C-05: استخدام حسابات تفاوت الجرد بدل COGS ──
        // COGS يجب أن يعكس تكلفة البضاعة المباعة فقط وليس فروقات الجرد
        final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);

        // حساب المخزون (1300+offset)
        final inventoryAccount = await _dbHelper.journal
            .findAccountByCodeAndCurrency(txn, '1300', currency);

        // حساب إيراد تفاوت الجرد (4400+offset)
        final varianceIncomeCode = (4400 + codeOffset).toString();
        final varianceIncomeRows = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [varianceIncomeCode, currency],
          limit: 1,
        );
        int? varianceIncomeAccountId;
        if (varianceIncomeRows.isNotEmpty) {
          varianceIncomeAccountId = varianceIncomeRows.first['id'] as int;
        } else {
          // إنشاء حساب إيراد تفاوت الجرد تلقائياً
          varianceIncomeAccountId = await txn.insert('accounts', {
            'name_ar': 'إيراد تفاوت الجرد ($currency)',
            'name_en': 'Inventory Variance Income ($currency)',
            'account_code': varianceIncomeCode,
            'account_type': 'REVENUE',
            'balance': 0,
            'currency': currency,
            'balance_type': 'credit',
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        // حساب خسارة تفاوت الجرد (5500+offset)
        final varianceLossCode = (5500 + codeOffset).toString();
        final varianceLossRows = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [varianceLossCode, currency],
          limit: 1,
        );
        int? varianceLossAccountId;
        if (varianceLossRows.isNotEmpty) {
          varianceLossAccountId = varianceLossRows.first['id'] as int;
        } else {
          // إنشاء حساب خسارة تفاوت الجرد تلقائياً
          varianceLossAccountId = await txn.insert('accounts', {
            'name_ar': 'خسارة تفاوت الجرد ($currency)',
            'name_en': 'Inventory Variance Loss ($currency)',
            'account_code': varianceLossCode,
            'account_type': 'EXPENSE',
            'balance': 0,
            'currency': currency,
            'balance_type': 'debit',
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }

        // C-05: قيود زيادة المخزون — مدين المخزون / دائن إيراد تفاوت الجرد
        if (totalIncreaseValue > 0) {
          if (inventoryAccount != null) {
            final invAccId = inventoryAccount['id'] as int;
            await txn.insert('transactions', {
              'account_id': invAccId,
              'journal_id': journalId,
              'debit': MoneyHelper.toCents(totalIncreaseValue),
              'credit': 0,
              'description': 'سند جرد - زيادة مخزون',
              'date': voucherMap['date'] as String? ?? now.substring(0, 10),
              'created_at': now,
              'currency_code': currency,
              'exchange_rate': currency == 'YER' ? 1.0 : voucherRate,
              'amount_base':
                  (MoneyHelper.toCents(totalIncreaseValue) * voucherRate)
                      .round(),
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, invAccId, totalIncreaseValue, 0.0, now);
          }
          await txn.insert('transactions', {
            'account_id': varianceIncomeAccountId,
            'journal_id': journalId,
            'debit': 0,
            'credit': MoneyHelper.toCents(totalIncreaseValue),
            'description': 'سند جرد - زيادة مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : voucherRate,
            'amount_base':
                (MoneyHelper.toCents(totalIncreaseValue) * voucherRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, varianceIncomeAccountId, 0.0, totalIncreaseValue, now);
        }

        // C-05: قيود نقص المخزون — مدين خسارة تفاوت الجرد / دائن المخزون
        if (totalDecreaseValue > 0) {
          await txn.insert('transactions', {
            'account_id': varianceLossAccountId,
            'journal_id': journalId,
            'debit': MoneyHelper.toCents(totalDecreaseValue),
            'credit': 0,
            'description': 'سند جرد - نقص مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : voucherRate,
            'amount_base':
                (MoneyHelper.toCents(totalDecreaseValue) * voucherRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, varianceLossAccountId, totalDecreaseValue, 0.0, now);
          if (inventoryAccount != null) {
            final invAccId = inventoryAccount['id'] as int;
            await txn.insert('transactions', {
              'account_id': invAccId,
              'journal_id': journalId,
              'debit': 0,
              'credit': MoneyHelper.toCents(totalDecreaseValue),
              'description': 'سند جرد - نقص مخزون',
              'date': voucherMap['date'] as String? ?? now.substring(0, 10),
              'created_at': now,
              'currency_code': currency,
              'exchange_rate': currency == 'YER' ? 1.0 : voucherRate,
              'amount_base':
                  (MoneyHelper.toCents(totalDecreaseValue) * voucherRate)
                      .round(),
            });
            await _dbHelper.journal.updateAccountBalanceWithJournal(
                txn, invAccId, 0.0, totalDecreaseValue, now);
          }
        }
      } // end if (applyStockAndJournal)
    });

    return voucherId;
  }

  Future<List<Map<String, dynamic>>> getInventoryVouchers(
      {String? searchQuery}) async {
    final db = await _db;
    String query = '''
      SELECT iv.*, w.name as warehouse_name
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
    ''';
    List<dynamic> args = [];
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query +=
          ' WHERE iv.voucher_number LIKE ? OR iv.description LIKE ? OR w.name LIKE ?';
      final likeQuery = '%$searchQuery%';
      args = [likeQuery, likeQuery, likeQuery];
    }
    query += ' ORDER BY iv.created_at DESC';
    return await db.rawQuery(query, args);
  }

  Future<Map<String, dynamic>?> getInventoryVoucherDetails(
      int voucherId) async {
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
    final ivPreCheck = await db.query('inventory_vouchers',
        where: 'id = ?', whereArgs: [id], limit: 1);
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
            final currentStock =
                (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
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

        // ── W-08: عكس القيود بدقة باستخدام رقم السند ──
        // البحث عن القيود المرتبطة برقم السند بالضبط بدل التاريخ والوصف
        final voucherNumber =
            voucherRows.first['voucher_number'] as String? ?? '';
        final deleteCurrency =
            voucherRows.first['currency'] as String? ?? 'YER';
        final deleteRate = await _getExchangeRate(txn, deleteCurrency);

        final relatedTxns = await txn.rawQuery(
          '''SELECT * FROM transactions
             WHERE (description LIKE ? OR description LIKE ?)
             ORDER BY id DESC''',
          ['%$voucherNumber%', '%سند جرد%$id%'],
        );

        // عكس جميع القيود المرتبطة (وليس فقط أول 4)
        for (final txnRow in relatedTxns) {
          final accId = txnRow['account_id'] as int;
          final debit = MoneyHelper.readMoney(txnRow['debit']);
          final credit = MoneyHelper.readMoney(txnRow['credit']);

          // Reverse: swap debit and credit
          final reversalAmount = credit > 0 ? credit : debit;
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': generateUniqueJournalId(),
            'debit': MoneyHelper.toCents(credit),
            'credit': MoneyHelper.toCents(debit),
            'description': 'عكس قيد - حذف سند جرد رقم $voucherNumber',
            'date': now.substring(0, 10),
            'created_at': now,
            'currency_code': deleteCurrency,
            'exchange_rate': deleteCurrency == 'YER' ? 1.0 : deleteRate,
            'amount_base':
                (MoneyHelper.toCents(reversalAmount) * deleteRate).round(),
          });

          // Reverse the account balance
          await _dbHelper.journal
              .updateAccountBalanceWithJournal(txn, accId, credit, debit, now);
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
    final journalId = generateUniqueJournalId();

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
        throw Exception(
            'لا يمكن تأكيد سند جرد بحالة "$currentStatus" — يجب أن يكون مسودة');
      }

      final currency = voucherRows.first['currency'] as String? ?? 'YER';
      final confirmRate = await _getExchangeRate(txn, currency);
      final voucherDate =
          voucherRows.first['date'] as String? ?? now.substring(0, 10);

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
          final currentStock =
              (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
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

      // ── C-05: استخدام حسابات تفاوت الجرد بدل COGS في تأكيد السند ──
      final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);

      // حساب المخزون (1300+offset)
      final inventoryAccount = await _dbHelper.journal
          .findAccountByCodeAndCurrency(txn, '1300', currency);

      // حساب إيراد تفاوت الجرد (4400+offset)
      final varianceIncomeCode = (4400 + codeOffset).toString();
      final varianceIncomeRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [varianceIncomeCode, currency],
        limit: 1,
      );
      int? varianceIncomeAccountId;
      if (varianceIncomeRows.isNotEmpty) {
        varianceIncomeAccountId = varianceIncomeRows.first['id'] as int;
      } else {
        varianceIncomeAccountId = await txn.insert('accounts', {
          'name_ar': 'إيراد تفاوت الجرد ($currency)',
          'name_en': 'Inventory Variance Income ($currency)',
          'account_code': varianceIncomeCode,
          'account_type': 'REVENUE',
          'balance': 0,
          'currency': currency,
          'balance_type': 'credit',
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
      }

      // حساب خسارة تفاوت الجرد (5500+offset)
      final varianceLossCode = (5500 + codeOffset).toString();
      final varianceLossRows = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [varianceLossCode, currency],
        limit: 1,
      );
      int? varianceLossAccountId;
      if (varianceLossRows.isNotEmpty) {
        varianceLossAccountId = varianceLossRows.first['id'] as int;
      } else {
        varianceLossAccountId = await txn.insert('accounts', {
          'name_ar': 'خسارة تفاوت الجرد ($currency)',
          'name_en': 'Inventory Variance Loss ($currency)',
          'account_code': varianceLossCode,
          'account_type': 'EXPENSE',
          'balance': 0,
          'currency': currency,
          'balance_type': 'debit',
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
      }

      final voucherNumber =
          voucherRows.first['voucher_number'] as String? ?? '';

      // C-05: قيود زيادة المخزون — مدين المخزون / دائن إيراد تفاوت الجرد
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
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : confirmRate,
            'amount_base':
                (MoneyHelper.toCents(totalIncreaseValue) * confirmRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, invAccId, totalIncreaseValue, 0.0, now);
        }
        await txn.insert('transactions', {
          'account_id': varianceIncomeAccountId,
          'journal_id': journalId,
          'debit': 0,
          'credit': MoneyHelper.toCents(totalIncreaseValue),
          'description': 'تأكيد سند جرد $voucherNumber - زيادة مخزون',
          'date': voucherDate,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': currency == 'YER' ? 1.0 : confirmRate,
          'amount_base':
              (MoneyHelper.toCents(totalIncreaseValue) * confirmRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, varianceIncomeAccountId, 0.0, totalIncreaseValue, now);
      }

      // C-05: قيود نقص المخزون — مدين خسارة تفاوت الجرد / دائن المخزون
      if (totalDecreaseValue > 0) {
        await txn.insert('transactions', {
          'account_id': varianceLossAccountId,
          'journal_id': journalId,
          'debit': MoneyHelper.toCents(totalDecreaseValue),
          'credit': 0,
          'description': 'تأكيد سند جرد $voucherNumber - نقص مخزون',
          'date': voucherDate,
          'created_at': now,
          'currency_code': currency,
          'exchange_rate': currency == 'YER' ? 1.0 : confirmRate,
          'amount_base':
              (MoneyHelper.toCents(totalDecreaseValue) * confirmRate).round(),
        });
        await _dbHelper.journal.updateAccountBalanceWithJournal(
            txn, varianceLossAccountId, totalDecreaseValue, 0.0, now);
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
            'currency_code': currency,
            'exchange_rate': currency == 'YER' ? 1.0 : confirmRate,
            'amount_base':
                (MoneyHelper.toCents(totalDecreaseValue) * confirmRate).round(),
          });
          await _dbHelper.journal.updateAccountBalanceWithJournal(
              txn, invAccId, 0.0, totalDecreaseValue, now);
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
