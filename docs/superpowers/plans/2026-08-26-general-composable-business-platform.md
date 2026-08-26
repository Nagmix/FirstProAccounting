# General Composable Business Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** تنفيذ منصة عامة قابلة للتركيب فوق النواة المالية الحالية، مع تهيئة متعددة الاختيار، ظهور ديناميكي للواجهات، ترحيل v59 آمن، وتكامل كامل مع Flutter دون تغيير التاريخ المحاسبي.

**Architecture:** نضيف طبقة typed صغيرة فوق الجداول الحالية: `BusinessProfile`, `CapabilityDefinition`, `CapabilityState`, وكتالوجات الملاحة والإجراءات. تحفظ الحالة في جداول v59 الجديدة، وتبقى `settings` القديمة adapter للتوافق. تُنفذ التهيئة والظهور عبر repositories/services وViewModels، بينما تبقى عمليات totals/posting/cancel في خدماتها المركزية ولا تنتقل إلى widgets.

**Tech Stack:** Flutter/Dart، Provider، ChangeNotifier، GetIt، sqflite_sqlcipher، SQLite، MoneyHelper، InvoiceTotalsEngine، GitHub Actions للتحليل والاختبارات وبناء Android.

**Spec:** `docs/superpowers/specs/2026-08-26-general-composable-business-platform-design.md`

## Global Constraints

- العمل مباشرة على `main` كما طلب المستخدم؛ لا worktree.
- لا تعديل migrations v2–v58؛ أول تغيير للمخطط هو v59.
- لا تثبيت Flutter أو حزم Flutter محلياً؛ التحقق التنفيذي النهائي عبر GitHub Actions.
- لا حذف لفواتير أو سندات أو قيود أو حركات مخزون تاريخية؛ المستند المرحّل يُلغى بقيد عكسي فقط.
- كل مبلغ جديد INTEGER minor units عبر `MoneyHelper`، وكل totals invoice-like عبر `InvoiceTotalsEngine`.
- لا استدعاء `BaseCurrencyService` أو فتح اتصال قاعدة آخر داخل `db.transaction`.
- لا hard-code لنوع نشاط مثل `businessType == bakery`؛ كل الظهور يعتمد على capability codes.
- الإصدار الأول مالك واحد على جهاز Android واحد؛ لا مزامنة أو تعدد مستخدمين أو استيراد Excel.
- أي فشل migration يمنع الدخول إلى التطبيق ويترك rollback قابلاً للاستعادة.

---

## Task 1: Establish the implementation baseline and test seams

**Files:**
- Read/modify as needed: `lib/core/di/service_locator.dart`
- Test: `test/regression/general_platform_baseline_test.dart`
- Create: `docs/superpowers/assessments/2026-08-26-general-platform-implementation-log.md`

**Interfaces:**
- Consumes: existing `DatabaseSchema.onCreate`, `DatabaseHelper`, `service_locator` registration style.
- Produces: a documented baseline and a test helper convention for in-memory databases; no production behavior change.

- [ ] **Step 1: Write the failing baseline test.**

Create a test that opens an in-memory database using the existing project test convention and asserts the current schema version is 58 before the new migration is added. The test must fail if the baseline unexpectedly differs, rather than silently accepting any version.

```dart
test('current production baseline is schema version 58 before v59', () async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 58,
    onCreate: DatabaseSchema.onCreate,
  );
  final rows = await db.rawQuery('PRAGMA user_version');
  expect((rows.single.values.single as num).toInt(), 58);
  await db.close();
});
```

- [ ] **Step 2: Run the focused test in CI or the project test environment and verify the expected RED/compatibility result.**

Run: `flutter test test/regression/general_platform_baseline_test.dart` in GitHub Actions.  
Expected: it either passes against v58, or fails with the exact current version/schema mismatch; do not proceed if the failure is caused by test setup.

- [ ] **Step 3: Implement only the test helper/documentation seam.**

Keep the production schema unchanged. Record the baseline, current CI run, and known test invocation in `docs/superpowers/assessments/2026-08-26-general-platform-implementation-log.md`. Do not add v59 yet.

- [ ] **Step 4: Run the focused test again.**

Expected: PASS with schema version 58 and no warnings.

- [ ] **Step 5: Commit.**

```bash
git add test/regression/general_platform_baseline_test.dart docs/superpowers/assessments/2026-08-26-general-platform-implementation-log.md
git commit -m "test: establish general platform baseline"
```

