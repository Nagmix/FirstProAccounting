import 'package:flutter/material.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/ui/navigation/navigation_definition.dart';
import 'package:firstpro/core/platform/capability_visibility_policy.dart';

class NavigationCatalog {
  NavigationCatalog._();

  static const List<NavigationDefinition> definitions = <NavigationDefinition>[
    NavigationDefinition(
      route: AppConstants.dashboard,
      labelAr: 'الرئيسية',
      icon: Icons.home,
      isCore: true,
      priority: 1,
    ),
    NavigationDefinition(
      route: AppConstants.customers,
      labelAr: 'العملاء',
      icon: Icons.people,
      requiredCapabilities: <String>{'sell'},
      priority: 10,
    ),
    NavigationDefinition(
      route: AppConstants.newSaleInvoice,
      labelAr: 'فاتورة بيع جديدة',
      icon: Icons.receipt,
      requiredCapabilities: <String>{'sell'},
      priority: 20,
    ),
    NavigationDefinition(
      route: AppConstants.salesInvoices,
      labelAr: 'فواتير المبيعات',
      icon: Icons.receipt_long,
      requiredCapabilities: <String>{'sell'},
      priority: 21,
    ),
    NavigationDefinition(
      route: AppConstants.pos,
      labelAr: 'نقطة البيع',
      icon: Icons.point_of_sale,
      requiredCapabilities: <String>{'sell'},
      priority: 22,
    ),
    NavigationDefinition(
      route: AppConstants.quotations,
      labelAr: 'عروض الأسعار',
      icon: Icons.description,
      requiredCapabilities: <String>{'sell'},
      priority: 23,
    ),
    NavigationDefinition(
      route: AppConstants.salesOrders,
      labelAr: 'طلبات البيع',
      icon: Icons.assignment,
      requiredCapabilities: <String>{'sell'},
      priority: 24,
    ),
    NavigationDefinition(
      route: AppConstants.suppliers,
      labelAr: 'الموردون',
      icon: Icons.local_shipping,
      requiredCapabilities: <String>{'buy'},
      priority: 30,
    ),
    NavigationDefinition(
      route: AppConstants.newPurchaseInvoice,
      labelAr: 'فاتورة شراء جديدة',
      icon: Icons.shopping_cart,
      requiredCapabilities: <String>{'buy'},
      priority: 31,
    ),
    NavigationDefinition(
      route: AppConstants.purchaseInvoices,
      labelAr: 'فواتير المشتريات',
      icon: Icons.shopping_bag,
      requiredCapabilities: <String>{'buy'},
      priority: 32,
    ),
    NavigationDefinition(
      route: AppConstants.purchaseOrders,
      labelAr: 'طلبات الشراء',
      icon: Icons.playlist_add_check,
      requiredCapabilities: <String>{'buy'},
      priority: 33,
    ),
    NavigationDefinition(
      route: AppConstants.recurringInvoices,
      labelAr: 'الفواتير المتكررة',
      icon: Icons.repeat,
      requiredCapabilities: <String>{'sell'},
      priority: 34,
    ),
    NavigationDefinition(
      route: AppConstants.products,
      labelAr: 'المنتجات والمخزون',
      icon: Icons.inventory_2,
      requiredCapabilities: <String>{'stock'},
      priority: 40,
    ),
    NavigationDefinition(
      route: AppConstants.inventory,
      labelAr: 'الأصناف',
      icon: Icons.category,
      requiredCapabilities: <String>{'stock'},
      priority: 41,
    ),
    NavigationDefinition(
      route: AppConstants.warehouses,
      labelAr: 'المستودعات',
      icon: Icons.warehouse,
      requiredCapabilities: <String>{'stock'},
      priority: 42,
    ),
    NavigationDefinition(
      route: AppConstants.stockTransfer,
      labelAr: 'تحويل مخزني',
      icon: Icons.compare_arrows,
      requiredCapabilities: <String>{'stock'},
      priority: 43,
    ),
    NavigationDefinition(
      route: AppConstants.stocktaking,
      labelAr: 'الجرد',
      icon: Icons.fact_check,
      requiredCapabilities: <String>{'stock'},
      priority: 44,
    ),
    NavigationDefinition(
      route: AppConstants.inventoryAdjustments,
      labelAr: 'تسويات الجرد',
      icon: Icons.fact_check_outlined,
      requiredCapabilities: <String>{'stock'},
      priority: 45,
    ),
    NavigationDefinition(
      route: AppConstants.inventoryVoucher,
      labelAr: 'سندات المخزون',
      icon: Icons.inventory,
      requiredCapabilities: <String>{'stock'},
      priority: 46,
    ),
    NavigationDefinition(
      route: AppConstants.serviceOrders,
      labelAr: 'الخدمات والطلبات',
      icon: Icons.build,
      requiredCapabilities: <String>{'service'},
      priority: 50,
    ),
    NavigationDefinition(
      route: AppConstants.shifts,
      labelAr: 'المواعيد والورديات',
      icon: Icons.event,
      requiredCapabilities: <String>{'schedule'},
      priority: 60,
    ),
    NavigationDefinition(
      route: AppConstants.productionOrders,
      labelAr: 'الإنتاج والوصفات',
      icon: Icons.factory_outlined,
      requiredCapabilities: <String>{'transform'},
      priority: 70,
    ),
    NavigationDefinition(
      route: AppConstants.cashBoxes,
      labelAr: 'الصناديق والبنوك',
      icon: Icons.account_balance_wallet,
      requiredCapabilities: <String>{'settle'},
      priority: 80,
    ),
    NavigationDefinition(
      route: AppConstants.cashTransfers,
      labelAr: 'تحويل بين الصناديق',
      icon: Icons.swap_horiz,
      requiredCapabilities: <String>{'settle'},
      priority: 81,
    ),
    NavigationDefinition(
      route: AppConstants.currencyExchange,
      labelAr: 'مصارفة العملات',
      icon: Icons.currency_exchange,
      requiredCapabilities: <String>{'settle'},
      priority: 81,
    ),
    NavigationDefinition(
      route: AppConstants.debts,
      labelAr: 'تتبع الديون',
      icon: Icons.savings,
      requiredCapabilities: <String>{'settle'},
      priority: 82,
    ),
    NavigationDefinition(
      route: AppConstants.vouchers,
      labelAr: 'السندات',
      icon: Icons.receipt_long,
      requiredCapabilities: <String>{'settle'},
      priority: 83,
    ),
    NavigationDefinition(
      route: AppConstants.bankReconciliation,
      labelAr: 'التسوية البنكية',
      icon: Icons.account_balance,
      requiredCapabilities: <String>{'settle'},
      priority: 84,
    ),
    NavigationDefinition(
      route: AppConstants.chartOfAccounts,
      labelAr: 'دليل الحسابات',
      icon: Icons.account_tree,
      isCore: true,
      priority: 85,
    ),
    NavigationDefinition(
      route: AppConstants.expenses,
      labelAr: 'المصروفات',
      icon: Icons.payments,
      requiredCapabilities: <String>{'settle'},
      priority: 84,
    ),
    NavigationDefinition(
      route: AppConstants.dailySalesReport,
      labelAr: 'تقرير المبيعات اليومية',
      icon: Icons.today,
      isCore: true,
      priority: 89,
    ),
    NavigationDefinition(
      route: AppConstants.employees,
      labelAr: 'الموظفون',
      icon: Icons.badge,
      isCore: true,
      priority: 88,
    ),
    NavigationDefinition(
      route: AppConstants.reports,
      labelAr: 'التقارير',
      icon: Icons.assessment,
      isCore: true,
      priority: 90,
    ),
    NavigationDefinition(
      route: AppConstants.statistics,
      labelAr: 'الإحصاءات',
      icon: Icons.bar_chart,
      isCore: true,
      priority: 91,
    ),
    NavigationDefinition(
      route: AppConstants.accountingAudit,
      labelAr: 'سجل التدقيق',
      icon: Icons.fact_check,
      isCore: true,
      priority: 100,
    ),
    NavigationDefinition(
      route: AppConstants.settings,
      labelAr: 'الإعدادات',
      icon: Icons.settings,
      isCore: true,
      priority: 101,
    ),
    NavigationDefinition(
      route: AppConstants.currencies,
      labelAr: 'العملات',
      icon: Icons.currency_exchange,
      isCore: true,
      priority: 102,
    ),
    NavigationDefinition(
      route: AppConstants.support,
      labelAr: 'المساعدة',
      icon: Icons.help_outline,
      isCore: true,
      priority: 103,
    ),
  ];

  static NavigationDefinition byRoute(String route) {
    return definitions.firstWhere(
      (definition) => definition.route == route,
      orElse: () => throw ArgumentError.value(route, 'route', 'Unknown route'),
    );
  }

  static List<NavigationDefinition> visibleCodes(Iterable<String> enabledCodes) {
    final enabled = CapabilityVisibilityPolicy.visibleCodes(enabledCodes).toSet();
    final visible = definitions.where((definition) {
      if (definition.isCore) return true;
      return definition.requiredCapabilities.every(enabled.contains);
    }).toList(growable: false);
    return visible..sort((a, b) => a.priority.compareTo(b.priority));
  }
}
