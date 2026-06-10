import 'package:sqflite_sqlcipher/sqflite.dart';

/// Database seed methods for populating initial data.
class DatabaseSeeds {
  /// Seed default currencies into the database.
  static Future<void> seedCurrencies(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = [
      {
        'code': 'YER',
        'name_ar': 'ريال يمني',
        'name_en': 'Yemeni Rial',
        'symbol': 'ر.ي',
        'exchange_rate': 1.0,
        'is_default': 1,
        'is_active': 1,
        'created_at': now
      },
      {
        'code': 'SAR',
        'name_ar': 'ريال سعودي',
        'name_en': 'Saudi Riyal',
        'symbol': 'ر.س',
        'exchange_rate': 140.0,
        'is_default': 0,
        'is_active': 1,
        'created_at': now
      },
      {
        'code': 'USD',
        'name_ar': 'دولار أمريكي',
        'name_en': 'US Dollar',
        'symbol': r'$',
        'exchange_rate': 530.0,
        'is_default': 0,
        'is_active': 1,
        'created_at': now
      },
    ];
    for (final c in currencies) {
      await db.insert('currencies', c);
    }
  }

  /// Shared account templates: [nameAr, nameEn, baseCode, accountType, parentBaseCode]
  /// parentBaseCode = null means this is a root/group account
  /// Used by both seedDefaultAccounts and seedAccountsForCurrency.
  static const List<List<dynamic>> defaultAccountTemplates = [
    // ── الأصول (Assets) ──
    ['حساب الأصول', 'Assets Account', 1000, 'ASSET', null],
    ['حساب الصناديق والبنوك', 'Cash & Banks Account', 1100, 'ASSET', 1000],
    ['حساب العملاء', 'Customers Account', 1200, 'ASSET', 1000],
    ['المخزون', 'Inventory Account', 1300, 'ASSET', 1000],
    // ── الخصوم (Liabilities) ──
    ['حساب الخصوم', 'Liabilities Account', 2000, 'LIABILITY', null],
    ['حساب الموردين', 'Suppliers Account', 2100, 'LIABILITY', 2000],
    ['ضريبة القيمة المضافة', 'VAT Payable', 2300, 'LIABILITY', 2000],
    // ── حقوق الملكية (Equity) ──
    ['حقوق الملكية', 'Equity Account', 2900, 'EQUITY', null],
    ['رصيد افتتاحي', 'Opening Balance Equity', 2901, 'EQUITY', 2900],
    ['الأرباح المحتجزة', 'Retained Earnings', 2910, 'EQUITY', 2900],
    // ── التكاليف (Costs) ──
    ['حساب التكاليف', 'Cost Account', 3000, 'COST', null],
    ['حساب المشتريات', 'Purchases Account', 3100, 'COST', 3000],
    ['تكلفة البضاعة المباعة', 'COGS Account', 3200, 'COST', 3000],
    // ── الإيرادات (Revenue) ──
    ['حساب الإيرادات', 'Revenue Account', 4000, 'REVENUE', null],
    ['حساب المبيعات', 'Sales Account', 4100, 'REVENUE', 4000],
    ['خصم مشتريات مكتسب', 'Purchase Discount Earned', 4600, 'REVENUE', 4000],
    // ── المصروفات (Expenses) ──
    ['حساب المصاريف', 'Expenses Account', 5000, 'EXPENSE', null],
    ['حساب الموظفين', 'Employees Account', 5100, 'EXPENSE', 5000],
    ['اجور النقل', 'Transport Charges', 5200, 'EXPENSE', 5000],
    ['مصاريف بنكية', 'Bank Charges', 5250, 'EXPENSE', 5000],
    ['خسائر فروقات الصرف', 'Exchange Rate Losses', 5300, 'EXPENSE', 5000],
    ['خصم مسموح به', 'Discount Allowed', 5400, 'EXPENSE', 5000],
    ['خسارة تفاوت الجرد', 'Inventory Variance Loss', 5500, 'EXPENSE', 5000],
    // ── إيرادات أخرى (Other Revenue) ──
    ['مكاسب فروقات الصرف', 'Exchange Rate Gains', 4700, 'REVENUE', 4000],
    ['إيراد تفاوت الجرد', 'Inventory Variance Income', 4400, 'REVENUE', 4000],
  ];