## Task 2: Add v59 additive schema and migration runner registration

**Files:**
- Create: `lib/data/datasources/migrations/migration_v59.dart`
- Modify: `lib/data/datasources/migrations/migration_runner.dart`
- Modify: `lib/data/datasources/database_helper.dart`
- Test: `test/database/migration_v59_general_platform_test.dart`

**Interfaces:**
- Consumes: existing migration runner API and `DatabaseSchema` table conventions.
- Produces: `class MigrationV59 { static Future<void> migrate(Database db) async; }`, registered for `58 -> 59`, creating `business_profile`, `business_capabilities`, `business_template_states`, `feature_flags`, `tax_profiles`, `document_tax_snapshots`, `document_reversals`, and `migration_runs` with the exact constraints from the spec.

- [ ] **Step 1: Write RED migration tests.**

The test must create a v58-compatible database, run `MigrationV59.migrate`, and assert all eight tables, required primary keys, unique constraints, and check constraints exist. It must also run the migration twice and assert the second run does not duplicate the singleton profile or capability rows.

```dart
test('v59 creates general platform tables and is idempotent', () async {
  final db = await openTestDatabaseAtVersion(58);
  await MigrationV59.migrate(db);
  await MigrationV59.migrate(db);

  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
    "('business_profile','business_capabilities','business_template_states',"
    "'feature_flags','tax_profiles','document_tax_snapshots',"
    "'document_reversals','migration_runs')",
  );
  expect(tables.map((row) => row['name']).toSet(), {
    'business_profile', 'business_capabilities', 'business_template_states',
    'feature_flags', 'tax_profiles', 'document_tax_snapshots',
    'document_reversals', 'migration_runs',
  });
  expect(await db.query('business_profile'), isEmpty);
  expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
});
```

- [ ] **Step 2: Run the focused migration test and verify it fails because `MigrationV59` and the new tables do not exist.**

Run: `flutter test test/database/migration_v59_general_platform_test.dart`.  
Expected: RED with a missing `MigrationV59`/table failure, not a syntax or fixture error.

- [ ] **Step 3: Implement minimal additive migration.**

Create `MigrationV59.migrate(Database db)` using `CREATE TABLE IF NOT EXISTS`, exact `CHECK` constraints, exact singleton `CHECK (id = 1)`, and indexes for document snapshot/reversal lookup. Keep all money columns INTEGER. Do not modify v2–v58 migration files. Register only `case 59` in the existing runner and set the database target version to 59 in the single current version constant.

- [ ] **Step 4: Add schema and constraint assertions, then run focused tests.**

Assert `document_tax_snapshots` has `UNIQUE(document_type, document_id)`, `document_reversals` has `UNIQUE(document_type, document_id)`, and invalid `enabled = 2` or negative `rate_bps` inserts fail. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add lib/data/datasources/migrations/migration_v59.dart lib/data/datasources/migrations/migration_runner.dart lib/data/datasources/database_helper.dart test/database/migration_v59_general_platform_test.dart
git commit -m "feat: add v59 general platform schema"
```

## Task 3: Add typed business profile repository with legacy adapter

**Files:**
- Create: `lib/data/models/business_profile_model.dart`
- Create: `lib/data/datasources/repositories/business_profile_repository.dart`
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/unit/business_profile_repository_test.dart`

**Interfaces:**
- Consumes: `DatabaseHelper`, `ReferenceDataRepository`/legacy `settings` access.
- Produces:

```dart
class BusinessProfile {
  final String? businessName;
  final String? phone;
  final String? email;
  final String? address;
  final String? logoPath;
  final String countryCode;
  final String baseCurrencyCode;
  final String locale;
  final String timezone;
  final String taxMode;
  final String setupStatus;
  final int setupVersion;
  final String source;
}

class BusinessProfileRepository {
  Future<BusinessProfile> getOrCreateProfile();
  Future<void> saveProfile(BusinessProfile profile);
  Future<bool> hasPostedFinancialData();
  Future<bool> canChangeBaseCurrency(String code);
}
```

- [ ] **Step 1: Write RED tests for new database and legacy v58 data.**

Test that an empty v59 database returns YER/YE/not_started defaults without duplicate rows; test that legacy `business_name`, `business_phone`, `business_email`, `business_address`, `business_logo_path`, and `default_currency` are read when the typed row is absent; test that saving is idempotent and preserves `setup_status`.

- [ ] **Step 2: Run the focused tests and verify missing typed model/repository failure.**

