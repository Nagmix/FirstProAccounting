import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/supplier_repository.dart';
import 'package:firstpro/data/models/supplier_model.dart';
import 'package:firstpro/ui/screens/shared/entities_screen.dart';
import 'package:firstpro/ui/screens/suppliers/add_supplier_sheet.dart';
import 'package:firstpro/ui/screens/suppliers/supplier_detail_screen.dart';

/// UI-10: SuppliersScreen is now a thin wrapper around EntitiesScreen<Supplier>.
/// All UI logic, state management, and card rendering live in the generic
/// [EntitiesScreen] widget. This file only provides the supplier-specific
/// configuration (labels, icons, repository callbacks, model accessors).
///
/// The [cardPhoneIconBuilder] is provided to show Icons.chat for WhatsApp
/// contacts (the only behavioral difference from the customer card).
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EntitiesScreen<Supplier>(
      title: 'قائمة الموردين',
      entityNoun: 'مورد',
      entityNounPlural: 'موردين',
      deleteEntityTypeLabel: 'المورد',
      searchHint: 'بحث عن مورد بالاسم أو الهاتف...',
      addLabel: 'إضافة مورد',
      emptyTitleAll: 'لا يوجد موردين',
      emptyTitleDebit: 'لا يوجد موردين مدينون',
      emptyTitleCredit: 'لا يوجد موردين دائنون',
      emptySubtitleAll: 'قم بإضافة موردين جدد لبدء إدارة حساباتك',
      entityIcon: Icons.local_shipping,
      addIcon: Icons.local_shipping,
      fetchAll: () => locator<SupplierRepository>().getAllSuppliers(),
      balanceForCurrency: (supplier, currency) => locator<SupplierRepository>()
          .getSupplierBalanceForCurrency(supplier.id!, currency),
      deleteEntity: (supplier) =>
          locator<SupplierRepository>().deleteSupplier(supplier.id!),
      parseEntity: Supplier.fromMap,
      buildAddSheet: () => const AddSupplierSheet(),
      buildDetailScreen: (supplier) =>
          SupplierDetailScreen(supplier: supplier),
      idOf: (s) => s.id,
      nameOf: (s) => s.name,
      phoneOf: (s) => s.phone,
      // UI-10: supplier card shows chat icon for WhatsApp contacts
      cardPhoneIconBuilder: (s) =>
          s.contactMethod == 'whatsapp' ? Icons.chat : Icons.phone_in_talk,
    );
  }
}
