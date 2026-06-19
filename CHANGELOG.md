# Changelog

All notable changes to **FirstPro Accounting** (الأول برو المحاسبي) are
documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For the active audit / task reference, see `agent-ctx/AUDIT.md` (gitignored,
local-only). For the engineering constitution, see `AGENTS.md`.

## [Unreleased]

### Added
- **VAT Return report (A-04)**: new `VatReturnScreen` and three
  `ReportService` methods (`getVatReturnSummary`, `getVatReturnDetails`,
  `getVatNetPayable`) for filing Value-Added Tax returns. Covers Output VAT
  (sale/POS invoices, posted to account 2300+offset) and Input VAT (purchase
  invoices, posted to account 1400+offset), with the net payable or
  refundable per currency. Returns are signed negative so net VAT reflects
  the true amount after returns. Excel export supported. Accessible from
  Reports → المحاسبة والمالية → إقرار ضريبة القيمة المضافة.
- **ThemeProvider (U-01)**: app-wide reactive theme mode controller. Theme
  changes in Settings now apply instantly without an app restart.
- **Record count cache (T-02)**: `LicenseService._getTotalRecordCount` now
  caches the count for 60 seconds, eliminating 4 `COUNT(*)` queries on every
  `canAddRecord()` call. The cache is invalidated explicitly after a
  successful record insert (product/customer/invoice/expense).

### Changed
- **Sale return weighted-average cost (A-01)**: returned goods are now
  valued at their ORIGINAL unit cost (captured in `invoice_items.unit_cost`
  at sale time) and `average_cost` is recomputed, instead of using the
  current `average_cost`. Fixes accounting drift when the average cost
  changed between sale and return.
- **Orphan invoice detection (B-03)**: `AuditService.getOrphanedInvoices`
  now uses a `LEFT JOIN` on `transactions.reference_id` /
  `reference_type` instead of `description LIKE '%invoiceId%'`. Faster
  (uses index) and more accurate (no false positives from substring
  matches).
- **License state save (T-01)**: `LicenseService._saveState` now uses
  `INSERT OR REPLACE` (atomic UPSERT) instead of `DELETE-then-INSERT`.
  Eliminates the window where a transient DB write failure could lose the
  user's license state.
- **Annual posting (A-03)**: `performAnnualPosting` now auto-creates the
  Retained Earnings account (2910+offset) and its Equity root (2900+offset)
  for any currency that has activity but no Equity accounts, instead of
  silently skipping that currency's closing entries.

### Fixed
- **SAR VAT rate on fresh install (B-04)**: `DatabaseSeeds.seedCurrencies`
  now seeds SAR with `vat_rate = 15.0` (matching `migration_v52.dart`).
  Previously, fresh installs silently skipped VAT on Saudi invoices because
  the seed value was 0.0 while existing databases (upgraded via v52) had
  15.0. The fix also documents that `vat_rate` is stored as a PERCENTAGE
  (15.0 = 15%), not a fraction (0.15).
- **Theme not reactive (U-01)**: changing the theme mode in Settings
  previously required an app restart to take effect. Now applies instantly
  via `ThemeProvider` + `ListenableBuilder` in `main.dart`.

### Removed
- **Orphan InventoryVoucherScreen (B-01)**: deleted the duplicate
  `lib/ui/screens/inventory/inventory_voucher_screen.dart` (543 lines, never
  imported). The canonical screen at `lib/ui/screens/vouchers/` is the only
  one used.
- **Orphan ThermalPrinterService (B-02)**: deleted
  `lib/core/services/thermal_printer_service.dart` (378 lines, never called
  from any screen). `BluetoothPrinterService` (SPP) is the only active
  printer service.
- **Deprecated AppConstants.currency / currencyEn (T-04)**: removed the
  mutable global constants that conflicted with the dynamic per-currency
  model. Use `CurrencyConstants.currencySymbol(code)` /
  `CurrencyConstants.currencyOptions` instead.