Run: `flutter test test/unit/business_profile_repository_test.dart`.  
Expected: RED because the typed model/repository is not implemented.

- [ ] **Step 3: Implement typed model and repository.**

Use an explicit row mapper, `id = 1`, parameterized SQL, and a transaction only around writes that use the same database handle. Read legacy settings outside any unrelated transaction. `hasPostedFinancialData()` must query posted invoices/transactions, not infer state from current settings. `canChangeBaseCurrency` returns true only when no posted financial data exists or the requested code equals the current code.

- [ ] **Step 4: Run focused tests plus existing reference-data tests.**

Expected: PASS; no duplicate profile row; legacy values are visible; currency guard refuses change after a posted row.

- [ ] **Step 5: Commit.**

```bash
git add lib/data/models/business_profile_model.dart lib/data/datasources/repositories/business_profile_repository.dart lib/core/di/service_locator.dart test/unit/business_profile_repository_test.dart
git commit -m "feat: add typed business profile repository"
```

## Task 4: Add capability definitions, dependency validation, and persistence

**Files:**
- Create: `lib/core/platform/capability_definition.dart`
- Create: `lib/core/platform/capability_catalog.dart`
- Create: `lib/data/models/capability_state_model.dart`
- Create: `lib/data/datasources/repositories/capability_repository.dart`
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/unit/capability_catalog_test.dart`
- Test: `test/unit/capability_repository_test.dart`

**Interfaces:**
- Consumes: v59 tables and `BusinessProfileRepository` conventions.
- Produces:

```dart
class CapabilityDefinition {
  final String code;
  final String labelAr;
  final String descriptionAr;
  final Set<String> dependencies;
  final bool isCore;
  final int priority;
}

class CapabilityCatalog {
  static const List<CapabilityDefinition> definitions;
  static CapabilityDefinition byCode(String code);
  static Set<String> resolveDependencies(Iterable<String> requested);
  static void validateNoCycles();
}

class CapabilityRepository {
  Future<Set<String>> getEnabledCodes();
  Future<void> replaceEnabledCodes(Iterable<String> codes, {required String source});
  Future<void> setEnabled(String code, bool enabled, {required String source});
  Future<bool> hasDataFor(String code);
}
```

- [ ] **Step 1: Write RED tests for the capability catalog.**

Test multi-select resolution (`transform` includes `stock`; `service` does not require a business type), unknown codes rejection, core capabilities always enabled, and cycle detection using a test-only catalog definition.

- [ ] **Step 2: Run focused catalog tests and verify RED.**

Run: `flutter test test/unit/capability_catalog_test.dart`.  
Expected: RED because catalog and dependency resolver are missing.

- [ ] **Step 3: Implement the minimal typed catalog.**

Define only the spec codes `sell`, `buy`, `stock`, `service`, `schedule`, `settle`, `transform`, and `reporting`; add core internal capabilities for security, backup, settings, and audit without exposing them as optional checkboxes. Do not add industry codes.

- [ ] **Step 4: Write RED persistence tests, then implement repository.**

Test empty state, idempotent replace, disabling a used capability keeps the row/data, and dependency-aware disabling. Use `INSERT ... ON CONFLICT`/update semantics and preserve `source`, timestamps, and definition version.

- [ ] **Step 5: Run focused tests and commit.**

```bash
git add lib/core/platform lib/data/models/capability_state_model.dart lib/data/datasources/repositories/capability_repository.dart lib/core/di/service_locator.dart test/unit/capability_catalog_test.dart test/unit/capability_repository_test.dart
git commit -m "feat: add composable capability catalog"
```

## Task 5: Add onboarding coordinator and startup gate

**Files:**
- Create: `lib/core/platform/onboarding_state.dart`
- Create: `lib/core/services/onboarding_coordinator.dart`
- Create: `lib/ui/screens/onboarding/onboarding_screen.dart`
- Create: `lib/ui/screens/onboarding/widgets/onboarding_step_shell.dart`
- Modify: `lib/main.dart`
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/unit/onboarding_coordinator_test.dart`
- Test: `test/widget/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: profile/capability repositories and existing license/PIN startup flow.
- Produces:

```dart
enum OnboardingStep { welcome, identity, locale, capabilities, tax, review }

