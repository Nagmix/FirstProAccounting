import 'package:flutter/material.dart';
import 'package:firstpro/core/constants/app_constants.dart';
import 'package:firstpro/core/platform/capability_visibility_policy.dart';
import 'package:firstpro/ui/dashboard/action_definition.dart';

class ActionCatalog {
  ActionCatalog._();

  static const List<ActionDefinition> definitions = <ActionDefinition>[
    ActionDefinition(
      key: 'pos',
      labelAr: 'نقطة البيع',
      icon: Icons.point_of_sale_rounded,
      route: AppConstants.pos,
      requiredCapabilities: <String>{'sell'},
      priority: 10,
      color: Color(0xFF4F46E5),
      backgroundColor: Color(0xFFEEF0FF),
    ),
    ActionDefinition(
      key: 'new_sale',
      labelAr: 'فاتورة بيع',
      icon: Icons.receipt_long_rounded,
      route: AppConstants.newSaleInvoice,
      requiredCapabilities: <String>{'sell'},
      priority: 20,
      color: Color(0xFF22C55E),
      backgroundColor: Color(0xFFECFDF5),
    ),
    ActionDefinition(
      key: 'new_purchase',
      labelAr: 'فاتورة شراء',
      icon: Icons.shopping_cart_rounded,
      route: AppConstants.newPurchaseInvoice,
      requiredCapabilities: <String>{'buy'},
      priority: 30,
      color: Color(0xFFF97316),
      backgroundColor: Color(0xFFFFF7ED),
    ),
    ActionDefinition(
      key: 'service_orders',
      labelAr: 'الخدمات والطلبات',
      icon: Icons.build_rounded,
      route: AppConstants.serviceOrders,
      requiredCapabilities: <String>{'service'},
      priority: 35,
      color: Color(0xFFEA580C),
      backgroundColor: Color(0xFFFFF7ED),
    ),
    ActionDefinition(
      key: 'production',
      labelAr: 'الإنتاج والوصفات',
      icon: Icons.factory_outlined,
      route: AppConstants.productionOrders,
      requiredCapabilities: <String>{'transform'},
      priority: 36,
      color: Color(0xFF7C3AED),
      backgroundColor: Color(0xFFF5F3FF),
    ),
    ActionDefinition(
      key: 'expenses',
      labelAr: 'المصروفات',
      icon: Icons.account_balance_wallet_rounded,
      route: AppConstants.expenses,
      requiredCapabilities: <String>{'settle'},
      priority: 40,
      color: Color(0xFFEF4444),
      backgroundColor: Color(0xFFFEF2F2),
    ),
    ActionDefinition(
      key: 'customers',
      labelAr: 'العملاء',
      icon: Icons.people_rounded,
      route: AppConstants.customers,
      isCore: true,
      priority: 50,
      color: Color(0xFF22C55E),
      backgroundColor: Color(0xFFECFDF5),
    ),
    ActionDefinition(
      key: 'suppliers',
      labelAr: 'الموردون',
      icon: Icons.local_shipping_rounded,
      route: AppConstants.suppliers,
      requiredCapabilities: <String>{'buy'},
      priority: 51,
      color: Color(0xFF3B82F6),
      backgroundColor: Color(0xFFEFF6FF),
    ),
    ActionDefinition(
      key: 'products',
      labelAr: 'المنتجات',
      icon: Icons.inventory_2_rounded,
      route: AppConstants.products,
      requiredCapabilities: <String>{'stock'},
      priority: 60,
      color: Color(0xFFF97316),
      backgroundColor: Color(0xFFFFF7ED),
    ),
    ActionDefinition(
      key: 'invoices',
      labelAr: 'الفواتير',
      icon: Icons.receipt_rounded,
      route: AppConstants.invoices,
      requiredCapabilities: <String>{'sell'},
      priority: 61,
      color: Color(0xFF4F46E5),
      backgroundColor: Color(0xFFEEF0FF),
    ),
    ActionDefinition(
      key: 'warehouses',
      labelAr: 'المستودعات',
      icon: Icons.warehouse_rounded,
      route: AppConstants.warehouses,
      requiredCapabilities: <String>{'stock'},
      priority: 62,
      color: Color(0xFF8B5CF6),
      backgroundColor: Color(0xFFF5F3FF),
    ),
    ActionDefinition(
      key: 'cash_boxes',
      labelAr: 'الصناديق',
      icon: Icons.credit_card_rounded,
      route: AppConstants.cashBoxes,
      requiredCapabilities: <String>{'settle'},
      priority: 70,
      color: Color(0xFF06B6D4),
      backgroundColor: Color(0xFFECFEFF),
    ),
    ActionDefinition(
      key: 'employees',
      labelAr: 'الموظفون',
      icon: Icons.badge_rounded,
      route: AppConstants.employees,
      isCore: true,
      priority: 80,
      color: Color(0xFFEC4899),
      backgroundColor: Color(0xFFFDF2F8),
    ),
    ActionDefinition(
      key: 'reports',
      labelAr: 'التقارير',
      icon: Icons.bar_chart_rounded,
      route: AppConstants.reports,
      isCore: true,
      priority: 90,
      color: Color(0xFF4F46E5),
      backgroundColor: Color(0xFFEEF0FF),
    ),
    ActionDefinition(
      key: 'settings',
      labelAr: 'الإعدادات',
      icon: Icons.settings_rounded,
      route: AppConstants.settings,
      isCore: true,
      priority: 100,
      color: Color(0xFF6B7280),
      backgroundColor: Color(0xFFF9FAFB),
    ),
  ];

  static List<ActionDefinition> visibleActions(Set<String> enabledCodes) {
    final visibleCodes = CapabilityVisibilityPolicy.visibleCodes(enabledCodes);
    return definitions
        .where(
          (action) =>
              action.isCore ||
              action.requiredCapabilities
                  .every((code) => visibleCodes.contains(code)),
        )
        .toList(growable: false)
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  static List<ActionDefinition> prioritizedActions(
    Set<String> enabledCodes, {
    int limit = 6,
  }) {
    if (limit <= 0) return const <ActionDefinition>[];
    final visible = visibleActions(enabledCodes);
    final unique = <String, ActionDefinition>{};
    for (final action in visible) {
      unique.putIfAbsent(action.route, () => action);
      if (unique.length == limit) break;
    }
    return unique.values.toList(growable: false);
  }
}