### Documentation
- **A-02**: documented that Exchange Gains (4700) and Losses (5300)
  accounts are correctly created in YER only (per IAS 21), with no
  per-currency offset. Added explanatory comment in
  `getOrCreateExchangeAccount` to prevent future "fixes" that would
  incorrectly add offsets.
- **A-05**: documented that `_handleExchangeDifference` correctly handles
  multi-currency settlement per IAS 21 — exchange differences are
  recognized in the functional currency (YER) using current rates from the
  currencies table.
- **T-03**: documented that the `balance_type = 'auto'` branches in
  `updateAccountBalance` / `updateAccountBalanceWithJournal` are defensive
  fallbacks (migration v50 resolved all 'auto' values; branches should
  never execute on a v50+ database).
- **AUDIT.md**: created the active audit reference at `agent-ctx/AUDIT.md`
  (gitignored) to replace the archived `docs/audit_report.md` and
  `docs_archive_AUDIT_REPORT_v1.md` (both deleted).
- **AGENTS.md**: updated sections 14 (worklog path) and 15 (audit reference
  path) to point to the new local-only locations.

### Tests
- Added regression guards for all fixes above:
  - `test/regression/architecture_dedup_guards_test.dart` (B-01, B-02, T-04)
  - `test/regression/a01_sale_return_weighted_average_test.dart`
  - `test/regression/b03_orphan_invoices_reference_id_test.dart`
  - `test/regression/b04_sar_vat_rate_seed_consistency_test.dart`
  - `test/regression/a04_vat_return_report_test.dart`
  - `test/regression/t01_license_save_state_upsert_test.dart`
  - `test/regression/t02_record_count_cache_test.dart`
  - `test/regression/a03_annual_posting_retained_earnings_test.dart`
  - `test/unit/theme/theme_provider_test.dart`
- Total test count: ~625+ (up from ~575 at the start of this cycle).
- All tests pass on CI (analyze + test + build APK + build AAB).

### CI
- All 4 commits in this cycle passed GitHub Actions:
  - Run #311: ✅ analyze + test + APK + AAB
  - Run #312: ✅ analyze + test
  - Run #313: ✅ analyze + test
  - Run #314: ✅ analyze + test + APK

## [2.0.0+2] — 2026-06-12

### Summary
The first audited release of FirstPro Accounting 2.0. This release
established the engineering constitution (`AGENTS.md`), completed the
IAS 2/21 compliance work (B-1.6), the per-currency dynamic model
(B-1.7), and the ×100 money-conversion bug fix (A-10).

### Added
- Double-entry bookkeeping with full chart of accounts (multi-currency).
- FIFO / LIFO / Weighted-Average costing with reversible cost layers.
- POS with shifts, held orders, multi-payment, deferred journal posting.
- Vouchers: receipt, payment, settlement, general entry, inventory.
- Bank reconciliation with auto-match.
- Currency exchange with gain/loss accounting.
- SQLCipher-encrypted database with key in Android Keystore.
- License server validation with 7-day offline grace period.
- PIN + biometric app lock.
- PDF invoice generation + Bluetooth ESC/POS thermal printing (80mm/58mm).
- Excel export for reports.
- 575+ tests covering accounting logic, migrations, regressions.

### Database
- Schema version 53 (cumulative migrations v2 through v53).
- INTEGER cents storage for all monetary columns (v34 conversion).
- `reference_type` / `reference_id` source-linking pattern (v46).
- `amount_base` for multi-currency reporting (v49).
- `balance_type` resolved from 'auto' to 'debit'/'credit' (v50).
- Per-currency `code_offset` and `base_code` (v51).
- Per-currency `vat_rate` (v52) and `default_currency` setting (v53).

---

## Versioning Policy

- **Major** (X.0.0): breaking changes (e.g. schema redesign, removed
  features).
- **Minor** (0.X.0): new features, backward-compatible (e.g. new report,
  new screen).
- **Patch** (0.0.X): bug fixes, backward-compatible.

The build number (+N) is incremented for each release build on CI.