class OnboardingCoordinator extends ChangeNotifier {
  OnboardingStep get currentStep;
  Future<void> load();
  Future<void> saveIdentity(...);
  Future<void> saveLocale({required String countryCode, required String baseCurrencyCode});
  Future<void> saveCapabilities(Set<String> codes);
  Future<void> saveTaxMode(String taxMode);
  Future<void> complete();
}
```

- [ ] **Step 1: Write RED coordinator tests.**

Test new profile starts at `welcome`, interrupted onboarding resumes at the saved step, completing twice is idempotent, and onboarding writes no invoices, transactions, stock movements, or journal rows.

- [ ] **Step 2: Run focused coordinator tests and verify RED.**

Run: `flutter test test/unit/onboarding_coordinator_test.dart`.  
Expected: RED due to missing coordinator/state.

- [ ] **Step 3: Implement coordinator with atomic persistence.**

Store `setup_status` and `setup_version` in `business_profile`; save each step only after validation. `complete()` requires at least one operational capability, writes final state once, and never creates financial rows. Country defaults to `YE`, base currency to `YER`, and tax mode to `none` until user confirmation.

- [ ] **Step 4: Write RED widget tests, implement screen, and verify.**

Mount the real screen with test repositories. Assert Arabic labels, multi-select checkboxes, back/next behavior, no exclusive business-type radio, validation errors, and resume state. Include loading, error, and retry states. Expected: focused widget tests PASS after implementation.

- [ ] **Step 5: Integrate `main.dart` startup gate and commit.**

After splash/license/PIN eligibility, resolve profile status: `not_started`/`in_progress` -> onboarding; `completed` -> MainScaffold. Do not block splash on non-critical alert/recurring background tasks. Register coordinator in GetIt.

```bash
git add lib/core/platform/onboarding_state.dart lib/core/services/onboarding_coordinator.dart lib/ui/screens/onboarding lib/main.dart lib/core/di/service_locator.dart test/unit/onboarding_coordinator_test.dart test/widget/onboarding_screen_test.dart
git commit -m "feat: add resumable business onboarding"
```

## Task 6: Add visibility policy and dynamic navigation catalog

**Files:**
- Create: `lib/core/platform/feature_visibility_service.dart`
- Create: `lib/ui/navigation/navigation_definition.dart`
- Create: `lib/ui/navigation/navigation_catalog.dart`
- Create: `lib/ui/screens/settings/business_capabilities_screen.dart`
- Modify: `lib/ui/navigation/main_scaffold.dart`
- Modify: `lib/ui/navigation/app_router.dart`
- Modify: `lib/ui/screens/settings/settings_screen.dart`
- Test: `test/unit/feature_visibility_service_test.dart`
- Test: `test/widget/capability_navigation_widget_test.dart`

**Interfaces:**
- Consumes: enabled capabilities, `CapabilityRepository`, existing route constants and screens.
- Produces:

```dart
class NavigationDefinition {
  final String route;
  final String labelAr;
  final IconData icon;
  final Set<String> requiredCapabilities;
  final bool isCore;
  final int priority;
}

class FeatureVisibilityService extends ChangeNotifier {
  Future<void> load();
  bool isVisible(Set<String> requiredCapabilities, {required bool isCore});
  bool canDisable(String code);
  Future<void> setEnabled(String code, bool enabled);
}
```

- [ ] **Step 1: Write RED policy and widget tests.**

Test core routes are always visible; a disabled capability hides only its navigation entries; a used capability cannot be deleted; a hidden route can be opened through a guard that offers “إظهار الميزة” or back; enabling a dependency also enables required dependencies.

- [ ] **Step 2: Run focused tests and verify RED.**

Run: `flutter test test/unit/feature_visibility_service_test.dart test/widget/capability_navigation_widget_test.dart`.  
Expected: RED because catalog/service/screen do not exist.

- [ ] **Step 3: Implement central catalog and policy.**

Move route metadata out of `_drawerSections`; do not delete route constants. Map existing routes to required capabilities: POS/sales to `sell`, purchases to `buy`, products/warehouses/adjustments to `stock`, service orders to `service`, shifts/scheduling to `schedule`, cash/debts/payments to `settle`, production/recipes to `transform`, and reports/settings/backup/audit to core/reporting.

- [ ] **Step 4: Implement settings capability screen and guarded navigation.**

Show all optional capabilities with explanatory text and dependency/data warnings. Disabling only changes visibility; it never deletes rows. Add loading/empty/error/retry states and preserve Arabic RTL styling.

- [ ] **Step 5: Run widget tests and commit.**

```bash
git add lib/core/platform/feature_visibility_service.dart lib/ui/navigation/navigation_definition.dart lib/ui/navigation/navigation_catalog.dart lib/ui/screens/settings/business_capabilities_screen.dart lib/ui/navigation/main_scaffold.dart lib/ui/navigation/app_router.dart lib/ui/screens/settings/settings_screen.dart test/unit/feature_visibility_service_test.dart test/widget/capability_navigation_widget_test.dart
git commit -m "feat: add capability-driven navigation"
```

## Task 7: Replace fixed dashboard actions with progressive disclosure

**Files:**
- Create: `lib/ui/dashboard/action_definition.dart`
- Create: `lib/ui/dashboard/action_catalog.dart`
- Modify: `lib/ui/screens/dashboard/dashboard_screen.dart`
- Modify: `lib/core/viewmodels/dashboard_viewmodel.dart`
- Test: `test/unit/action_catalog_test.dart`
- Test: `test/widget/dashboard_capability_actions_test.dart`

**Interfaces:**
- Consumes: `FeatureVisibilityService`, existing dashboard metrics and route constants.
- Produces:

```dart
class ActionDefinition {
  final String key;
  final String labelAr;
  final IconData icon;
  final String route;
  final Set<String> requiredCapabilities;
  final int priority;
  final bool isCore;
}