  /// Seed default chart of accounts for all currencies.
  static Future<void> seedDefaultAccounts(Database db) async {
    // Only seed if accounts don't already exist
    final existing = await db.query('accounts',
        where: 'account_code = ?', whereArgs: ['1000'], limit: 1);
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();

    // Use shared account templates (M-07)
    final templates = defaultAccountTemplates;

    // Currency configurations: [currencyCode, symbol, codeOffset]
    final currencyConfigs = [
      ['YER', 'ر.ي', 0],
      ['SAR', 'ر.س', 1],
      ['USD', r'$', 2],
    ];

    for (final config in currencyConfigs) {
      final currencyCode = config[0] as String;
      final currencySymbol = config[1] as String;
      final codeOffset = config[2] as int;

      // Track inserted account IDs by code for parent_id resolution
      final codeToId = <String, int>{};

      // Sort to ensure parent accounts are inserted before children
      final sortedTemplates = List<List<dynamic>>.from(templates);
      sortedTemplates.sort((a, b) {
        final parentA = a[4] as int?;
        final parentB = b[4] as int?;
        if (parentA == null && parentB != null) return -1;
        if (parentA != null && parentB == null) return 1;
        return 0;
      });

      for (final template in sortedTemplates) {
        final baseCode = template[2] as int;
        final actualCode = (baseCode + codeOffset).toString();
        final accountType = template[3] as String;
        final parentBaseCode = template[4] as int?;

        int? parentId;
        if (parentBaseCode != null) {
          final parentCode = (parentBaseCode + codeOffset).toString();
          parentId = codeToId[parentCode];
        }

        final id = await db.insert('accounts', {
          'name_ar': '${template[0]} ($currencySymbol)',
          'name_en': '${template[1]} ($currencyCode)',
          'account_code': actualCode,
          'account_type': accountType,
          'balance': 0,
          'currency': currencyCode,
          'balance_type': (accountType == 'ASSET' ||
                  accountType == 'COST' ||
                  accountType == 'EXPENSE')
              ? 'debit'
              : 'credit',
          'base_code': baseCode,
          'parent_id': parentId,
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
        codeToId[actualCode] = id;
      }
    }
  }

  /// Seed accounts for a specific currency if they don't already exist.
  static Future<void> seedAccountsForCurrency(DatabaseExecutor db,
      String currencyCode, String currencySymbol, int codeOffset) async {
    final now = DateTime.now().toIso8601String();

    final baseCode = 1000 + codeOffset;
    final existing = await db.query('accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [baseCode.toString(), currencyCode],
        limit: 1);
    if (existing.isNotEmpty) return;

    final templates = defaultAccountTemplates;
    final codeToId = <String, int>{};

    final sortedTemplates = List<List<dynamic>>.from(templates);
    sortedTemplates.sort((a, b) {
      final parentA = a[4] as int?;
      final parentB = b[4] as int?;
      if (parentA == null && parentB != null) return -1;
      if (parentA != null && parentB == null) return 1;
      return 0;
    });

    for (final template in sortedTemplates) {
      final actualCode = ((template[2] as int) + codeOffset).toString();
      final accountType = template[3] as String;
      final parentBaseCode = template[4] as int?;

      int? parentId;
      if (parentBaseCode != null) {
        final parentCode = (parentBaseCode + codeOffset).toString();
        parentId = codeToId[parentCode];
      }

      final id = await db.insert('accounts', {
        'name_ar': '${template[0]} ($currencySymbol)',
        'name_en': '${template[1]} ($currencyCode)',
        'account_code': actualCode,
        'account_type': accountType,
        'balance': 0,
        'currency': currencyCode,
        'balance_type': (accountType == 'ASSET' ||
                accountType == 'COST' ||
                accountType == 'EXPENSE')
            ? 'debit'
            : 'credit',
        'base_code': template[2] as int,
        'parent_id': parentId,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
      codeToId[actualCode] = id;
    }
  }

  /// Seed the units table with a comprehensive default set organized by type.
  static Future<void> seedDefaultUnits(Database db) async {
    final now = DateTime.now().toIso8601String();
    // Only seed if units table is empty
    final count = (await db.query('units')).length;
    if (count > 0) return;

    final defaultUnits = [
      // ── العد (Count) ──
      {
        'name_ar': 'حبة',
        'name_en': 'Piece',
        'abbreviation': 'حبة',
        'unit_type': 'count',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 1
      },
      {
        'name_ar': 'قطعة',
        'name_en': 'Item',
        'abbreviation': 'ق',
        'unit_type': 'count',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 2
      },
      {
        'name_ar': 'كرتون',
        'name_en': 'Carton',
        'abbreviation': 'كرت',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 3
      },
      {
        'name_ar': 'باكيت',
        'name_en': 'Packet',
        'abbreviation': 'باك',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 4
      },
      {
        'name_ar': 'علبة',
        'name_en': 'Box',
        'abbreviation': 'علب',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 5
      },
      {
        'name_ar': 'ظرف',
        'name_en': 'Envelope',
        'abbreviation': 'ظرف',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 6
      },
      {
        'name_ar': 'طبق',
        'name_en': 'Tray',
        'abbreviation': 'طبق',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 7
      },
      {
        'name_ar': 'طقم',
        'name_en': 'Set',
        'abbreviation': 'طقم',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 8
      },
      {
        'name_ar': 'منصة',
        'name_en': 'Pallet',
        'abbreviation': 'منص',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 0,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 9
      },
      {
        'name_ar': 'درزن',
        'name_en': 'Dozen',
        'abbreviation': 'درز',
        'unit_type': 'count',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 10
      },

      // ── الوزن (Weight) ──
      {
        'name_ar': 'جرام',
        'name_en': 'Gram',
        'abbreviation': 'جم',
        'unit_type': 'weight',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 11
      },
      {
        'name_ar': 'كيلو',
        'name_en': 'Kilogram',
        'abbreviation': 'كجم',
        'unit_type': 'weight',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 12
      },
      {
        'name_ar': 'طن',
        'name_en': 'Ton',
        'abbreviation': 'طن',
        'unit_type': 'weight',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 13
      },

      // ── السوائل (Liquid) ──
      {
        'name_ar': 'مل',
        'name_en': 'Milliliter',
        'abbreviation': 'مل',
        'unit_type': 'liquid',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 14
      },
      {
        'name_ar': 'لتر',
        'name_en': 'Liter',
        'abbreviation': 'ل',
        'unit_type': 'liquid',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 15
      },
      {
        'name_ar': 'جالون',
        'name_en': 'Gallon',
        'abbreviation': 'جال',
        'unit_type': 'liquid',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 16
      },

      // ── الصيدلية (Pharmacy) ──
      {
        'name_ar': 'شريط',
        'name_en': 'Strip',
        'abbreviation': 'شر',
        'unit_type': 'pharmacy',
        'is_base_unit': 0,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 1,
        'display_order': 17
      },
      {
        'name_ar': 'كبسولة',
        'name_en': 'Capsule',
        'abbreviation': 'كبس',
        'unit_type': 'pharmacy',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 18
      },

      // ── القياس (Measurement) ──
      {
        'name_ar': 'متر',
        'name_en': 'Meter',
        'abbreviation': 'م',
        'unit_type': 'count',
        'is_base_unit': 1,
        'is_sellable': 1,
        'is_purchasable': 1,
        'is_packaging': 0,
        'display_order': 19
      },
    ];

    for (final unit in defaultUnits) {
      await db.insert('units', {
        ...unit,
        'is_active': 1,
        'description': '',
        'created_at': now,
        'updated_at': now,
      });
    }
  }
}
