import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../../core/utils/currency_formatter.dart';

// ═══════════════════════════════════════════════════════════════════
//  Shared Data Types
// ═══════════════════════════════════════════════════════════════════

class ReportGroup {
  final String name;
  final IconData icon;
  final Color color;
  final List<ReportItem> items;
  bool isExpanded;

  ReportGroup({
    required this.name,
    required this.icon,
    required this.color,
    required this.items,
    this.isExpanded = false,
  });
}

class ReportItem {
  final String name;
  final IconData icon;
  final Color color;
  final String key;

  const ReportItem({
    required this.name,
    required this.icon,
    required this.color,
    required this.key,
  });
}

enum DatePreset {
  today,
  thisWeek,
  thisMonth,
  thisQuarter,
  thisYear,
  custom,
}

// ═══════════════════════════════════════════════════════════════════
//  Constants
// ═══════════════════════════════════════════════════════════════════

const currencyOptions = ['ر.ي', 'ر.س', r'$'];

const accountTypes = [
  MapEntry('الكل', 'الكل'),
  MapEntry('أصول', 'ASSET'),
  MapEntry('خصوم', 'LIABILITY'),
  MapEntry('حقوق الملكية', 'EQUITY'),
  MapEntry('تكاليف', 'COST'),
  MapEntry('إيرادات', 'REVENUE'),
  MapEntry('مصاريف', 'EXPENSE'),
];

// ═══════════════════════════════════════════════════════════════════
//  Report Descriptions
// ═══════════════════════════════════════════════════════════════════

const reportDescriptions = {
  'sales': 'تفاصيل فواتير المبيعات',
  'purchases': 'تفاصيل فواتير المشتريات',
  'sales_returns': 'فواتير المرتجعات للمبيعات',
  'purchase_returns': 'فواتير المرتجعات للمشتريات',
  'profit_loss': 'ملخص الأرباح والخسائر',
  'invoice_profit': 'ربح كل فاتورة بالتفصيل',
  'sales_by_product': 'ترتيب المنتجات حسب المبيعات',
  'sales_by_customer': 'ترتيب العملاء حسب المشتريات',
  'account_movement': 'حركة حساب محدد بالتفصيل',
  'all_account_movement': 'كل حركات الحسابات',
  'trial_balance': 'ميزان المراجعة للتحقق',
  'trial_balance_screen': 'شاشة كاملة لميزان المراجعة',
  'financial_statements': 'قائمة الدخل والمركزية المالي',
  'cash_box': 'أرصدة وحركة الصناديق',
  'accounts_no_movement': 'حسابات بلا قيود',
  'customer_statement': 'كشف حساب عميل',
  'supplier_statement': 'كشف حساب مورد',
  'expenses': 'تفاصيل المصروفات',
  'inventory': 'حالة المخزون الحالية',
  'inventory_movement': 'وارد وصادر المخزون',
  'inventory_cost': 'تكلفة وقيمة المخزون',
  'out_of_stock': 'أصناف نفدت من المخزون',
  'low_stock': 'أصناف تحت الحد الأدنى',
  'customer_debts': 'ديون العملاء المستحقة',
  'supplier_debts': 'ديون الموردين المستحقة',
  'cash_transfers': 'التحويلات بين الصناديق',
  'currency_exchanges': 'عمليات صرافة العملات',
  'vouchers': 'سندات القبض والصرف',
  'shifts': 'تقرير الورديات',
};

String getReportDescription(String key) {
  return reportDescriptions[key] ?? 'تقرير';
}

// ═══════════════════════════════════════════════════════════════════
//  Formatting Utilities
// ═══════════════════════════════════════════════════════════════════

String? currencyCode(String selectedCurrency) {
  switch (selectedCurrency) {
    case 'ر.ي': return 'YER';
    case 'ر.س': return 'SAR';
    case r'$': return 'USD';
    default: return null;
  }
}

String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  try {
    final dt = DateTime.parse(iso);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (e) {
    debugPrint('ReportHelpers.fmtDate: $e');
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}

String fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

String fmtMoney(double v) => CurrencyFormatter.format(v);

String accountTypeAr(String type) {
  switch (type) {
    case 'ASSET': return 'أصول';
    case 'LIABILITY': return 'خصوم';
    case 'EQUITY': return 'حقوق الملكية';
    case 'COST': return 'تكاليف';
    case 'REVENUE': return 'إيرادات';
    case 'EXPENSE': return 'مصاريف';
    default: return type;
  }
}

String invoiceTypeAr(String type, {int? isReturn}) {
  final isRet = isReturn == 1;
  switch (type) {
    case 'sale': case 'pos': return isRet ? 'مرتجع مبيعات' : 'مبيعات';
    case 'purchase': return isRet ? 'مرتجع مشتريات' : 'مشتريات';
    default: return type;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Filter Need Checkers
// ═══════════════════════════════════════════════════════════════════

bool needsDateFilter(String? reportKey) {
  if (reportKey == null) return false;
  const noDate = {'accounts_no_movement', 'inventory', 'out_of_stock', 'low_stock', 'inventory_cost'};
  return !noDate.contains(reportKey);
}

bool needsCurrencyFilter(String? reportKey) {
  if (reportKey == null) return false;
  const noCurrency = {'accounts_no_movement', 'inventory_movement', 'cash_transfers', 'currency_exchanges', 'shifts'};
  return !noCurrency.contains(reportKey);
}

bool needsAccountFilter(String? reportKey) {
  return reportKey == 'account_movement';
}

bool needsCustomerFilter(String? reportKey) {
  return reportKey == 'customer_statement';
}

bool needsSupplierFilter(String? reportKey) {
  return reportKey == 'supplier_statement';
}

bool needsCashBoxFilter(String? reportKey) {
  return reportKey == 'cash_box';
}

bool needsWarehouseFilter(String? reportKey) {
  return const {'inventory', 'out_of_stock', 'low_stock'}.contains(reportKey);
}

bool needsCategoryFilter(String? reportKey) {
  return const {'inventory', 'out_of_stock', 'low_stock', 'sales_by_product'}.contains(reportKey);
}

bool needsAccountTypeFilter(String? reportKey) {
  return const {'trial_balance', 'all_account_movement'}.contains(reportKey);
}

// ═══════════════════════════════════════════════════════════════════
//  Date Preset Helpers
// ═══════════════════════════════════════════════════════════════════

({DateTime? from, DateTime? to}) applyDatePreset(DatePreset preset) {
  final now = DateTime.now();
  switch (preset) {
    case DatePreset.today:
      return (
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day),
      );
    case DatePreset.thisWeek:
      final weekday = now.weekday;
      final weekStart = now.subtract(Duration(days: weekday - 1));
      return (
        from: DateTime(weekStart.year, weekStart.month, weekStart.day),
        to: DateTime(now.year, now.month, now.day),
      );
    case DatePreset.thisMonth:
      return (
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, now.day),
      );
    case DatePreset.thisQuarter:
      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      return (
        from: DateTime(now.year, quarterStartMonth, 1),
        to: DateTime(now.year, now.month, now.day),
      );
    case DatePreset.thisYear:
      return (
        from: DateTime(now.year, 1, 1),
        to: DateTime(now.year, now.month, now.day),
      );
    case DatePreset.custom:
      return (from: null, to: null);
  }
}

/// Find the report name for a given key from the groups list.
String getReportName(String? key, List<ReportGroup> groups) {
  if (key == null) return 'تقرير';
  for (final group in groups) {
    for (final item in group.items) {
      if (item.key == key) return item.name;
    }
  }
  return 'تقرير';
}