class ActionCatalog {
  static List<ActionDefinition> visibleActions(Set<String> enabledCodes);
  static List<ActionDefinition> prioritizedActions(Set<String> enabledCodes, {int limit = 6});
}
```

- [ ] **Step 1: Write RED action catalog tests.**

Assert that a retail-like selection gets sale/product/purchase actions without showing service/production; a service+stock selection gets service/parts actions; core settings/reporting remain available; output is capped at six primary actions and contains no duplicate routes.

- [ ] **Step 2: Run focused tests and verify RED.**

Run: `flutter test test/unit/action_catalog_test.dart test/widget/dashboard_capability_actions_test.dart`.  
Expected: RED because the catalog is missing and dashboard is still fixed.

- [ ] **Step 3: Implement catalog and dashboard integration.**

Replace `_allActions` with catalog output while preserving existing dashboard metrics. Keep a “كل الوظائف” entry to the dynamic drawer. Remove the fixed 3×3/page assumption only after widget tests cover small and large action counts. Keep loading/error/empty states for metrics and actions.

- [ ] **Step 4: Run widget tests and inspect build warnings.**

Expected: PASS; no overflow on 320px width, no duplicate key/route, and no hard-coded business-type condition.

- [ ] **Step 5: Commit.**

```bash
git add lib/ui/dashboard lib/ui/screens/dashboard/dashboard_screen.dart lib/core/viewmodels/dashboard_viewmodel.dart test/unit/action_catalog_test.dart test/widget/dashboard_capability_actions_test.dart
git commit -m "feat: add progressive capability dashboard"
```

## Task 8: Separate tax policy from currency and add document snapshots

**Files:**
- Create: `lib/data/models/tax_profile_model.dart`
- Create: `lib/data/models/document_tax_snapshot_model.dart`
- Create: `lib/data/datasources/repositories/tax_policy_repository.dart`
- Create: `lib/core/finance/tax_policy_resolver.dart`
- Modify: `lib/core/viewmodels/invoice_viewmodel.dart`
- Modify: `lib/core/viewmodels/pos_viewmodel.dart`
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/unit/tax_policy_resolver_test.dart`
- Test: `test/integration/document_tax_snapshot_test.dart`

**Interfaces:**
- Consumes: `InvoiceTotalsEngine`, existing currency data, v59 tax tables.
- Produces:

```dart
class TaxPolicyResolver {
  Future<TaxProfile?> resolveFor({required DateTime date, required String countryCode});
  DocumentTaxSnapshot snapshotFor(TaxProfile? profile, TotalsResult totals, {...});
}

class TaxPolicyRepository {
  Future<List<TaxProfile>> listForCountry(String countryCode);
  Future<int> save(TaxProfile profile);
  Future<DocumentTaxSnapshot?> getSnapshot(String documentType, String documentId);
}
```

- [ ] **Step 1: Write RED tests.**

Test that current currency VAT is not used as a new tax source, 500 basis points means 5.00%, dated policies resolve correctly, no-policy mode returns zero tax without inventing a rate, and a saved document snapshot stays unchanged after the current policy changes.

- [ ] **Step 2: Run focused tests and verify RED.**

