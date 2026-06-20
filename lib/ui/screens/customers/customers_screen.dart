import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/customer_repository.dart';
import 'package:firstpro/data/models/customer_model.dart';
import 'package:firstpro/ui/screens/shared/entities_screen.dart';
import 'package:firstpro/ui/screens/customers/add_customer_sheet.dart';
import 'package:firstpro/ui/screens/customers/customer_detail_screen.dart';

/// UI-10: CustomersScreen is now a thin wrapper around EntitiesScreen<Customer>.
/// All UI logic, state management, and card rendering live in the generic
/// [EntitiesScreen] widget. This file only provides the customer-specific
/// configuration (labels, icons, repository callbacks, model accessors).
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EntitiesScreen<Customer>(
      title: 'قائمة العملاء',
      entityNoun: 'عميل',
      entityNounPlural: 'عملاء',
      deleteEntityTypeLabel: 'العميل',
      searchHint: 'بحث عن عميل بالاسم أو الهاتف...',
      addLabel: 'إضافة عميل',
      emptyTitleAll: 'لا يوجد عملاء',
      emptyTitleDebit: 'لا يوجد عملاء مدينون',
      emptyTitleCredit: 'لا يوجد عملاء دائنون',
      emptySubtitleAll: 'قم بإضافة عملاء جدد لبدء إدارة حساباتك',
      entityIcon: Icons.people,
      addIcon: Icons.person_add,
      fetchAll: () => locator<CustomerRepository>().getAllCustomers(),
      balanceForCurrency: (customer, currency) => locator<CustomerRepository>()
          .getCustomerBalanceForCurrency(customer.id!, currency),
      deleteEntity: (customer) =>
          locator<CustomerRepository>().deleteCustomer(customer.id!),
      parseEntity: Customer.fromMap,
      buildAddSheet: () => const AddCustomerSheet(),
      buildDetailScreen: (customer) =>
          CustomerDetailScreen(customer: customer),
      idOf: (c) => c.id,
      nameOf: (c) => c.name,
      phoneOf: (c) => c.phone,
      // cardPhoneIconBuilder omitted → defaults to Icons.phone
    );
  }
}
