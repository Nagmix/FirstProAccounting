import 'package:get_it/get_it.dart';

import '../../data/datasources/database_helper.dart';
import '../../data/datasources/repositories/account_repository.dart';
import '../../data/datasources/repositories/customer_repository.dart';
import '../../data/datasources/repositories/invoice_repository.dart';
import '../../data/datasources/repositories/product_repository.dart';
import '../../data/datasources/repositories/supplier_repository.dart';
import '../../data/datasources/repositories/expense_repository.dart';
import '../../data/datasources/repositories/reference_data_repository.dart';
import '../../data/datasources/repositories/order_repository.dart';
import '../../data/datasources/repositories/voucher_repository.dart';
import '../../data/datasources/repositories/employee_repository.dart';
import '../../data/datasources/repositories/expense_sub_account_repository.dart';
import '../../data/datasources/services/cash_box_service.dart';
import '../../data/datasources/services/journal_service.dart';
import '../../data/datasources/services/stock_service.dart';
import '../../data/datasources/services/shift_service.dart';
import '../../data/datasources/services/report_service.dart';
import '../../data/datasources/services/audit_service.dart';
import '../../data/datasources/services/costing_engine_service.dart';
import '../../data/datasources/services/bank_reconciliation_service.dart';
import '../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../core/viewmodels/dashboard_viewmodel.dart';
import '../../core/viewmodels/pos_viewmodel.dart';
import '../../core/viewmodels/invoice_viewmodel.dart';

final GetIt locator = GetIt.instance;

/// Initialize the service locator with all dependencies.
/// Must be called once at app startup before any screen is loaded.
Future<void> setupLocator() async {
  // ── Core ──
  locator.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // ── Repositories ──
  locator.registerLazySingleton<AccountRepository>(
    () => AccountRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<CustomerRepository>(
    () => CustomerRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<InvoiceRepository>(
    () => InvoiceRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ProductRepository>(
    () => ProductRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<SupplierRepository>(
    () => SupplierRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ExpenseRepository>(
    () => ExpenseRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ReferenceDataRepository>(
    () => ReferenceDataRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<OrderRepository>(
    () => OrderRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<VoucherRepository>(
    () => VoucherRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<EmployeeRepository>(
    () => EmployeeRepository(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ExpenseSubAccountRepository>(
    () => ExpenseSubAccountRepository(locator<DatabaseHelper>()),
  );

  // ── Services ──
  locator.registerLazySingleton<CashBoxService>(
    () => CashBoxService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<JournalService>(
    () => JournalService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<StockService>(
    () => StockService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ShiftService>(
    () => ShiftService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<ReportService>(
    () => ReportService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<AuditService>(
    () => AuditService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<CostingEngineService>(
    () => CostingEngineService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<BankReconciliationService>(
    () => BankReconciliationService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<VoucherAutoMappingService>(
    () => VoucherAutoMappingService(locator<DatabaseHelper>()),
  );

  // ── ViewModels (factory — fresh instance per screen, no stale state) ──
  locator.registerFactory<DashboardViewModel>(() => DashboardViewModel());
  locator.registerFactory<PosViewModel>(() => PosViewModel());
  locator.registerFactory<InvoiceViewModel>(() => InvoiceViewModel());

  // ── Mark locator as ready so DatabaseHelper resolves via locator ──
  // This ensures all sub-service getters in DatabaseHelper return the same
  // singleton instances that are registered here, eliminating duplicate objects.
  DatabaseHelper.markLocatorReady();
}