Run: `flutter test test/unit/tax_policy_resolver_test.dart test/integration/document_tax_snapshot_test.dart`.  
Expected: RED due to missing typed tax models/resolver.

- [ ] **Step 3: Implement minimal resolver/repository and invoice integration.**

Use parameterized queries and INTEGER minor units. Do not hard-code Yemen tax rates. New invoices receive an explicit snapshot; legacy invoices receive a legacy snapshot only when needed for display, using stored `tax_amount` without reverse inference. Resolve currency offset before any posting transaction.

- [ ] **Step 4: Run accounting regression tests.**

Run existing invoice/return/payment suites plus focused tests. Expected: all old totals unchanged; new snapshots are unique and immutable.

- [ ] **Step 5: Commit.**

```bash
git add lib/data/models/tax_profile_model.dart lib/data/models/document_tax_snapshot_model.dart lib/data/datasources/repositories/tax_policy_repository.dart lib/core/finance/tax_policy_resolver.dart lib/core/viewmodels/invoice_viewmodel.dart lib/core/viewmodels/pos_viewmodel.dart lib/core/di/service_locator.dart test/unit/tax_policy_resolver_test.dart test/integration/document_tax_snapshot_test.dart
git commit -m "feat: add dated tax policy snapshots"
```

## Task 9: Route all invoice-like totals through the canonical engine

**Files:**
- Modify: `lib/data/datasources/services/recurring_invoice_service.dart`
- Modify: `lib/data/datasources/repositories/invoice_repository.dart` only where snapshot/posting integration is required
- Test: `test/regression/f03_recurring_invoices_test.dart`
- Test: `test/integration/recurring_invoice_totals_engine_test.dart`

**Interfaces:**
- Consumes: `InvoiceTotalsEngine`, tax resolver/snapshot, existing recurring invoice schema and deterministic run IDs.
- Produces: recurring generation whose `subtotal`, `discount`, `tax`, `transport`, `total`, `paid`, and `remaining` are derived from one canonical totals result.

- [ ] **Step 1: Write RED recurring totals tests.**

Create a template with fractional minor-unit-sensitive prices, discount, taxable transport, and a dated policy. Assert generated invoice totals exactly equal `InvoiceTotalsEngine` output and that rerunning the same scheduled date does not create a second invoice/run.

- [ ] **Step 2: Run focused tests and verify the current double calculation fails.**

Run: `flutter test test/regression/f03_recurring_invoices_test.dart test/integration/recurring_invoice_totals_engine_test.dart`.  
Expected: RED on the engine-equality assertion, demonstrating the old `double` calculation is still active.

- [ ] **Step 3: Implement minimal integration.**

Build `TotalsInput` from template items, resolve tax before transaction, call the engine, map minor units to stored money fields through existing helpers, and pass the result into the standard invoice repository. Keep deterministic ID and recovery behavior. Do not introduce a second totals formula.

- [ ] **Step 4: Run recurring and existing invoice tests.**

Expected: PASS; no nested DB access; all old recurring CRUD tests remain green.

- [ ] **Step 5: Commit.**

```bash
git add lib/data/datasources/services/recurring_invoice_service.dart lib/data/datasources/repositories/invoice_repository.dart test/regression/f03_recurring_invoices_test.dart test/integration/recurring_invoice_totals_engine_test.dart
git commit -m "fix: use canonical totals for recurring invoices"
```

## Task 10: Add non-destructive document lifecycle and cancellation guard

**Files:**
- Create: `lib/core/finance/document_lifecycle_service.dart`
- Create: `lib/data/models/document_reversal_model.dart`
- Modify: `lib/data/datasources/services/cash_box_service.dart`
- Modify: `lib/data/datasources/repositories/invoice_repository.dart`
- Modify: relevant voucher models/repository files discovered during implementation
- Modify: `lib/core/di/service_locator.dart`
- Test: `test/integration/document_lifecycle_test.dart`
- Test: `test/regression/cancellation_immutability_test.dart`

**Interfaces:**
- Consumes: journal helpers, fiscal-period guards, invoice/cash-box reversal paths, v59 reversal table.
- Produces:

```dart
enum DocumentStatus { draft, posted, partiallySettled, settled, cancelled }

class DocumentLifecycleService {
  Future<void> cancelInvoice(String id, {required String reason});
  Future<void> cancelVoucher(String id, {required String reason});
  Future<bool> canDeleteDraft(String documentType, String id);
}
```

- [ ] **Step 1: Write RED cancellation tests.**

Create a posted sale with stock and partial payment, cancel it, and assert the original invoice, original journal rows, original stock movement, tax snapshot, and payment history remain. Assert exactly one reversal exists, balances/stock are reversed once, and a second cancel is rejected/idempotent. Test posted voucher deletion is rejected and draft deletion remains possible only without dependencies.

- [ ] **Step 2: Run focused tests and verify current destructive voucher path fails.**

Run: `flutter test test/integration/document_lifecycle_test.dart test/regression/cancellation_immutability_test.dart`.  
Expected: RED on original-row retention or voucher deletion assertion.

- [ ] **Step 3: Implement lifecycle service and adapt existing methods.**

Move cancellation orchestration out of UI/service-specific branches. Resolve all read-only dependencies before opening the transaction. Inside one transaction, lock by status, create one exact reversal journal linked to the original, reverse stock/cost/entity/cash effects, insert `document_reversals`, and set cancellation metadata. Refuse closed fiscal periods. Replace destructive `deleteVoucher` behavior for posted vouchers with lifecycle cancellation while preserving a compatibility method that returns a clear error for forbidden deletion.

- [ ] **Step 4: Run all accounting regression tests and check balance invariants.**

Expected: balanced journals, no negative accidental double-reversal, unchanged historical values, no `LIKE` broad matching.

- [ ] **Step 5: Commit.**

```bash
git add lib/core/finance/document_lifecycle_service.dart lib/data/models/document_reversal_model.dart lib/data/datasources/services/cash_box_service.dart lib/data/datasources/repositories/invoice_repository.dart lib/core/di/service_locator.dart test/integration/document_lifecycle_test.dart test/regression/cancellation_immutability_test.dart
git commit -m "fix: preserve documents during cancellation"
```

## Task 11: Complete migration upgrade coordinator and recovery checks

**Files:**
- Create: `lib/core/services/upgrade_coordinator.dart`
- Create: `lib/ui/screens/recovery/database_recovery_screen.dart`
- Modify: `lib/main.dart`
- Modify: `lib/core/services/portable_backup_service.dart` only for pre-upgrade snapshot hooks
- Test: `test/integration/upgrade_coordinator_test.dart`
- Test: `test/integration/portable_backup_roundtrip_test.dart`

**Interfaces:**
- Consumes: database helper, migration runner, portable backup staging/HMAC/integrity/rollback, profile setup state.
- Produces:

```dart
class UpgradeCoordinator {
  Future<UpgradeResult> prepareAndValidate();
}

class UpgradeResult {
  final bool success;
  final bool recoveryRequired;
  final int fromVersion;
  final int toVersion;
  final String? errorCode;
}
```

- [ ] **Step 1: Write RED upgrade tests.**

Test v58 fixture upgrades to current schema with data preserved, migration status is recorded, integrity and foreign-key checks are empty, a repeated validation is safe, and injected migration failure yields `recoveryRequired` without MainScaffold eligibility.

- [ ] **Step 2: Run focused tests and verify RED.**

Run: `flutter test test/integration/upgrade_coordinator_test.dart`.  
Expected: RED because coordinator/recovery screen do not exist.

- [ ] **Step 3: Implement coordinator and recovery state.**

Create a pre-upgrade encrypted snapshot using existing portable backup primitives, run the normal versioned upgrade path, perform schema/invariant checks, and mark `migration_runs`. Do not create a nested transaction inside sqflite migration callbacks. On failure preserve the original and expose recovery actions; do not silently overwrite or delete the user database.

- [ ] **Step 4: Integrate startup and run backup round-trip tests.**

`main.dart` must wait for upgrade validation before onboarding/MainScaffold. Existing non-critical background scans run only after a successful entry state. Expected: PASS for restore of database and attachments with integrity checks.

- [ ] **Step 5: Commit.**

```bash
git add lib/core/services/upgrade_coordinator.dart lib/ui/screens/recovery/database_recovery_screen.dart lib/main.dart lib/core/services/portable_backup_service.dart test/integration/upgrade_coordinator_test.dart test/integration/portable_backup_roundtrip_test.dart
git commit -m "feat: add local database upgrade recovery"
```

## Task 12: Finish full frontend integration and UI quality pass

**Files:**
- Modify: `lib/ui/screens/settings/settings_screen.dart`
- Modify: `lib/ui/screens/settings/widgets/settings_profile_section.dart`
- Modify: `lib/ui/navigation/main_scaffold.dart`
- Modify: `lib/ui/screens/dashboard/dashboard_screen.dart`
- Modify: affected ViewModels and route screens from Tasks 5–11
- Test: `test/widget/general_platform_acceptance_test.dart`

**Interfaces:**
- Consumes: all stable services/catalogs from prior tasks.
- Produces: a coherent Arabic RTL flow with no dead routes, loading/empty/error/retry states, mobile-safe layout, and direct links between capability choice, dashboard, navigation, settings, and workflows.

- [ ] **Step 1: Write RED end-to-end widget acceptance tests.**

Cover new install onboarding, resume after interruption, selecting multiple capabilities, hiding and re-enabling a used capability, opening a hidden route, and dashboard action changes. Use real repositories with an in-memory database; avoid tests that only assert mocks were called.

- [ ] **Step 2: Run focused widget tests and verify RED.**

Run: `flutter test test/widget/general_platform_acceptance_test.dart`.  
Expected: RED on missing full integration/old fixed dashboard behavior.

- [ ] **Step 3: Implement integration without duplicating business logic.**

Replace legacy profile write paths with typed repository writes while maintaining legacy reads. Add a settings entry for capabilities and guarded links. Keep core backup/security/reporting visible. Ensure all user-facing text is Arabic, all forms validate, and all screens have loading/empty/error/retry states. Keep files focused; extract widgets rather than expanding `MainScaffold` or `DashboardScreen` with repeated conditionals.

- [ ] **Step 4: Run widget acceptance and static checks.**

Expected: PASS with no overflow, missing localization, route, or duplicate-key warnings. Verify 320px, 768px, 1024px, and Android RTL behavior in CI/device job where available.

- [ ] **Step 5: Commit.**

```bash
git add lib/ui test/widget/general_platform_acceptance_test.dart
 git commit -m "feat: complete capability-aware Flutter experience"
```

## Task 13: Full verification, review, documentation, and CI release gate

**Files:**
- Create: `docs/superpowers/assessments/2026-08-26-general-platform-implementation-report.md`
- Modify: relevant `docs/` test/run documentation only after implementation is verified
- Test: all existing and new test suites

**Interfaces:**
- Consumes: all implementation tasks and acceptance criteria.
- Produces: verified CI run, review report, migration compatibility matrix, and release notes; no unverified completion claim.

- [ ] **Step 1: Run local non-Flutter static checks only.**

Run: `git diff --check`, `git status --short`, and repository searches for forbidden patterns such as `businessType ==`, tax calculations using `double` in invoice-like paths, destructive deletes on posted documents, and nested `BaseCurrencyService` access in transactions. Do not claim Flutter success locally.

- [ ] **Step 2: Run the complete CI workflow.**

Push the implementation commits to `origin/main`; monitor Android Release workflow until completed. Require Flutter analyze, all tests, APK/AAB builds, signing verification, fingerprints, and artifact uploads to succeed.

- [ ] **Step 3: Perform the five-axis review.**

Review tests first, then implementation for correctness, readability, architecture, security, and performance. Specifically check SQL parameterization, no secrets/log leakage, no N+1 dashboard queries, bounded lists, explicit typed boundaries, and no feature logic leaking into shared database helpers.

- [ ] **Step 4: Run final CI after any review fix.**

Expected: latest HEAD is clean, CI conclusion is `success`, and the run SHA equals the final commit. If any test or review gate fails, stop claiming completion and fix through a new RED/GREEN cycle.

- [ ] **Step 5: Commit documentation and deliver.**

```bash
git add docs/superpowers/assessments/2026-08-26-general-platform-implementation-report.md docs/
git commit -m "docs: record general platform verification"
git push origin main
```

The final report must state exactly which migrations, tests, CI run, Android artifacts, and limitations were verified. Import from Excel/external systems, synchronization, multi-user roles, and free workflow builder remain explicitly out of scope.

---

## Plan self-review

The plan covers the spec's data model, compatibility adapter, progressive disclosure, capability combinations, onboarding, navigation, dashboard, tax separation, canonical totals, non-destructive cancellation, migration snapshots/rollback, error states, acceptance scenarios, Android UI integration, and CI gate. Each production change begins with a failing behavior test, has a focused green step, and is committed as a reviewable slice. No task edits migrations v2–v58 or assumes local Flutter availability. The first implementation task is deliberately a baseline only; no code production change starts until its RED/GREEN test seam is established.
